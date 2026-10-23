# 04　技術選型

本章說明用了什麼、為什麼用。PitchCoach 的技術來源分成三類，對待方式不同：

| 來源 | 例子 | 怎麼對待 |
|---|---|---|
| 題目規定 | iOS 17+、SwiftUI、AVAudioEngine、SwiftData、Swift Charts、不可用第三方套件、偵測自行實作 | 不討論要不要用，討論怎麼用好 |
| 需求推導 | 延遲 ≤ 150 ms → 低延遲的擷取方式；精度 < 1 cent → 高精度演算法 | 從需求倒推，用量測決定 |
| 自己選擇 | MPM、手寫專案檔、Swift Testing | 寫決策紀錄 |

---

## 4.1 技術一覽

| 技術 | 版本 | 用途 | 選用理由 | 替代方案 |
|---|---|---|---|---|
| Swift | 6.4（Package 宣告 tools 6.0） | 全部程式 | 📄 題目規定 iOS／SwiftUI；tools 6.0 是為了讓 CI 上較舊的 Xcode 也能編譯（`docs/ARCHITECTURE.md` §13） | — |
| SwiftUI＋Observation | iOS 17 SDK | 畫面、`@Observable` 模型 | 📄 題目規定 | UIKit |
| AVAudioEngine | iOS SDK | 收音與伴奏播放 | 📄 題目規定 | Audio Unit 直接操作 |
| `AVAudioSinkNode` | iOS SDK | 收音回呼 | 📄 `installTap` 實際約 100 ms 一包，吃掉 2/3 延遲預算（D2） | `installTap`；ring buffer＋分析執行緒 |
| `AVAudioSourceNode` | iOS SDK | 即時合成伴奏 | 📄 樣本精準的拍點（`docs/ARCHITECTURE.md` §8） | 🔍 `AVAudioPlayerNode`、`AVAudioUnitSampler` |
| Accelerate（vDSP） | iOS／macOS SDK | FFT、向量運算 | 📄 偵測要能在 IO 執行緒跑（`docs/ARCHITECTURE.md` §3.3） | 純 Swift 迴圈 |
| SwiftData | iOS 17 SDK | 練習紀錄 | 📄 題目規定 | Core Data |
| Swift Charts | iOS 17 SDK | 趨勢圖、偏差曲線、週報圖表 | 📄 題目規定 | — |
| `ImageRenderer`＋`CGContext` PDF | iOS 17 SDK | 週報 PDF | 📄 向量輸出、文字可選取，與畫面預覽共用版面（`docs/ARCHITECTURE.md` §10.2） | 🔍 `UIGraphicsPDFRenderer` 手動排版 |
| `OSAllocatedUnfairLock` | iOS 16+ | 跨執行緒資料交換 | 📄 只用 trylock，拿不到不等待（`docs/ARCHITECTURE.md` §3.3） | 🔍 原子變數（見 4.7） |
| Swift Testing | Xcode 27 | 單元測試 | 📄 `docs/ARCHITECTURE.md` §12 指定；未記載選用原因 | XCTest |
| XCTest（XCUITest） | Xcode 27 | UI 測試 | 🔍 UI 測試目前只能用 XCTest | — |
| GitHub Actions | `macos-15` runner、`actions/checkout@v5` | CI | 📄 題目的加分項（`docs/ARCHITECTURE.md` §13） | — |
| 第三方套件 | 無 | — | 📄 題目規定不可使用 | — |

部署目標：App iOS 17.0；Package `platforms: [.iOS(.v17), .macOS(.v14)]`。

---

## 4.2 音訊擷取：`AVAudioSinkNode`

| 方案 | 回呼頻率 | 延遲影響 |
|---|---|---|
| `inputNode.installTap(bufferSize:)` | iOS 常忽略指定大小，實際約 100 ms 一包（4,410／4,800 個樣本） | 單這一項吃掉約 2/3 的延遲預算 |
| **`AVAudioSinkNode`（採用）** | 依 IO buffer，設定 5 ms 時約每 5 ms 一次 | 幾乎不增加 |

> 📄 依據：`docs/ARCHITECTURE.md` §3.3「為什麼用 AVAudioSinkNode 而不是 installTap」、決策 D2

代價是回呼在**即時執行緒**上，不能配置記憶體、不能等鎖（06 章）。換來的是實機上量到的管線 P95 約 40 ms，端到端估計約 98 ms，在 150 ms 的預算內。

設計文件也寫了退路：「若實機 profiling 發現 overrun，改成 ring buffer＋分析執行緒（介面不變）」。實際沒有用到。

