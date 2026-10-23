import Accompaniment
import AVFAudio
import MusicTheory
import Observation
import os
import PitchDetection
import PracticeEngine
import QuartzCore

private let logger = Logger(subsystem: "PitchCoach", category: "AudioPipeline")

/// 管理 AVAudioSession 與 AVAudioEngine，把偵測結果以螢幕更新頻率分送給畫面（docs/ARCHITECTURE.md §3）。
///
/// - 收音：內建麥克風 → inputNode → AVAudioSinkNode（IO 執行緒做 MPM）→ RealtimeMailbox → 主執行緒
/// - 伴奏：Drone／Metronome AVAudioSourceNode → mainMixerNode → 喇叭／有線／藍牙 A2DP
/// - 中斷：系統通知轉成 `AudioSessionEvent`，由 `AudioInterruptionPolicy` 決定要暫停、重建或通知練習中斷
@MainActor
@Observable
final class AudioPipeline {
    enum State: Equatable {
        case idle
        case running
        /// 被來電、其他 App 等中斷，或 App 在背景。
        case suspended
        case permissionDenied
        case failed(String)
    }

    enum PipelineError: LocalizedError {
        case noInputAvailable

        var errorDescription: String? {
            switch self {
            case .noInputAvailable: "找不到可用的麥克風。"
            }
        }
    }

    private(set) var state: State = .idle
    private(set) var sampleRate: Double?
    /// 分析窗結束到畫面顯示的延遲（不含硬體輸入延遲）。
    private(set) var latency = LatencyStatistics()
    /// 硬體輸入延遲（AVAudioSession.inputLatency + IO buffer）。
    private(set) var hardwareInputLatency: Double = 0
    /// 最近一個 IO buffer 的輸入電平（dBFS）。
    private(set) var inputLevelDB: Float = -.infinity
    /// 啟動後收到的分析 frame 總數（除錯用）。
    private(set) var receivedFrameCount = 0
    /// 伴奏目前從內建喇叭播放（麥克風會收到伴奏，建議戴耳機）。
    private(set) var isOutputBuiltInSpeaker = false
    /// iOS 回報的輸入／輸出延遲（秒），歌唱模式的時間對齊使用。
    private(set) var inputLatency: Double = 0
    private(set) var outputLatency: Double = 0
    /// 目前輸出路由的識別（埠類型＋UID），作為延遲校正值的索引。
    private(set) var routeKey = ""
    private(set) var routeName = ""
    /// 開發用：目前的輸入與輸出埠（名稱與類型），確認收音一律使用內建麥克風。
    private(set) var routeDescription = ""
    /// 歌唱模式提出：用喇叭外放時啟用回音消除（docs/SINGING_MODE.md §8）。
    var prefersVoiceProcessing = false {
        didSet {
            if prefersVoiceProcessing != oldValue, state == .running { scheduleRestart() }
        }
    }
    private(set) var isVoiceProcessingActive = false
    var songPlayerSettings = SongPlayerSettings() {
        didSet { songPlayer?.settings.set(songPlayerSettings) }
    }

    var drone = DroneSettings() {
        didSet { droneSynthesizer?.settings.set(drone) }
    }
    var metronome = MetronomeSettings() {
        didSet { metronomeSynthesizer?.settings.set(metronome) }
    }

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var captureContext: RealtimeCaptureContext?
    @ObservationIgnored private var droneSynthesizer: DroneSynthesizer?
    @ObservationIgnored private var metronomeSynthesizer: MetronomeSynthesizer?
    @ObservationIgnored private var songPlayer: SongPlayer?
    @ObservationIgnored private var songEventHandlers: [UUID: @MainActor (SongPlayer.Report) -> Void] = [:]
    @ObservationIgnored private var frameHandlers: [UUID: @MainActor (PitchFrame) -> Void] = [:]
    @ObservationIgnored private var timedFrameHandlers: [UUID: @MainActor (PitchFrame, Double) -> Void] = [:]
    @ObservationIgnored private var interruptionHandlers: [UUID: @MainActor (PracticeInterruptionReason) -> Void] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var pendingRestart: Task<Void, Never>?
    @ObservationIgnored private var voiceProcessingGuard = VoiceProcessingGuard()
    /// 歌唱伴奏播放中（playSong 到歌曲結束或 stopSong）。
    @ObservationIgnored private var isSongPlaying = false
    #if DEBUG
    @ObservationIgnored private var syntheticSource: SyntheticInputSource?
    @ObservationIgnored private var syntheticSong: SyntheticSongScript?
    @ObservationIgnored private var syntheticSongTask: Task<Void, Never>?
    #endif
    @ObservationIgnored private lazy var displayLink = DisplayLinkDriver { [weak self] target in
        self?.deliverFrames(displayTime: target)
    }

