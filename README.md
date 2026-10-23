# PitchCoach 音準練習教練

[![CI](https://github.com/hn83320589/PitchCoach/actions/workflows/ci.yml/badge.svg)](https://github.com/hn83320589/PitchCoach/actions/workflows/ci.yml)

給兒童小提琴與長笛學生的 iPhone 音準練習 App：即時調音器、長音與音階練習、練習紀錄與趨勢，並能產生 PDF 週報分享給老師。

- **平台**：iOS 17 以上、iPhone 直向
- **技術**：SwiftUI、AVAudioEngine、AVAudioSession、SwiftData、Swift Charts、Accelerate/vDSP
- **相依**：無第三方套件、無後端
- **音高偵測**：自行實作（McLeod Pitch Method ＋ 諧波加權最小平方精修）

| 調音器 | 長音結果 | 音階結果 | 近 30 天趨勢 | PDF 週報 |
|---|---|---|---|---|
| ![調音器](docs/screenshots/01-tuner.png) | ![長音結果](docs/screenshots/03-long-tone-result.png) | ![音階結果](docs/screenshots/05-scale-result.png) | ![趨勢](docs/screenshots/07-trends.png) | ![PDF 週報](docs/screenshots/11-weekly-report-pdf.png) |

> 截圖由 UI 測試以合成訊號自動產生（`scripts/export-screenshots.sh`），PDF 為示範資料實際輸出的頁面。實機截圖見[實機驗收](#實機驗收)。

---

## 目錄

1. [執行方式](#執行方式)
2. [專案結構](#專案結構)
3. [音訊流程架構](#音訊流程架構)
4. [音高偵測演算法](#音高偵測演算法)
5. [測試訊號與精度量測](#測試訊號與精度量測)
6. [延遲量測](#延遲量測)
7. [練習判定規則](#練習判定規則)
8. [測試](#測試)
9. [實機驗收](#實機驗收)
10. [已知限制](#已知限制)

---

## 執行方式

**需求**：Xcode 16 以上（開發環境為 Xcode 27），iOS 17 以上的模擬器或實機。

```sh
git clone https://github.com/hn83320589/PitchCoach.git
open PitchCoach/PitchCoach.xcodeproj
```

1. 選擇 `PitchCoach` scheme 與 iPhone 模擬器，⌘R 執行。
2. 實機執行：在 Signing & Capabilities 選擇自己的 Team，並把 Bundle Identifier 改成自己的。
3. 第一次啟動會詢問麥克風權限。

模擬器的麥克風即 Mac 的麥克風，可對著 Mac 演奏或播放測試音（`python3 scripts/make-test-tone.py 442`）。

**命令列**

```sh
# 核心邏輯（macOS 上執行，不需模擬器）
swift test --package-path Packages/PitchCoachKit

# App 單元測試與 UI 測試
xcodebuild test -project PitchCoach.xcodeproj -scheme PitchCoach \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'

# 以 UI 測試重新產生 README 截圖
scripts/export-screenshots.sh
```

GitHub Actions（macOS runner）會在每次 push 執行 `swift test` 並建置 App（`.github/workflows/ci.yml`）。

---

## 專案結構

```
PitchCoach/
├── PitchCoach/                      # App（SwiftUI）
│   ├── App/                         # 進入點、分頁、設定
│   ├── Audio/                       # AudioPipeline、中斷策略、即時擷取、合成輸入（UI 測試）
│   ├── Features/                    # 調音器、練習、紀錄、週報、設定
│   └── Persistence/                 # SwiftData 模型、Repository、示範資料（DEBUG）
├── PitchCoachTests/                 # App 單元測試（Swift Testing）
├── PitchCoachUITests/               # UI 測試（XCUITest，合成訊號驅動）
├── Packages/PitchCoachKit/          # 獨立 Swift Package（不依賴 UIKit／SwiftUI）
│   ├── Sources/MusicTheory/         # 基準音、音名、cents、大調音階
│   ├── Sources/PitchDetection/      # MPM、諧波精修、串流切窗、即時信箱
│   ├── Sources/PracticeEngine/      # 調音器平滑、長音／音階／自由練習判定、生命週期、統計
│   ├── Sources/Accompaniment/       # drone 與節拍器合成器
│   └── Sources/SignalKit/           # 測試訊號產生（固定種子）
├── docs/ARCHITECTURE.md             # 系統分析與架構設計（含所有設計決策）
├── docs/DEVICE_TESTING.md           # 實機驗收步驟
└── scripts/                         # 截圖匯出、測試音產生
```

所有「判定」與「統計」都在 Package 內，App 只負責 I/O（音訊、儲存、畫面、PDF），因此長音指標、到位規則、週報數字都能在 macOS 上以 `swift test` 驗證。

---

## 音訊流程架構

```mermaid
flowchart LR
    MIC["內建麥克風<br/>（固定，不用耳機麥克風）"] --> IN["inputNode"]
    IN --> SINK["AVAudioSinkNode<br/>IO 執行緒"]
    SINK --> SPA["StreamingPitchAnalyzer<br/>窗 2048／hop 512"]
    SPA --> DET["MPM 粗估（選對八度）<br/>＋ 諧波加權最小平方精修"]
    DET -->|PitchFrame| MB["RealtimeMailbox<br/>trylock，不阻塞"]
    MB -->|CADisplayLink 取出| MAIN["主執行緒"]
    MAIN --> TT["TunerTracker<br/>中位數＋遲滯＋EMA"] --> TUNER["調音器畫面"]
    MAIN --> EV["長音／音階／自由練習判定"] --> PRACTICE["練習畫面"] --> DB[("SwiftData")]
    DB --> AN["PracticeAnalytics"] --> CHARTS["Swift Charts 趨勢"] & PDF["PDF 週報"]

    DRONE["Drone 合成<br/>AVAudioSourceNode"] --> MIX["mainMixerNode"]
    METRO["節拍器合成<br/>AVAudioSourceNode"] --> MIX
    MIX --> OUT["喇叭／有線耳機／藍牙 A2DP"]

    SYS["AVAudioSession 通知<br/>來電、路由、媒體重置、背景"] --> POL["AudioInterruptionPolicy"]
    POL -->|暫停／重建／標記中斷| MAIN
```

**AVAudioSession**：`.playAndRecord`、`.measurement` mode（關閉 AGC）、`.defaultToSpeaker`、`.allowBluetoothA2DP`，IO buffer 5 ms。**不使用 HFP**：HFP 會把收音切到藍牙耳機並降到 16 kHz。收音固定使用內建麥克風，有線／藍牙耳機只負責播放伴奏，三種路由的讀數因此一致。

**執行緒**：偵測直接在 IO 執行緒執行（每 hop 約 0.27 ms，所有緩衝預先配置、不配置記憶體），結果經 `OSAllocatedUnfairLock` 的 trylock 交給主執行緒；拿不到鎖時暫存在生產者端，IO 執行緒永不等待。

**中斷處理**：系統通知轉成純值事件，由 `AudioInterruptionPolicy`（純函式，有單元測試）決定動作：

| 事件 | 動作 |
|---|---|
| 來電、鬧鐘、其他 App 佔用音訊 | 練習標記中斷 → 暫停引擎；結束且系統建議恢復時重建 |
| 插拔有線耳機、藍牙連線變化 | 練習標記中斷 → 300 ms debounce 後重建引擎（取樣率可能改變）；拔除時暫停伴奏 |
| 媒體服務重置 | 練習標記中斷 → 重建 |
| App 進入背景／回到前景 | 練習標記中斷 → 停止引擎／重建 |

---

## 音高偵測演算法

兩階段：**MPM 負責選對八度，諧波擬合負責精度**（設計文件 §4）。

### 1. McLeod Pitch Method（粗估）

1. 取最近 2,048 個樣本，去除直流；RMS 低於 −50 dBFS 視為靜音。
2. 以 vDSP FFT 計算自相關 r(τ)，以平方前綴和計算 m(τ)，得正規化平方差函數 **n(τ) = 2r(τ) / m(τ)**。
3. 每個正值區間取一個 key maximum，**選第一個 ≥ 0.9 × 最高峰者**，拋物線插值。
4. 峰值（clarity）< 0.85 視為沒有明顯音高（白噪音約 0.1–0.4，SNR 20 dB 的正弦約 0.98）。

### 2. 諧波加權最小平方精修

模型 x ≈ c + Σₕ aₕcos(hωj′) + bₕsin(hωj′)（h ≤ 16，j′ 以窗中心為原點），以 Brent 法求投影能量 J(ω) 的最大值。

- 對 16 個諧波以內的週期訊號，真實頻率處殘差為 0 → 沒有插值偏差；白噪音下接近最大概似估計。
- **權重用 sine 窗**：矩形權重時，弓弦（鋸齒波）的高次泛音在低頻洩漏，65 Hz 偏差 9.4 cents；Hann 權重洩漏最小但噪音誤差逼近 3 cents；sine 窗兩者兼顧。
- 以窗中心為原點時 cos／sin 欄正交，Gram 矩陣由 Dirichlet kernel 的封閉解查表，每次評估只需 O(W·H) 的向量內積。
- 兩段搜尋：先用主瓣仍寬的諧波（容忍粗估誤差），再用全部諧波小範圍精修，避免跳到旁瓣。

| 參數 | 值 | 理由 |
|---|---|---|
| 窗長 | 2,048 樣本 | 最低 65 Hz 週期 738 樣本（48 kHz），需 ≤ 窗長的一半；約 43 ms |
| Hop | 512 樣本（約 11 ms） | 約 90 frames/s |
| MPM k | 0.90 | 見下方八度錯誤推導 |
| clarity 門檻 | 0.85 | 區分噪音與音高 |
| 精修諧波數 | ≤ 16 | 低頻涵蓋到約 1 kHz 以上的泛音 |

### 防止八度錯誤

1. **k = 0.9 門檻**：基頻 + a 倍強的二次泛音時，n(T/2) ≈ (a² − 1)/(a² + 1)。a = 2（長笛高音區）→ 0.6 < 0.9，不會選到半週期（八度偏高）；a ≥ 4.4 才會誤判。
2. **選「第一個」而非「最高」**：週期訊號在 2T、3T 的 n 值和 T 幾乎一樣，只取最高峰會隨機落在倍數週期（八度偏低）。
3. **精修只在粗估附近搜尋**：搜尋範圍限制在主瓣內，不會跳到 ω/2 或 2ω。
4. **調音器顯示層**：3 frame 中位數濾波去除單一 frame 的跳動。

---

## 測試訊號與精度量測

測試訊號由 `SignalKit` 以固定種子產生（SplitMix64 亂數、Box–Muller 高斯白噪音），內部以 Double 計算、輸出 Float，可重現。

- **純正弦**：65·2^(k/12) Hz，k = 0…60，外加 2,100 Hz，共 62 個頻率；每個頻率不同的固定初始相位。
- **二次泛音強 2 倍**：基頻振幅 0.25、二次泛音 0.5。
- **白噪音 SNR 20 dB**：以實際量到的 RMS 調整噪音，使訊雜比恰為 20 dB（誤差 < 0.1 dB，有測試）。
- **性質測試**：500 組，基頻 65–2,100 Hz 對數均勻、取樣率隨機、2–8 次泛音振幅 U[0, 1]、相位隨機。
- **鋸齒波**（弓弦振動模型，驗收標準以外）：泛音一路到 Nyquist，振幅 1/h。

**量測結果**（單一 frame，誤差單位 cents）：

| 訊號 | 44.1 kHz 最大／平均 | 48 kHz 最大／平均 | 驗收門檻 |
|---|---|---|---|
| 純正弦（62 個頻率） | 0.001 / 0.0002 | 0.001 / 0.0002 | < 1 |
| 二次泛音強 2 倍 | 0.0007 / 0.0002（八度錯誤 0） | 0.0005 / 0.0001（八度錯誤 0） | 不可八度錯誤 |
| SNR 20 dB（測試用種子） | 0.81 / 0.16 | 1.53 / 0.17 | < 3 |
| SNR 20 dB 壓力測試（1,240 次） | 2.08 / 0.19 | 2.36 / 0.21 | < 3 |
| 性質測試 500 組 | 最大 0.001，八度錯誤 0 | （兩種取樣率混合） | < 5、八度錯誤 0 |
| 鋸齒波 | 0.18 / 0.007 | 0.11 / 0.006 | — |
| 靜音、極小訊號、150 段白噪音 | 皆無輸出 | 皆無輸出 | 不輸出音高 |

> 只用 MPM 拋物線插值時，SNR 20 dB 低頻誤差達 8 cents、性質測試達 4 cents；加入諧波精修後才達到上表（設計文件 §4.5 有各變體比較）。

---

## 延遲量測

**目標**：從聲音開始到畫面顯示讀數 ≤ 150 ms。

### 方法一：內部時間戳（App 內建）

每個分析 frame 記錄「分析窗最後一個樣本」對應的 host time（由 `AudioTimeStamp.mHostTime` 與樣本偏移推算），在 `CADisplayLink` 取出時與該幀的 `targetTimestamp`（預計顯示時間）相減。設定 → 開啟「顯示延遲資訊」即可在調音器下方看到 P50／P95、硬體輸入延遲與取樣率。

端到端估計 = 硬體輸入延遲 ＋ 分析窗填入新聲音（最長 42.7 ms）＋ 等待 hop（最長 10.7 ms）＋ 上述 P95。

| 環境 | 管線 P50 | 管線 P95 | 硬體輸入 | 端到端估計（最壞） |
|---|---|---|---|---|
| iPhone 18 Pro 模擬器（iOS 27、M4 Pro） | 11–12 ms | 18–29 ms | 2.8 ms | 約 85 ms |
| 實機 | 待量測 | 待量測 | 待量測 | 待量測 |

### 方法二：外部慢動作錄影

以另一支手機 240 fps 慢動作錄影，同時拍到發聲（撥弦或音叉）與 PitchCoach 螢幕，逐格計算音軌波形起點到讀數出現的影格數（每格 4.17 ms），重複 20 次取 P50／P95。步驟見 [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md)。結果：**待實機量測**。

---

## 練習判定規則

詳細定義與理由見設計文件 §6、§7。

**調音器**：起音需 2 個有效 frame；保持讀數直到連續 8 個無效 frame 才回到「—」；相對目前顯示的音超過 65 cents 立即換音，50–65 cents 需持續 100 ms 才換；cents 以 EMA（50 ms）平滑。

**長音（10 秒）**：從按下開始後第一個有音高的 frame 起算；偏差相對目標音；±10 cents（含邊界）以內的比例分母為全部 frame（含無音高與錯音）；平均與母體標準差只用 |偏差| ≤ 50 cents 的 frame。

**音階到位**：有音高且 |偏差| ≤ 15.0 cents，從第一個在範圍內的 frame 起持續 ≥ 300 ms 即到位（299 ms 不算、300 ms 算）。**抖動規則**：範圍外（含無音高）的空檔 ≤ 50 ms 不重設計時，> 50 ms 才重設；只在範圍內的 frame 上到位。每音平均偏差只計 |偏差| ≤ 50 cents 的 frame；偏差最大 3 音以音高合併上下行。

**自由練習**：調音器畫面開著且偵測到演奏的時間；停頓 ≤ 5 秒計入、> 60 秒結束一段、少於 30 秒不記錄。只計入練習分鐘數，不計成績。

**中斷**：練習進行中遇到上表任一事件即標記「中斷」並保留已完成的部分；趨勢中的分鐘數與各音偏差計入中斷練習，長音準確率只用完成的練習。

**週報「最常偏高／偏低」**：區間內 frame 加權平均偏差超過 ±5 cents，且出現在至少 2 次練習中的音，各取前 3。

---

## 測試

共 **130 個測試**，全數通過。

| 套件 | 數量 | 重點 |
|---|---|---|
| `MusicTheoryTests` | 18 | A4 = 442／440 驗收案例、[-50, 50) 歸屬、12 調拼寫、起始八度範圍 |
| `SignalKitTests` | 4 | 種子決定性、SNR 混合精度 |
| `PitchDetectionTests` | 21 | 純正弦、二次泛音、SNR 20 dB、靜音與噪音、500 組性質測試、鋸齒波、串流切窗、即時信箱 |
| `AccompanimentTests` | 9 | 節拍器拍點精準不漂移、click 不被當成音高、drone 頻率與淡入淡出 |
| `PracticeEngineTests` | 47 | 調音器平滑、長音手算 fixture、到位 299／300 ms 與 ±15 抖動邊界、生命週期、自由練習、趨勢與週報 |
| `PitchCoachTests`（App） | 25 | 中斷策略與通知轉換、SwiftData 往返、PDF 文字抽取（中文與數字）、設定 |
| `PitchCoachUITests` | 6 | 合成訊號驅動：調音器、長音、音階、背景中斷與恢復、自由練習記錄、趨勢與週報分享 |

UI 測試以啟動參數 `-syntheticScenario` 讓收音管線改吃合成訊號（只在 DEBUG 組態編譯），偵測、判定、儲存與畫面皆走正式路徑；`-uiTesting` 使用記憶體內儲存。

---

## 實機驗收

需要實機與耳機的項目，步驟見 [docs/DEVICE_TESTING.md](docs/DEVICE_TESTING.md)。

| 驗收項目 | 狀態 |
|---|---|
| 內建麥克風／有線耳機／藍牙耳機（開啟伴奏）讀數差 ±3 cents，附截圖 | 待實機測試 |
| 延遲 ≤ 150 ms（慢動作錄影） | 待實機測試（模擬器內部時間戳估計約 85 ms） |
| 練習中來電、鬧鐘、插拔耳機不當機、恢復偵測、標記中斷 | 策略有單元測試、背景中斷有 UI 測試；實機待測 |
| PDF 透過分享選單存到「檔案」 | 模擬器已驗證分享選單；實機待測 |

---

## 已知限制

- **PDF 複製文字的部首問題**：PingFang 的部分字形（音、生、小、高…）同時對應康熙部首碼位，從 PDF 複製或搜尋時會得到部首字元（例如「⾳」U+2FB3 而非「音」U+97F3）。**畫面顯示完全正確**，僅影響複製與搜尋；測試以 NFKC 正規化驗證。
- **喇叭外放持續音會被麥克風收到**：未使用回音消除（voice processing 的降噪可能壓抑持續音），以喇叭播放持續音時 App 會提示戴耳機。
- **音階每音平均含滑音的過渡 frame**：換音瞬間分析窗橫跨兩個音，偏差在 ±50 cents 內的過渡 frame 會被計入，使平均略往鄰音方向稀釋（合成測試中 +12 cents 顯示為 +10.4 cents）。
- **諧波模型上限 16 個諧波**：泛音極豐富的低音會有微小偏差（鋸齒波最大 0.18 cent）；強烈非諧和的音色未驗證。
- **只處理單音**：不支援雙音與和弦（題目假設）。
- **藍牙耳機的麥克風不會被使用**（設計如此）；A2DP 的輸出延遲（約 150–250 ms）會讓聽到的節拍器較晚，但不影響偵測。
- **`.measurement` mode 的喇叭音量**尚未在實機確認；若伴奏過小，可改用 `.default` mode。
- **進入背景即暫停**，不支援背景收音（題目要求）。
- **週報與趨勢的音名一律用升記號**（例如 A#4），音階練習畫面則依調號拼寫（B♭4）。
- **iOS 27 模擬器**：`simctl privacy grant` 無法預先授予麥克風權限，第一次需手動按「允許」；模擬器的延遲數字不代表實機。
- 只支援 iPhone 直向與繁體中文。