---

## 4.3 音訊工作階段

| 設定 | 值 | 理由 |
|---|---|---|
| Category | `.playAndRecord` | 伴奏與收音同時 |
| Mode | `.measurement` | 關閉自動增益等系統處理，讀數一致 |
| Options | `.defaultToSpeaker`、`.allowBluetoothA2DP` | 無耳機時從喇叭出聲；藍牙走高音質 A2DP |
| **不使用** | `.allowBluetoothHFP` | HFP 會把麥克風切到耳機、降到 16 kHz |
| 偏好輸入 | 固定內建麥克風 | 三種輸出路由都用同一顆麥克風，讀數才會一致（AC-11） |
| IO buffer | 0.005 秒 | 降低延遲 |

> 📄 依據：`docs/ARCHITECTURE.md` §3.1、決策 D3

實機驗收證實了固定內建麥克風的設計：連著 AirPods Pro 時，延遲面板顯示「輸入 iPhone 麥克風（MicrophoneBuiltIn）、輸出 AirPods Pro（BluetoothA2DPOutput）」，內建與藍牙兩種路由的讀數相差 0 cent（📄 `docs/TEST_REPORT.md` §5.1）。

`.measurement` 的代價是沒有自動增益：實機上 30 cm 外的測試音只有 −43～−47 dBFS，離偵測門檻 −50 dBFS 不遠（📄 README 已知限制）。

---

## 4.4 音高偵測演算法

| 方案 | 優點 | 缺點 |
|---|---|---|
| FFT 峰值 | 簡單 | 2,048 點 @48 kHz 每格 23 Hz，解析度不足；最高峰常是泛音 |
| 自相關 | 直觀 | 容易選到 2 倍週期；沒有自然的信心值 |
| YIN | 廣泛使用 | 📄 設計文件比較：信心值為差分函數的谷值，意義不如 MPM 直觀 |
| **MPM（採用）** | NSDF 對純正弦在真實週期處恰為 1；峰值高度就是 clarity | 單獨使用時抗噪不足 |
| 機器學習模型 | 對真實聲音強健 | 違反「不可用第三方套件」；難以證明精度 |

> 📄 依據：`docs/ARCHITECTURE.md` §4.1「選 MPM 的主因：clarity 天然提供 FR-04 所需的『無明顯音高』判準；對純正弦峰值無偏，有利於達成 < 1 cent」
> 🔍 推斷：FFT 峰值、自相關、機器學習三列是本文件補充的常見方案，設計文件只比較了 MPM 與 YIN。

### 量測推翻了原本的設計

原設計只用 MPM＋拋物線內插。實作後量測：

| 變體（48 kHz） | 鋸齒波 < 200 Hz 偏差 | SNR 20 dB 最差（610 次） |
|---|---|---|
| 只用 MPM | 0.2 cents（高頻 2.3） | **8.4 cents** ❌ |
| ＋諧波精修，矩形權重、10 個諧波 | **9.43 cents** ❌ | 1.62 |
| ＋諧波精修，Hann 權重、10 個諧波 | 0.28 | 2.66（逼近門檻） |
| **＋諧波精修，sine 窗、16 個諧波（採用）** | **0.11** | **1.93** |

> 📄 依據：`docs/ARCHITECTURE.md` §4.5 的變體比較表；commit `a855655`「MPM 粗估＋諧波加權最小平方精修的基頻偵測」

四個變體都是實際寫出來、用同一組測試量出來的。這次調整能快速完成，是因為 SNR 20 dB 的測試早就寫好了：換演算法時立刻知道新方案有沒有比較好。演算法細節在 08 章。

---

## 4.5 時間的表示法：`Duration`

| 方案 | 問題 |
|---|---|
| `Double` 秒數 | 浮點誤差讓「持續 300 ms 到位」的邊界比較出錯 |
| `Date` | 牆上時鐘，會因改時間、時區、校時而跳動 |
| 整數樣本數 | 精確，但不同取樣率之間不能直接比較，測試難讀 |
| **`Duration`（採用）** | 整數「秒＋10⁻¹⁸ 秒」，加減比較精確；測試可寫 `.milliseconds(300)` |

> 📄 依據：`docs/ARCHITECTURE.md` §3.3「時間戳以 Duration 表示……299 ms／300 ms 邊界比較是精確的整數比較」
> 🔍 推斷：`Date` 與整數樣本數兩列是本文件補充的比較。

樣本位置換算成 `Duration` 也要避開浮點：