    init() {
        observeSystemNotifications()
    }

    // MARK: - 訂閱

    func addFrameHandler(_ handler: @escaping @MainActor (PitchFrame) -> Void) -> UUID {
        let id = UUID()
        frameHandlers[id] = handler
        return id
    }

    func removeFrameHandler(_ id: UUID) {
        frameHandlers[id] = nil
        timedFrameHandlers[id] = nil
    }

    /// 歌唱模式：同時取得分析窗結束的 host time（秒），用來換算歌曲時間。
    func addTimedFrameHandler(_ handler: @escaping @MainActor (PitchFrame, Double) -> Void) -> UUID {
        let id = UUID()
        timedFrameHandlers[id] = handler
        return id
    }

    /// 練習畫面用：收音被中斷時以原因通知，讓進行中的練習標記為「中斷」。
    func addInterruptionHandler(_ handler: @escaping @MainActor (PracticeInterruptionReason) -> Void) -> UUID {
        let id = UUID()
        interruptionHandlers[id] = handler
        return id
    }

    func removeInterruptionHandler(_ id: UUID) {
        interruptionHandlers[id] = nil
    }

    /// 歌唱模式：歌曲起點被播放、歌曲結束時通知。
    func addSongEventHandler(_ handler: @escaping @MainActor (SongPlayer.Report) -> Void) -> UUID {
        let id = UUID()
        songEventHandlers[id] = handler
        return id
    }

    func removeSongEventHandler(_ id: UUID) {
        songEventHandlers[id] = nil
    }

    func playSong(_ score: SongPlayerScore) {
        isSongPlaying = true
        #if DEBUG
        if let syntheticSong {
            playSyntheticSong(score, script: syntheticSong)
            return
        }
        #endif
        songPlayer?.play(score)
    }

    func stopSong() {
        isSongPlaying = false
        #if DEBUG
        syntheticSongTask?.cancel()
        syntheticSong?.set(nil)
        #endif
        songPlayer?.stop()
    }

    // MARK: - 啟動與停止

    func start() async {
        guard state != .running else { return }
        if !usesSyntheticInput {
            guard await ensureRecordPermission() else {
                state = .permissionDenied
                return
            }
        }
        restartNow()
    }

    /// UI 測試以合成訊號取代麥克風（只在 DEBUG 組態可用），不需要麥克風權限。
    private var usesSyntheticInput: Bool {
        #if DEBUG
        SyntheticScenario.fromLaunchArguments() != nil
        #else
        false
        #endif
    }

    /// 使用者在「收音已暫停」畫面按「恢復」。
    func resume() {
        restartNow()
    }

    /// App 前景／背景切換（由 scenePhase 呼叫）。
    func handle(_ event: AudioSessionEvent) {
        let status: AudioInterruptionPolicy.PipelineStatus = switch state {
        case .running: .running
        case .suspended, .failed: .suspended
        case .idle, .permissionDenied: .idle
        }
        if event == .engineConfigurationChanged {
            voiceProcessingGuard.engineStoppedItself(at: CACurrentMediaTime(), route: routeKey)
            if isVoiceProcessingActive && !voiceProcessingGuard.allowsVoiceProcessing(on: routeKey) {
                logger.error("回音消除在此路由無法穩定運作（引擎啟動後隨即停止），改用不消除的模式：\(self.routeKey)")
            }
        }
        if case .routeChanged = event { refreshRouteDescription() }
        let commands = AudioInterruptionPolicy.commands(for: event, status: status, isSongPlaying: isSongPlaying)
        if !commands.isEmpty {
            logger.info("事件 \(String(describing: event)) → \(String(describing: commands))")
        }
        for command in commands {
            switch command {
            case .interruptPractice(let reason):
                for handler in interruptionHandlers.values { handler(reason) }
            case .suspend:
                suspend()
            case .restart:
                scheduleRestart()
            case .pauseAccompaniment:
                drone.isEnabled = false
                metronome.isEnabled = false
            }
        }
    }

