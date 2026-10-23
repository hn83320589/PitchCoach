# 09　測試

本章說明怎麼驗證這個系統是對的：測試的分層、讓訊號測試可重現的方法、代表性測試的寫法、UI 測試與實機驗收，以及誠實列出的缺口。

---

## 9.1 測試策略

| 層級 | 數量 | 執行環境 | 時間 | 驗證什麼 |
|---|---|---|---|---|
| Package 單元測試 | 149 | macOS（`swift test`） | 約 20 秒 | 偵測精度、判定規則、統計、解析器、時間對齊、合成器 |
| App 單元測試 | 35 | iOS 模擬器 | 約 1 秒（不含建置） | 事件策略、SwiftData 往返、PDF 內容、設定、狀態提示 |
| UI 測試 | 7 | iOS 模擬器 | 約 3 分鐘 | 合成訊號 → 偵測 → 判定 → 儲存 → 畫面 |
| 實機驗收 | 手動 | iPhone＋耳機 | 約 1 小時 | 真實麥克風、路由、中斷、延遲 |

| 套件 | 數量 | 重點 |
|---|---|---|
| `MusicTheoryTests` | 18 | A4 = 442／440 驗收案例、[−50, 50) 歸屬、12 調拼寫、起始八度範圍 |
| `SignalKitTests` | 7 | 種子決定性、SNR 混合精度、人聲模擬 |
| `PitchDetectionTests` | 24 | 純正弦、二次泛音、SNR 20 dB、靜音與噪音、500 組性質測試、鋸齒波、171 組人聲、串流、信箱 |
| `AccompanimentTests` | 13 | 拍點樣本精準、click 不被當成音高、SongPlayer |
| `SingingEngineTests` | 38 | 格式錯誤、移調、顫音、滑音、容許八度、起音、同音連唱、時鐘、校正 |
| `PracticeEngineTests` | 49 | 讀數平滑、長音手算、299／300 ms 與 ±15 邊界、生命週期、自由練習、統計 |
| `PitchCoachTests` | 35 | 事件策略、回音消除退回、收音狀態提示、SwiftData 往返、PDF、設定 |
| `PitchCoachUITests` | 7 | 調音器、長音、音階、背景中斷、自由練習、週報分享、歌唱 |

測試框架：單元測試用 Swift Testing（`import Testing`、`#expect`），UI 測試用 XCTest。

---

## 9.2 執行指令

```sh
# Package（macOS，不需模擬器）
swift test --package-path Packages/PitchCoachKit

# 只跑某個套件或某個測試
swift test --package-path Packages/PitchCoachKit --filter PitchDetectionTests
swift test --package-path Packages/PitchCoachKit --filter metricsMatchHandCalculation

# App 單元測試＋UI 測試（換成你有的模擬器名稱）
xcodebuild test -project PitchCoach.xcodeproj -scheme PitchCoach \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/DerivedData

# 只跑 App 單元測試
xcodebuild test -project PitchCoach.xcodeproj -scheme PitchCoach \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:PitchCoachTests

# 跑 UI 測試並把截圖匯出到 docs/screenshots/
scripts/export-screenshots.sh "iPhone 18 Pro"
```

指定 `-derivedDataPath build/DerivedData` 是為了避開 Xcode 自己的建置快取（10 章「常見錯誤」）。

---

## 9.3 可重現的測試訊號

`Packages/PitchCoachKit/Sources/SignalKit/` 負責產生測試訊號。只要用到亂數，測試就可能「今天過、明天不過」，所以：

**自寫可設定種子的亂數產生器**（`SplitMix64.swift`，十幾行，實作標準的 `RandomNumberGenerator` 協定）。同一個種子永遠產生同一串數字，測試 `seededGeneratorIsDeterministic` 驗證。

> 📄 依據：`docs/ARCHITECTURE.md` §12「測試訊號由 SignalKit 以固定種子產生（自寫 SplitMix64 亂數，Box–Muller 產生高斯白噪音），結果可重現」

**SNR 要量出來**：`SignalGenerator.addNoise(to:snrDB:using:)` 依實際量到的 RMS 縮放噪音，讓訊雜比恰為 20 dB。只依理論標準差設定時，有限長度的隨機樣本會讓實際 SNR 偏離。測試 `addNoiseAchievesRequestedSNR` 驗證誤差 < 0.1 dB——測試工具本身也要測。