```swift
// Packages/PitchCoachKit/Sources/PitchDetection/StreamingPitchAnalyzer.swift
/// 取樣率為整數時以整數運算換算，時間戳精確（練習判定的 300 ms 邊界比較依賴這點）。
private func duration(ofSamples samples: Int64) -> Duration {
    // ...
    let rate = Int64(sampleRate)
    let remainder = samples % rate
    let (attoseconds, _) = rate.dividingFullWidth(remainder.multipliedFullWidth(by: 1_000_000_000_000_000_000))
    return Duration(secondsComponent: samples / rate, attosecondsComponent: attoseconds)
}
```

`multipliedFullWidth`／`dividingFullWidth` 用 128 位元的中間結果，避免 `remainder × 10¹⁸` 溢位。這是踩坑後的修正（11 章踩坑 1）。

---

## 4.6 PDF：SwiftUI 版面 → `ImageRenderer` → `CGContext`

> 📄 依據：`docs/ARCHITECTURE.md` §10.2「週報頁面以 SwiftUI View 排版 → ImageRenderer.render 畫進 CGContext(PDF)（向量輸出、文字可選取）……週報預覽畫面與 PDF 共用同一個 WeeklyReport 值，數字只計算一次」

好處是畫面預覽與 PDF 用同一個 View（`PitchCoach/Features/Report/WeeklyReportPage.swift`），版面只寫一次；輸出是向量，系統字型直接支援中文。

副作用：PingFang 的部分字形（音、生、小、高）同時對應康熙部首碼位，從 PDF 複製文字會得到部首字元（例如「⾳」U+2FB3）。畫面顯示正確，只影響複製與搜尋。測試以 Unicode NFKC 正規化後比對（📄 README 已知限制）。

---

## 4.7 被限制排除的選項：原子變數

IO 執行緒與主執行緒交換資料，最直覺的工具是原子變數。但：

- Swift Atomics 是第三方套件 → 不可用。
- 系統的 `Synchronization` 模組（`Atomic`）需要 iOS 18 → 部署目標是 iOS 17。

所以用 `OSAllocatedUnfairLock`，並且 IO 端只用 trylock。

> 🔍 推斷：設計文件只寫了採用 `OSAllocatedUnfairLock` 的 trylock，沒有記載原子變數的比較。以上是依題目限制與部署目標推得的理由。

---

## 4.8 工具鏈

| 項目 | 選擇 | 理由 |
|---|---|---|
| 專案檔 | 手寫 `project.pbxproj`，Xcode 16 起的資料夾同步群組 | 📄 D9：本機沒有 XcodeGen／Tuist，規範要求不擅自引入新工具；同步群組讓新增檔案不必改專案檔 |
| 測試亂數 | 自寫 SplitMix64（`Packages/PitchCoachKit/Sources/SignalKit/SplitMix64.swift`） | 📄 `docs/ARCHITECTURE.md` §12「自寫 SplitMix64 亂數……結果可重現」；🔍 系統亂數無法設定種子 |
| 截圖 | UI 測試產生，`scripts/export-screenshots.sh` 匯出 | 📄 commit `3d57c9b`「以合成訊號驅動的 UI 測試與截圖匯出」；🔍 好處是 README 截圖與程式保持一致 |
| 測試音 | `scripts/make-test-tone.py`（只用 Python 標準函式庫） | 📄 實機驗收用 A4 音源（`docs/DEVICE_TESTING.md`） |
| CI | 兩個 job：`swift test`、iOS 模擬器上的 `xcodebuild test` | 📄 commit `15e2c4d`：程式碼審查指出 App 測試沒在 CI 上跑 |

---

## 4.9 版本注意事項

- **Package tools 6.0、本機 Swift 6.4**：避免使用 6.2 之後才有的語言功能，CI 上較舊的 Xcode 才能編譯（📄 `docs/ARCHITECTURE.md` §13）。
- **iOS 17 部署目標**：不能用 iOS 18 的 `Synchronization`；可以用 iOS 17 的 SwiftData、Observation。
- **iOS 26 新增的藍牙選項**：SDK 中有 `.bluetoothHighQualityRecording`（耳機高音質收音），本專案沒有開啟，所以連藍牙耳機時仍用內建麥克風。若日後想用耳機收音，要重新評估 AC-11 的一致性要求。
- **iOS 模擬器的音訊行為與實機不同**：模擬器回報的輸出延遲為 0 ms；開啟 voice processing 的引擎會自己停下（11 章踩坑 6）。