    private func suspend() {
        pendingRestart?.cancel()
        displayLink.stop()
        tearDownEngine()
        state = .suspended
    }

    /// 路由變更與引擎設定變更常常接連發生，合併成一次重建。
    private func scheduleRestart() {
        pendingRestart?.cancel()
        pendingRestart = Task { [weak self] in
            // sleep 只會因取消而丟出錯誤，取消時由下一行結束
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.restartNow()
        }
    }

    private func restartNow() {
        pendingRestart?.cancel()
        displayLink.stop()
        tearDownEngine()
        #if DEBUG
        if let scenario = SyntheticScenario.fromLaunchArguments() {
            startSynthetic(scenario)
            return
        }
        #endif
        do {
            try configureSession()
            try startEngine()
            displayLink.start()
            state = .running
        } catch {
            tearDownEngine()
            logger.error("收音啟動失敗：\(error.localizedDescription)")
            state = .failed(error.localizedDescription)
        }
    }

    #if DEBUG
    /// UI 測試：不開麥克風，以合成訊號驅動同一條偵測管線。伴奏不發聲。
    private func startSynthetic(_ scenario: SyntheticScenario) {
        let context = RealtimeCaptureContext(sampleRate: 48000)
        let reference = TuningReference(clamping: Double(UserDefaults.standard.object(forKey: "referenceA4") as? Int ?? 442))
        let song = scenario == .singing ? SyntheticSongScript() : nil
        let source = SyntheticInputSource(scenario: scenario, reference: reference, context: context, song: song)
        syntheticSong = song
        captureContext = context
        syntheticSource = source
        sampleRate = context.sampleRate
        source.start()
        displayLink.start()
        state = .running
        logger.info("合成輸入啟動：\(scenario.rawValue)")
    }

    /// UI 測試：沒有真正的 SongPlayer，以計時模擬歌曲起點與結束的回報，合成歌聲依同一時間軸演唱。
    private func playSyntheticSong(_ score: SongPlayerScore, script: SyntheticSongScript) {
        let start = CACurrentMediaTime() + Double(score.countInBeats) * score.beatDuration
        script.set((score, start))
        syntheticSongTask?.cancel()
        syntheticSongTask = Task { [weak self] in
            for (event, time) in [(SongPlayer.Report.Event.songStarted, start), (.finished, start + score.duration + 0.5)] {
                // sleep 只會因取消而丟出錯誤，取消時由下一行結束
                try? await Task.sleep(for: .seconds(max(0, time - CACurrentMediaTime())))
                guard !Task.isCancelled, let self else { return }
                self.deliverSongReport(SongPlayer.Report(event: event, hostTime: time))
            }
        }
    }
    #endif

    // MARK: - Session 與引擎

