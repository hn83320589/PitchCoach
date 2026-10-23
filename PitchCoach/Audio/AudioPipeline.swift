import AVFAudio
import Observation
import os
import PitchDetection
import QuartzCore

private let logger = Logger(subsystem: "PitchCoach", category: "AudioPipeline")

/// 管理 AVAudioSession 與 AVAudioEngine，把偵測結果以螢幕更新頻率分送給畫面（docs/ARCHITECTURE.md §3）。
///
/// 收音：內建麥克風 → inputNode → AVAudioSinkNode（IO 執行緒做 MPM）→ RealtimeMailbox → 主執行緒。
@MainActor
@Observable
final class AudioPipeline {
    enum State: Equatable {
        case idle
        case running
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

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var captureContext: RealtimeCaptureContext?
    @ObservationIgnored private var frameHandlers: [UUID: @MainActor (PitchFrame) -> Void] = [:]
    @ObservationIgnored private lazy var displayLink = DisplayLinkDriver { [weak self] target in
        self?.deliverFrames(displayTime: target)
    }

    func addFrameHandler(_ handler: @escaping @MainActor (PitchFrame) -> Void) -> UUID {
        let id = UUID()
        frameHandlers[id] = handler
        return id
    }

    func removeFrameHandler(_ id: UUID) {
        frameHandlers[id] = nil
    }

    func start() async {
        guard state != .running else { return }
        guard await ensureRecordPermission() else {
            state = .permissionDenied
            return
        }
        do {
            try configureSession()
            try startEngine()
            displayLink.start()
            state = .running
        } catch {
            tearDownEngine()
            state = .failed(error.localizedDescription)
        }
    }

    func stop() {
        displayLink.stop()
        tearDownEngine()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            // 停用失敗不影響下次啟動（setActive(true) 會重新取得 session），記錄後繼續
            logger.error("AVAudioSession 停用失敗：\(error.localizedDescription)")
        }
        if case .failed = state { return }
        state = .idle
    }

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
    }

    private func startEngine() throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardwareFormat = input.outputFormat(forBus: 0)
        guard hardwareFormat.sampleRate > 0, hardwareFormat.channelCount > 0,
              let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: hardwareFormat.sampleRate,
                                             channels: 1, interleaved: false) else {
            throw PipelineError.noInputAvailable
        }

        let context = RealtimeCaptureContext(sampleRate: hardwareFormat.sampleRate)
        let sink = context.makeSinkNode()
        engine.attach(sink)
        engine.connect(input, to: sink, format: monoFormat)
        engine.prepare()
        try engine.start()

        self.engine = engine
        captureContext = context
        sampleRate = hardwareFormat.sampleRate
    }

    private func tearDownEngine() {
        engine?.stop()
        engine = nil
        captureContext = nil
    }

    // MARK: - 分送

    private func deliverFrames(displayTime: CFTimeInterval) {
        guard let captureContext else { return }
        captureContext.mailbox.drain { captured in
            if captured.frame.estimate != nil, captured.hostTime > 0 {
                latency.record(displayTime - captured.hostTime)
            }
            for handler in frameHandlers.values {
                handler(captured.frame)
            }
        }
    }
}