**相位不同但固定**：

```swift
// Packages/PitchCoachKit/Tests/PitchDetectionTests/TestSupport.swift
/// 每個頻率用不同但固定的初始相位，避免所有測試都從相位 0 開始。
func deterministicPhase(_ frequency: Double) -> Double {
    (frequency * 7.919).truncatingRemainder(dividingBy: 2 * .pi)
}
```

---

## 9.4 代表性測試走讀

### 走讀一：長音的手算 fixture

```swift
// Packages/PitchCoachKit/Tests/PracticeEngineTests/LongToneEvaluatorTests.swift
/// 手算：10 個 frame，cents = [0, 5, 10, 12, −8, —, 60, −10, 3, 20]
/// - ±10 以內（含邊界）：0, 5, 10, −8, −10, 3 → 6 / 10 = 0.6
/// - 平均與標準差只用有音高且 |c| ≤ 50 者：[0, 5, 10, 12, −8, −10, 3, 20]
///   平均 = 32 / 8 = 4.0；母體變異數 = (16+1+36+64+144+196+1+256) / 8 = 89.25 → 標準差 9.4472
/// - 有音高比例：9 / 10（60 cents 雖是錯音仍算有音高）
@Test func metricsMatchHandCalculation() throws {
    let evaluator = evaluate([0, 5, 10, 12, -8, nil, 60, -10, 3, 20])
    let result = evaluator.result()
    #expect(abs(result.inToleranceRatio - 0.6) < 1e-12)
    #expect(abs(try #require(result.meanCents) - 4.0) < 1e-9)
    #expect(abs(try #require(result.standardDeviationCents) - 89.25.squareRoot()) < 1e-9)
    #expect(abs(result.voicedRatio - 0.9) < 1e-12)
    #expect(result.statFrameCount == 8)
}
```

為什麼這樣設計：

- **資料刻意涵蓋每一種情況**：剛好 ±10（算）、12 與 20（不算但進平均）、無音高（分母有、平均沒有）、60 cents 錯音（有音高但不進平均）。決策 D4 的每一列都有對應的資料點。
- **計算過程寫在註解裡**：讀測試的人可以拿紙筆驗算，測試本身的正確性也可以被檢查。
- **輔助函式 `evaluate` 以 10 ms 間隔產生 frame**，判定器的時間完全由測試控制。

### 走讀二：音階的時間邊界

```swift
// Packages/PitchCoachKit/Tests/PracticeEngineTests/ScaleEvaluatorTests.swift（測試名稱）
holding299msDoesNotAdvance
holding300msAdvances
exactly15CentsOnEitherSideCountsAsInTolerance
justBeyond15CentsNeverAdvances
excursionOf50msIsBridged
excursionLongerThan50msRestartsHold
```

每條規則測「剛好在邊界上」與「剛好超過」兩側。這類測試最能抓到 `<` 寫成 `<=`、浮點誤差、單位換算錯誤。299／300 ms 之所以能穩定通過，靠的是 `Duration` 的精確表示（04 章 4.5 節）。測試命名本身就是規格：只看名稱就知道規則是什麼。

---

## 9.5 其他測試寫法

| 寫法 | 例子 | 擅長抓什麼 |
|---|---|---|
| 參數化：涵蓋整個範圍 | 65–2,100 Hz 每個半音（62 個頻率）× 2 種取樣率 | 特定頻率才出現的誤差 |
| 性質測試 | 500 組隨機頻率與泛音，斷言「八度錯誤 0、誤差 < 5 cents」 | 沒想到的組合 |
| 整條鏈測試 | 人聲合成 → 串流偵測 → 時鐘 → 判定（AC-15、AC-18） | 分析窗造成的幅度衰減、半窗延遲等只在整條鏈出現的效應 |
| 不變性測試 | 任意分塊餵入的 frame 與一次餵入相同 | 串流、快取的邊界錯誤 |
| 決定性併發測試 | `withLockHeldForTesting` 持鎖時呼叫 `push` | 很難自然重現的競爭情況 |
| 純函式策略測試 | 事件 → 命令 | 系統事件處理 |
| 往返測試 | SwiftData 記憶體內容器：存入、讀回、比對 `summary` | 儲存與轉換的遺漏 |
| PDF 文字抽取 | PDFKit 抽文字、NFKC 正規化後檢查「練習天數」「F#4」等 | 版面上數字的錯誤 |