    private func ensureRecordPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: await AVAudioApplication.requestRecordPermission()
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // 不使用 HFP（.allowBluetoothHFP）：HFP 會把麥克風切到耳機並降到 16 kHz
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
        // 一律用內建麥克風收音，有線／藍牙耳機只負責播放，三種路由的讀數才會一致
        if let builtInMic = session.availableInputs?.first(where: { $0.portType == .builtInMic }) {
            try session.setPreferredInput(builtInMic)
        }
        hardwareInputLatency = session.inputLatency + session.ioBufferDuration
        inputLatency = session.inputLatency
        outputLatency = session.outputLatency
        isOutputBuiltInSpeaker = session.currentRoute.outputs.contains { $0.portType == .builtInSpeaker }
        let output = session.currentRoute.outputs.first
        routeKey = output.map { "\($0.portType.rawValue):\($0.uid)" } ?? "none"
        routeName = output?.portName ?? ""
        refreshRouteDescription()
    }

    private func refreshRouteDescription() {
        let route = AVAudioSession.sharedInstance().currentRoute
        func describe(_ ports: [AVAudioSessionPortDescription]) -> String {
            let text = ports.map { "\($0.portName)（\($0.portType.rawValue)）" }.joined(separator: "、")
            return text.isEmpty ? "無" : text
        }
        routeDescription = "輸入 \(describe(route.inputs))　輸出 \(describe(route.outputs))"
    }

    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        // 回音消除必須在讀取格式、啟動引擎之前設定（會改變輸入格式）
        isVoiceProcessingActive = false
        if prefersVoiceProcessing && isOutputBuiltInSpeaker && voiceProcessingGuard.allowsVoiceProcessing(on: routeKey) {
            do {
                try input.setVoiceProcessingEnabled(true)
                input.isVoiceProcessingAGCEnabled = false
                isVoiceProcessingActive = true
            } catch {
                // 退回不消除的模式（方案 B：快速衰減的提示音＋建議戴耳機），不讓收音整個失敗
                logger.error("無法啟用回音消除：\(error.localizedDescription)")
            }
        }
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let monoInput = Self.monoFormat(sampleRate: inputFormat.sampleRate) else {
            throw PipelineError.noInputAvailable
        }

        let context = RealtimeCaptureContext(sampleRate: inputFormat.sampleRate)
        let sink = context.makeSinkNode()
        engine.attach(sink)
        engine.connect(input, to: sink, format: monoInput)

        let outputRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let synthRate = outputRate > 0 ? outputRate : inputFormat.sampleRate
        let droneSynth = DroneSynthesizer(sampleRate: synthRate)
        let metronomeSynth = MetronomeSynthesizer(sampleRate: synthRate)
        let player = SongPlayer(sampleRate: synthRate)
        droneSynth.settings.set(drone)
        metronomeSynth.settings.set(metronome)
        player.settings.set(songPlayerSettings)
        if let monoOutput = Self.monoFormat(sampleRate: synthRate) {
            for renderer in [droneSynth, metronomeSynth] as [any RealtimeRenderer] {
                let source = AudioNodeFactory.sourceNode(format: monoOutput, renderer: renderer)
                engine.attach(source)
                engine.connect(source, to: engine.mainMixerNode, format: monoOutput)
            }
            let songSource = AudioNodeFactory.timedSourceNode(format: monoOutput, renderer: player)
            engine.attach(songSource)
            engine.connect(songSource, to: engine.mainMixerNode, format: monoOutput)
        }

        engine.prepare()
        try engine.start()
        voiceProcessingGuard.engineStarted(voiceProcessing: isVoiceProcessingActive, at: CACurrentMediaTime())

        self.engine = engine
        captureContext = context
        droneSynthesizer = droneSynth
        metronomeSynthesizer = metronomeSynth
        songPlayer = player
        sampleRate = inputFormat.sampleRate
    }

    private func tearDownEngine() {
        #if DEBUG
        syntheticSource?.stop()
        syntheticSource = nil
        syntheticSongTask?.cancel()
        #endif
        isSongPlaying = false
        // engine.stop() 返回後 IO 回呼已結束，才能釋放回呼使用的物件
        engine?.stop()
        engine = nil
        captureContext = nil
        droneSynthesizer = nil
        metronomeSynthesizer = nil
        songPlayer = nil
    }

    private static func monoFormat(sampleRate: Double) -> AVAudioFormat? {
        AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)
    }

    private func observeSystemNotifications() {
        let names: [Notification.Name] = [
            AVAudioSession.interruptionNotification,
            AVAudioSession.routeChangeNotification,
            AVAudioSession.mediaServicesWereResetNotification,
            .AVAudioEngineConfigurationChange,
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let event = AudioSessionEvent(notification: notification) else { return }
                MainActor.assumeIsolated { self?.handle(event) }
            }
        }
    }

    // MARK: - 分送

    private func deliverFrames(displayTime: CFTimeInterval) {
        guard let captureContext else { return }
        var latestLevel: Float?
        captureContext.mailbox.drain { captured in
            receivedFrameCount += 1
            latestLevel = captured.inputLevelDB
            if captured.frame.estimate != nil, captured.hostTime > 0 {
                latency.record(displayTime - captured.hostTime)
            }
            for handler in frameHandlers.values {
                handler(captured.frame)
            }
            for handler in timedFrameHandlers.values {
                handler(captured.frame, captured.hostTime)
            }
        }
        if let latestLevel { inputLevelDB = latestLevel }
        songPlayer?.reports.drain { deliverSongReport($0) }
    }

    private func deliverSongReport(_ report: SongPlayer.Report) {
        if report.event == .finished { isSongPlaying = false }
        for handler in songEventHandlers.values { handler(report) }
    }
}