性質測試的隨機分佈要寫明，因為它直接決定測試的難度：

```swift
// Packages/PitchCoachKit/Tests/PitchDetectionTests/MPMPropertyTests.swift
/// - 基頻：65–2,100 Hz 對數均勻分佈
/// - 取樣率：44.1 kHz 或 48 kHz 隨機
/// - 基頻振幅 1.0；2–8 次泛音振幅各為 U[0, 1]；所有成分相位隨機
/// - 只加入低於 Nyquist 頻率 90% 的泛音；整體正規化到峰值約 0.5
private static let seed: UInt64 = 20261023
```

> 📄 依據：分佈定義為決策 D6（`docs/ARCHITECTURE.md` §12）

---

## 9.6 UI 測試

UI 測試以合成訊號驅動同一條偵測管線（07 章 7.5 節）：

| 啟動參數 | 作用 |
|---|---|
| `-syntheticScenario <tuner\|longTone\|scale\|singing>` | 不開麥克風，以合成訊號取代 |
| `-uiTesting` | SwiftData 用記憶體內儲存 |
| `-seedDemoData` | 28 天示範紀錄 |
| `-referenceA4 442`、`-showsLatencyOverlay NO` | 固定設定 |

```swift
// PitchCoachUITests/PitchCoachUITests.swift
func testTunerShowsSyntheticA4Reading() {
    let app = launch("tuner")
    // A4 +3 cents（A4 = 442 Hz）→ 442.77 Hz
    waitForValue(element(app, "tuner.frequency"), "442.8 Hz", timeout: 5)
    waitForValue(element(app, "tuner.cents"), "+3 ¢", timeout: 3)
    attachScreenshot("01-tuner")
}
```

合成訊號是已知的，所以能斷言精確值。歌唱的 UI 測試讓合成歌聲跟著伴奏時間軸唱完整首，每 8 個音中第 4 個偏高 32 cents、第 7 個偏低 30 cents，斷言音準正確率在合理範圍；結果頁上每個音的偏差剛好等於設定值，證明合成、偵測、時間對齊、判定整條鏈都正確。

> 📄 依據：對話中使用者要求「加入 UI 測試」；commit `3d57c9b`

UI 測試同時產生 README 的截圖（`scripts/export-screenshots.sh`）。

---

## 9.7 斷言與量測分開

測試只回答「有沒有低於門檻」；報告需要「實際是多少」。

| | 斷言（測試） | 量測（報告） |
|---|---|---|
| 目的 | 防止退步 | 描述現況 |
| 形式 | `#expect(error < 3)` | 「最大 2.25 cents」 |
| 何時執行 | 每次 commit、CI | 程式改變後重新量 |

撰寫測試報告時發現 README 的 SNR 20 dB 數字是偵測器修改前量的，已不反映目前程式。用臨時量測程式在目前程式碼上重量（訊號、種子、頻率清單與正式測試相同）後才更新（📄 commit `95481f2`、`docs/TEST_REPORT.md` §9）。文件中的數字也會過期，要知道它在哪個版本量的。

---

## 9.8 讓紅燈有意義

修正「同音連唱」時，先只在列舉中加入新的 `notSeparated` 值、不改邏輯，讓測試能編譯，再看它怎麼失敗：

```
✘ verdicts == [.onTime, .notSeparated, .notSeparated, .notSeparated]
↳   verdicts → [.onTime, .onTime, .onTime, .onTime]                    （200 BPM：被判「準時」）
✘ result.notes.map(\.rhythmVerdict) == [.onTime, .notSeparated, .onTime, .notSeparated]
↳   → [.onTime, .early, .onTime, .early]                               （一般速度：被判「提早」）
```

編譯失敗不能證明測試在檢查想檢查的行為；行為失敗可以。這個紅燈還重現了問題本身，與程式碼審查的推論完全一致，之後的綠燈才有說服力（📄 commit `cd38059`）。

---

## 9.9 CI

`.github/workflows/ci.yml` 有兩個 job：`swift test`（Package 149 個）與 iOS 模擬器上的 `xcodebuild test`（App 35＋UI 7）。

- 模擬器機型在執行時從最新的 iOS runtime 挑第一台 iPhone，不寫死名稱（runner 映像會更新）。
- 挑到的 UDID 以環境變數傳給 `xcodebuild`，不把 `${{ }}` 運算式直接拼進 shell。

> 📄 依據：commit `15e2c4d`（程式碼審查指出 App 測試沒在 CI 上跑）、commit `c271187`（背景安全審查標記運算式直接展開）

---

## 9.10 實機驗收

> 📄 依據：`docs/DEVICE_TESTING.md`、`docs/TEST_REPORT.md` §5

1. 在需求分析階段就列出需要實機的項目與設備。
2. 寫成可照做的步驟（`docs/DEVICE_TESTING.md`），含判定標準與截圖檔名。
3. 在 App 內建量測工具：延遲面板（P50／P95、輸入電平、輸入／輸出埠）、延遲校正畫面。沒有工具，實機驗收只能憑感覺。
4. 證據放在 `docs/device/`，測試報告逐項引用。

缺設備時誠實替代並寫明：

| 原本 | 替代 | 理由 |
|---|---|---|
| 來電 | 鬧鐘、Siri、控制中心播放音樂 | 都觸發同一個 `AVAudioSession.interruptionNotification` |
| 拔有線耳機 | AirPods 放回充電盒 | 走同一條「耳機連接或中斷」路徑 |
| 慢動作錄影量延遲 | 內部時間戳估計（約 98 ms） | 報告標為「部分通過」 |

含有不該公開內容的截圖（動態島裡正在播放內容的人臉縮圖）裁掉後才放進公開 repo，並在報告中註明裁切範圍（📄 對話中使用者決定「裁掉狀態列再加入」）。

---

## 9.11 覆蓋範圍與缺口

### 每一層測試的盲點

| 問題 | 為什麼自動化測試沒抓到 | 誰抓到的 |
|---|---|---|
| 開啟回音消除時引擎無限重啟 | UI 測試用合成輸入，完全不經過 AVAudioEngine | 使用者在模擬器上用真實收音試唱 |
| 同音連唱的假節奏判定 | 起音測試的同音重複都有重新咬字 | 程式碼審查＋合成測試證實 |
| 練習頁無法恢復收音 | 模擬器無法觸發「中斷結束但未建議恢復」 | 實機測試鬧鐘中斷 |
| 週報說明漏了歌唱 | 測試只檢查數字，沒檢查說明文字 | 實機產生 PDF 時目視檢查 |

以上四項都已補上測試。設計測試時要清楚知道「這個測試沒有經過哪些程式」；測試、審查、實機、目視互相補位。

### 目前沒有自動化測試的部分

| 部分 | 現況 |
|---|---|
| `AudioPipeline` 與 AVAudioEngine 的實際互動 | 只有策略函式有單元測試；引擎建立、重建、回音消除只能手動或實機驗證 |
| KTV 音高條的繪製內容 | UI 測試只確認元件存在與截圖，沒有檢查曲線位置 |
| 喇叭外放時回音消除的效果 | 沒有任何驗證（實機也未做） |
| 不同取樣率的實機（44.1 kHz 裝置） | 單元測試涵蓋兩種取樣率，實機只測過 48 kHz |

### 建議補強（建議）

- **建議**：為 `AudioPipeline` 的引擎重建抽出一個可注入的「引擎工廠」協定，讓重建邏輯能用假引擎測試（例如「引擎啟動後立刻停下」的情境）。
- **建議**：UI 測試加一個「真實引擎」的煙霧測試（smoke test）：不用合成輸入，只確認進入歌唱頁後管線狀態穩定在 running，用來抓引擎層的循環重啟。
- **建議**：KTV 音高條的座標換算抽成純函式（歌曲時間、音高 → 畫面座標），單元測試換算結果。
- **建議**：為次諧波問題建立一段確定沒有人聲的提示音錄音，做成回歸測試資料（12 章延伸專題）。
