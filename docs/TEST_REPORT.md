# PitchCoach 測試報告

| 項目 | 內容 |
|---|---|
| 報告日期 | 2026-10-23 |
| 受測版本 | 自動化測試：`01c8989`。實機：`cd38059` 起的建置（含路由診斷），「恢復收音」以 `4a590eb` 驗證 |
| 測試範圍 | 驗收標準 AC-01～AC-21（含歌唱模式）、功能需求 FR-01～FR-21、非功能需求 NFR-01～NFR-06 |
| 結論 | **自動化測試與實機驗收皆通過**（iPhone 15 Pro Max、AirPods Pro）。缺設備而未做的部分：有線耳機（AC-11、AC-12）、第二支手機（真正的來電、AC-08 慢動作錄影） |

---

## 1. 結果摘要

| 指標 | 結果 |
|---|---|
| 自動化測試 | **191 / 191 通過**，0 失敗、0 略過（題目要求 ≥ 55） |
| 編譯警告 | **0**（Package 與 App 皆以全新建置目錄重新編譯確認） |
| GitHub Actions | 每次 push 執行 `swift test`（149 個）＋ iOS 模擬器上的 App 單元測試與 UI 測試（42 個），見 [Actions](https://github.com/hn83320589/PitchCoach/actions) |
| 第三方套件 | 0 個（Package 無外部相依、Xcode 專案無遠端套件參照） |

| 驗收狀態 | 數量 | 項目 |
|---|---|---|
| ✅ 通過 | 19 | AC-01～AC-07、AC-09、AC-10、AC-12～AC-21 |
| 🟡 部分通過（缺設備的部分未做） | 2 | AC-08（慢動作錄影）、AC-11（有線耳機） |
| ⏳ 待實機 | 0 | — |

---

## 2. 測試環境

| 項目 | 版本 |
|---|---|
| 電腦 | Apple M4 Pro，macOS 27.0.1（26A434） |
| Xcode | 27.0（27A266a） |
| Swift | 6.4（swiftlang-6.4.0.34.1） |
| 模擬器 | iPhone 18 Pro，iOS 27.0（24A434） |
| 實機 | iPhone 15 Pro Max（iPhone16,2），iOS 27.0.1（24A446）；AirPods Pro |
| CI | GitHub Actions `macos-15` |
| 部署目標 | iOS 17.0（App 與 Package 皆同） |

執行指令：

```sh
# Package（macOS）
swift test --package-path Packages/PitchCoachKit

# App 單元測試＋UI 測試（模擬器，乾淨建置）
xcodebuild clean test -project PitchCoach.xcodeproj -scheme PitchCoach \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -derivedDataPath build/ReportDD
```

---

## 3. 自動化測試結果

| 測試目標 | 執行環境 | 數量 | 結果 |
|---|---|---|---|
| `MusicTheoryTests` | macOS | 18 | ✅ 全數通過 |
| `SignalKitTests` | macOS | 7 | ✅ 全數通過 |
| `PitchDetectionTests` | macOS | 24 | ✅ 全數通過 |
| `AccompanimentTests` | macOS | 13 | ✅ 全數通過 |
| `SingingEngineTests` | macOS | 38 | ✅ 全數通過 |
| `PracticeEngineTests` | macOS | 49 | ✅ 全數通過 |
| `PitchCoachTests`（App 單元） | 模擬器 | 35 | ✅ 全數通過 |
| `PitchCoachUITests` | 模擬器 | 7 | ✅ 全數通過 |
| **合計** | | **191** | **✅ 191 / 191** |

UI 測試以啟動參數 `-syntheticScenario` 讓收音管線改吃合成訊號，偵測、判定、儲存與畫面都走正式路徑，不需要麥克風權限。本機（iPhone 18 Pro、iOS 27.0）與 CI（從 runner 最新的 iOS runtime 挑第一台 iPhone）都會執行。

---

## 4. 驗收標準逐項對照

### 4.1 樂器模式（AC-01～AC-14）

| # | 驗收標準 | 狀態 | 證據 |
|---|---|---|---|
| AC-01 | Xcode 開啟即可建置（模擬器／實機） | ✅ | CI 在 iOS 模擬器建置並測試成功；本機乾淨建置 0 警告；實機（iPhone 15 Pro Max）以個人 Team 建置安裝成功 |
| AC-02 | 純正弦 65–2,100 Hz 每半音、44.1k／48k，誤差 < 1¢ | ✅ | `pureSineEverySemitoneAt44100/48000IsWithinOneCent`。**實測**：62 個頻率，兩種取樣率最大 **0.0010¢**、平均 0.0002¢ |
| AC-03 | 二次泛音強 2 倍不發生八度錯誤 | ✅ | `strongSecondHarmonicCausesNoOctaveErrorAt44100/48000`。**實測**：八度錯誤 **0**，最大誤差 0.0007¢（44.1k）／0.0005¢（48k） |
| AC-04 | 白噪音 SNR 20 dB 誤差 < 3¢ | ✅ | `whiteNoiseAt20dBSNRStaysWithinThreeCents`。**實測**：測試種子最大 1.26¢（44.1k）／1.64¢（48k）；20 個種子各 62 頻率的壓力量測（各 1,240 次）最大 **2.25¢**／1.84¢，沒有漏偵測 |
| AC-05 | 靜音、純噪音不輸出音高 | ✅ | `silenceProducesNoPitch`、`signalBelowLevelGateProducesNoPitch`、`whiteNoiseProducesNoPitch`、`frequenciesOutsideDetectionRangeProduceNoPitch`、`framesWithoutPitchShowDash`。模擬器真實收音：測試音停止後（背景約 −48 dBFS）顯示「—」 |
| AC-06 | ≥ 500 組隨機頻率＋隨機泛音性質測試 | ✅ | `randomHarmonicSignalsHaveNoOctaveErrorsAndStayWithinFiveCents`。**實測**：500 組，八度錯誤 **0**，最大誤差 **0.0010¢** |
| AC-07 | A4=442 → 442 Hz 為 A4 0¢；A4=440 → +7.85¢ | ✅ | `frequency442AtReference442IsA4WithZeroCents`、`frequency442AtReference440IsA4WithPlus7Point85Cents`、`readingFollowsTuningReference`、`defaultReferenceIs442Hz` |
| AC-08 | 延遲 ≤ 150 ms 並說明量測方式 | 🟡 | 量測方式寫在 README「延遲量測」。**實機內部時間戳**：管線 P50 30–31 ms、P95 38–40 ms，硬體輸入 6.7 ms，端到端估計約 **98 ms**（§5.2）。外部慢動作錄影未做（沒有第二台可錄影的裝置） |
| AC-09 | 長音指標與手算一致 | ✅ | `metricsMatchHandCalculation`、`toleranceBoundaryOf10CentsIsInclusive`、`framesWithoutPitchCountAsOutOfTolerance`、`timingStartsAtFirstVoicedFrame`、`noUsableFramesGivesNilStatistics`；UI：`testLongToneRunsTenSecondsAndShowsResult` |
| AC-10 | 到位判定 299／300 ms 邊界、±15¢ 抖動規則 | ✅ | `holding299msDoesNotAdvance`、`holding300msAdvances`、`exactly15CentsOnEitherSideCountsAsInTolerance`、`justBeyond15CentsNeverAdvances`、`excursionOf50msIsBridged`、`excursionLongerThan50msRestartsHold`；UI：`testScaleReachesEveryStepAndFlagsWorstNotes` |
| AC-11 | 內建麥克風／有線耳機／藍牙耳機讀數差 ±3¢，附截圖 | 🟡 | **實機**：內建麥克風與 AirPods Pro 皆為 A4、0¢、442.0 Hz，相差 **0¢**；路由診斷證實藍牙時仍以內建麥克風收音（§5.1）。有線耳機未測（沒有設備） |
| AC-12 | 模擬來電／插拔耳機不當機、可恢復、標記中斷 | ✅ | 狀態機與事件策略：`interruptionWhileRunningMarksSessionInterruptedWithReason`、`phoneCallInterruptsPracticeAndResumesDetectionAfterward`、`pluggingOrUnpluggingHeadphonesInterruptsPracticeAndRebuildsEngine`、`mediaServicesResetAndConfigurationChangeRestartEngine`、`configurationChangeDuringSongInterruptsSinging` 等。UI：`testBackgroundingDuringLongToneMarksSessionInterrupted`；練習頁恢復收音：`AudioUnavailableNoticeTests`。**實機**：鬧鐘、Siri、音樂播放、AirPods 中斷、進入背景 5 種情境皆不當機、標記中斷並保留已完成部分，練習頁可恢復收音（§5.4）。真正的來電與插拔有線耳機未測（沒有第二支手機與有線耳機），鬧鐘、Siri、音樂與來電觸發同一種 iOS 音訊中斷事件 |
| AC-13 | PDF 數據與紀錄一致、中文正常、可存到「檔案」 | ✅ | `weeklyReportSummarizesPracticeAndScores`、`pdfContainsSearchableChineseTextAndReportNumbers`、`pdfPageIsA4`；UI：`testHistoryShowsTrendsAndGeneratesWeeklyReport`（產生週報並開啟分享選單）。**實機**：存到「檔案」後可開啟、中文正常，數字與紀錄一致（§5.5） |
| AC-14 | 測試 ≥ 40 個全數通過 | ✅ | 191 個全數通過 |

### 4.2 歌唱模式（AC-14'～AC-21）

| # | 驗收標準 | 狀態 | 證據 |
|---|---|---|---|
| AC-14' | 測試 ≥ 55 個 | ✅ | 191 個全數通過 |
| AC-15 | 人聲模擬（泛音＋共振峰＋5.5 Hz ±60¢ 顫音）：中心 < 5¢、速度 < 0.5 Hz、幅度 < 10¢ | ✅ | `vibratoVoiceYieldsCenterRateAndDepth`（男、女、童聲三組）。**實測**見下表 |
| AC-16 | 前 20% 從 −100¢ 滑上來仍判定「準」 | ✅ | `glideIntoFirstTwentyPercentStillCountsAsAccurate`（判定器）、`glidingVoiceIsStillAccurate`（人聲走完整條處理鏈） |
| AC-17 | 容許八度：整首低八度 → 準；關閉 → 偏低 | ✅ | `octaveToleranceDecidesWhetherLowOctaveCounts`、`lowOctaveVoiceDependsOnOctaveTolerance` |
| AC-18 | 合成演唱訊號，起音誤差 < 30 ms | ✅ | `synthesizedSingingOnsetsAreLocatedWithinThirtyMilliseconds`、`legatoPitchChangeIsDetectedAtPitchCrossing`；同音連唱沒有重新咬字時不給假的起音：`repeatedNoteSungAsOneSustainedToneIsNotSeparated`、`fastRepeatedNotesWithoutRearticulationAreNotCountedOnTime`。**實測**見下表 |
| AC-19 | 實機：內建喇叭與藍牙耳機的節奏判定一致、起音誤差 ±80 ms | ✅ | 規則：`eightyMillisecondBoundaryDecidesOnTimeEarlyOrLate`、`songClockUsesWindowCenterAndRemovesLatencies`、`offsetIsMedianOnsetDelayOfCalibrationTones`。**實機回授自我測試**：未校正前的殘餘誤差喇叭 +21～+39 ms、AirPods Pro +52～+57 ms，各 3 次全部在 ±80 ms 內（§5.3）。真人演唱的對照未做 |
| AC-20 | 自訂格式錯誤指出第幾個音符與原因、不當機 | ✅ | `invalidNoteNameReportsIndexTokenAndReason`、`missingOrInvalidOctaveIsReported`、`missingOrInvalidDurationIsReported`、`emptyInputIsAnError`、`notesOutsideSingableRangeAreRejected` |
| AC-21 | 移調後目標音高、音高條、判定同步改變 | ✅ | `transposingShiftsEveryPitchAndKeepsRests`、`transpositionChangesPitchButNotTiming`、`transpositionMovesTargetsAndVerdicts`、`playerScoreFollowsTransposedTimeline`；UI：`testSingingTranspositionAndFullSongWithKaraokeRoll`（移調 +2 後音域由 C4–G4 變成 D4–A4） |

**AC-15 實測值**（在本版程式碼上重新量測）：

| 聲音 | 中心音高誤差 | 顫音速度 | 顫音幅度 |
|---|---|---|---|
| 男聲 /a/（E3） | 0.02¢ | 5.500 Hz | 60.08¢ |
| 女聲 /i/（A4） | 0.05¢ | 5.500 Hz | 60.04¢ |
| 童聲 /u/（E5） | 0.05¢ | 5.500 Hz | 60.03¢ |
| 門檻 | < 5¢ | 5.5 ± 0.5 Hz | 60 ± 10¢ |

**AC-18 實測值**（〈小星星〉開頭 7 個音，涵蓋換氣後起音、同音重複、連唱換音）：

| 音 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|
| 實際偏移（ms） | 0 | +50 | −40 | +120 | 0 | −90 | +30 |
| 偵測偏移（ms） | +1.3 | +43.0 | −46.7 | +117.0 | −3.7 | −95.2 | +32.9 |
| 誤差（ms） | 1.3 | 7.0 | 6.7 | 3.0 | 3.7 | 5.2 | 2.9 |

最大誤差 **7.0 ms**，門檻 30 ms。

---

## 5. 實機驗收

裝置：iPhone 15 Pro Max（iOS 27.0.1）、AirPods Pro。測試音為 `scripts/make-test-tone.py` 產生的 442 Hz（A4 = 442 Hz），由另一台裝置在約 30 cm 外播放。截圖在 `docs/device/`。

### 5.1 AC-11 音訊路由

| 路由 | 讀數 | 輸入電平 | 截圖 |
|---|---|---|---|
| 內建麥克風（無耳機） | A4、0¢、442.0 Hz | −47.4 dBFS | `route-builtin.png` |
| AirPods Pro | A4、0¢、442.0 Hz | −42.9 dBFS | `route-bluetooth.png` |
| 有線耳機 | 未測（沒有設備） | — | — |

兩種路由相差 0¢（門檻 ±3¢）。延遲面板的路由診斷（`route-bluetooth-ports.png`）顯示「輸入 iPhone 麥克風（MicrophoneBuiltIn）、輸出 AirPods Pro（BluetoothA2DPOutput）」，證實連上藍牙耳機時仍以內建麥克風收音，耳機只負責播放。

第一次拍藍牙截圖時輸入電平只有 −60.6 dBFS，低於偵測門檻 −50 dBFS 而顯示「—」；調整音源後為 −42.9 dBFS，正常讀到 A4。原因是測試音傳到麥克風時太小聲，不是路由問題（見 §7 #7）。

### 5.2 AC-08 延遲（內部時間戳）

| 項目 | 實機 | 模擬器（參考） |
|---|---|---|
| 管線 P50（分析窗結束 → 畫面） | 30–31 ms | 10–12 ms |
| 管線 P95 | 38–40 ms | 18 ms |
| 硬體輸入延遲 | 6.7 ms | 2.8 ms |
| 端到端估計（最壞） | **約 98 ms** | 約 85 ms |

端到端估計 = 硬體輸入 6.7 ＋ 分析窗 42.7 ＋ 等待 hop 10.7 ＋ P95 38 ms，低於 150 ms 的門檻。外部慢動作錄影未做（沒有第二台可錄影的裝置）。

### 5.3 AC-19 延遲校正回授

在「延遲校正」畫面播放 8 個 A4 提示音，以內建麥克風收回。畫面顯示的偏移是「只靠 iOS 回報的輸出延遲對齊」後的殘餘誤差（尚未套用校正值）。藍牙測試時關閉 AirPods 的自動入耳偵測，並把一邊耳機貼在 iPhone 底部的麥克風上。

| 路由 | iOS 回報的輸出延遲 | 8 個提示音的殘餘偏移 | 校正值（中位數），3 次 | 截圖 |
|---|---|---|---|---|
| 內建喇叭 | 10 ms | +21～+39 ms | +24、+24、+33 ms | `ac19-speaker-1～3.png` |
| AirPods Pro | 176 ms | +52～+57 ms（第 1 次的第 1 個未偵測到，其餘 7 個） | +57、+55、+55 ms | `ac19-bluetooth-1～3.png` |

- 未校正前的殘餘誤差全部在 ±80 ms 內：一個準時演唱的學生，在喇叭與藍牙都會被判定「準時」，兩種路由的節奏判定一致。
- 套用校正值後，兩種路由的殘餘誤差都接近 0。藍牙實際延遲約 176 ＋ 55 ≈ 230 ms，iOS 回報值少算約 55 ms，喇叭少算約 25 ms，兩者不同，印證「依路由分別校正」的必要。
- 偏移在 21／26 ms、52／57 ms 之間交替，相差約 5.3 ms，等於電平分析的子區塊（256 樣本），是起音偵測的時間解析度；整首沒有漂移。
- 喇叭第 1、2 次的 8 個數字完全相同。這和偵測的格點量化相符，但無法從截圖確認是兩次獨立校正。

### 5.4 AC-12 練習中斷

都在長音練習倒數中觸發：

| 觸發 | 結果頁 | 保留秒數 | 截圖 |
|---|---|---|---|
| 鬧鐘（代替來電） | 中斷：來電或其他 App 使用音訊 | 9.2 秒 | `ac12-alarm.png` |
| Siri | 同上 | 0.9 秒 | `ac12-siri.png` |
| 控制中心播放音樂 | 同上 | 3.7 秒 | `ac12-music.png` |
| AirPods Pro 放回充電盒 | 中斷：耳機連接或中斷 | 4.0 秒 | `ac12-bluetooth.png` |
| 回到主畫面再回來 | 中斷：App 進入背景 | 2.2 秒 | `ac12-background.png` |

- 5 種情境都沒有當掉，都正確標記原因並保留已完成的部分。
- 沒有第二支手機，以鬧鐘、Siri、音樂代替來電：四者在 App 內觸發同一個 `AVAudioSession.interruptionNotification`，走同一條處理路徑。插拔有線耳機未測（沒有設備），藍牙斷線走同一條「耳機連接或中斷」路徑。
- AirPods 那一次準確率 0%、平均偏差「—」：當時沒有收到 A4 附近的聲音，不影響中斷判定。
- **恢復**：測試中發現練習頁原本沒有恢復收音的方法（§7 #5），修正後在練習設定頁顯示「收音已暫停」與「恢復收音」（`ac12-resume.png`）。實務上，進入 PitchCoach 時系統通常會先暫停其他 App 的音樂，所以這個按鈕主要用在練習途中被其他 App 搶走音訊、而 iOS 沒有建議恢復的情況。

### 5.5 AC-13 PDF 存到「檔案」

週報 → 產生 → 分享 → 儲存到「檔案」→ 在「檔案」App 開啟（`ac13-pdf-in-files.png`，PDF 原檔 `PitchCoach_週報_2026-10-17_2026-10-23.pdf`）：

- 可以開啟，中文顯示正常。
- 數字與紀錄一致：練習 19 次 = 長音完成 12 次 ＋ 中斷 6 次 ＋ 歌唱 1 次。
- 發現總時數說明寫「以及長音、音階練習」，但數字也包含歌唱時間（§7 #6，已修正；這份 PDF 是修正前產生的）。

---

## 6. 模擬器真實音訊驗證

自動化測試都用合成訊號。本輪另外在模擬器上，用 Mac 的喇叭與麥克風走真實的聲學路徑。

### 6.1 調音器

由 Mac 喇叭播放 442 Hz 測試音 6 秒（A4 = 442 Hz）：

| 時間點 | 顯示 |
|---|---|
| 播放中 | **A4、0¢、442.0 Hz**，指針在綠色區 |
| 停止後 | 「—」（背景電平約 −48 dBFS，沒有誤報） |
| 延遲面板 | P50 11 ms、P95 18 ms、硬體輸入 2.8 ms |

### 6.2 延遲校正回授（AC-19 的模擬器試跑）

App 從 Mac 喇叭播放 8 個 A4 提示音，由 Mac 麥克風收回：

| 提示音 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| 起音偏移（ms） | +73 | +78 | +73 | +78 | +73 | +78 | +73 | +78 |

8 個全部偵測到，中位數 +75 ms，整首沒有漂移。模擬器回報的輸出延遲是 0 ms，所以這 75 ms 是 iOS 沒算進去的部分（Mac 的喇叭與麥克風緩衝、模擬器轉接、聲音在空氣中的傳遞），由依路由的校正值補上。這只是模擬器上的參考值，不能代替實機量測。

### 6.3 歌唱音準判定的依據

使用者反映「已經唱很高還是被判偏低」，因此做了三項交叉檢驗：

| 檢驗 | 結果 |
|---|---|
| 離線合成〈兩隻老虎〉的提示音，直接餵給偵測器 | 32 個音全部 0¢ |
| 錄下模擬器的麥克風輸入，與獨立的頻譜分析比對 | 每個時間點的頻率一致（例如偵測 158 Hz，頻譜峰值 158 Hz） |
| 使用者 5 次紀錄的每音偏差 | 中位數 −348～−781¢，每次不同，而且不是整整一個八度 |

結論：判定正確，使用者是用自己習慣的調在唱，比目標低了 3.5～8 個半音，並不是偵測器的八度錯誤。建議先用調音器對準第一個音，並戴耳機聽清提示音。

---

## 7. 本輪發現的問題

| # | 問題 | 嚴重度 | 狀態 |
|---|---|---|---|
| 1 | 開啟回音消除的引擎在模擬器上啟動約 0.1 秒就自己停下，App 每 0.45 秒重建一次而陷入無限循環；演唱中引擎重建後畫面永遠停在「預備…」 | 高 | **已修正**（`eb260fb`）：連續 2 次停下就退回不消除的模式；演唱中引擎重建時標記「中斷：收音失敗」並保留已唱完的音。新增 3 個測試，並在模擬器以真實音訊驗證 |
| 2 | 同音重複卻連成一個長音（沒有重新咬字）時，三種起音線索都不存在，退回規則取到前一個音的 frame：一般速度判定「提早約 250 ms」，200 BPM 十六分音符反而判定「準時」（程式碼審查提出，合成測試證實） | 中 | **已修正**（`cd38059`）：前一個音同音高且發聲沒有中斷時，標示「沒有分開唱」，不計入節奏正確率。新增 2 個測試 |
| 3 | Xcode 按 Run 時顯示 `Unable to resolve module dependency: 'SingingEngine'` | 低（環境） | Xcode 自己的建置快取過期，程式碼沒問題；清除建置資料夾（⇧⌘K）即可。命令列與 CI 都使用乾淨的建置目錄 |
| 4 | 某次回授測試中，提示音有幾個音被讀成基頻的 1/2～1/5（次諧波） | 待確認 | 可能是提示音衰減後音量接近背景噪音所致；無法確定當時是否完全沒有人出聲。不影響有人演唱時的判定（歌聲遠大於提示音）。實機的延遲校正（§5.3）只用起音、不受影響；回音消除驗證仍需留意 |
| 5 | 收音被中斷後，若 iOS 沒有建議恢復，只有調音器頁有「恢復收音」；練習頁只顯示灰色的「開始」與「收音尚未啟動」（說法也不正確） | 中 | **已修正**（`4a590eb`）：三個練習頁依收音狀態顯示「收音已暫停／恢復收音」「無法啟動／重試」「需要權限／前往設定」。新增 4 個測試，實機驗證 |
| 6 | 週報總時數說明寫「以及長音、音階練習」，但數字也包含歌唱時間 | 低 | **已修正**（`01c8989`）：改為「長音、音階、歌唱練習」，PDF 文字測試加入檢查 |
| 7 | 偵測門檻 −50 dBFS 在實機上的餘量不大：`.measurement` 模式沒有自動增益，30 cm 外手機播放的測試音只有 −43～−47 dBFS | 觀察 | 一般演奏與演唱比測試音大聲，實測沒有問題；但長笛或小提琴離手機太遠、或音量很小時可能顯示「—」。已寫入 README 已知限制，是否降低門檻需以真實樂器再評估（門檻太低會讓背景噪音被誤判為音高） |

---

## 8. 未完成的項目

步驟見 [DEVICE_TESTING.md](DEVICE_TESTING.md)。

| 項目 | 缺少的設備或原因 | 要做什麼 |
|---|---|---|
| AC-08 外部量測 | 另一台可 240 fps 慢動作錄影的裝置 | 慢動作錄影 20 次，記錄 P50／P95 |
| AC-11 有線耳機 | 有線耳機 | 接上有線耳機、開啟伴奏，截一張調音器畫面 |
| AC-12 真正的來電、插拔有線耳機 | 第二支手機、有線耳機 | 練習中來電、插拔有線耳機 |
| AC-19 真人演唱 | （時間） | 同一首歌，喇叭與藍牙各唱 3 次，比較節奏正確率與起音差 |
| 回音消除 | （時間） | 用喇叭外放，故意唱錯一個音，確認被判定為偏高或偏低 |

---

## 9. 附註

- 量測值是在本版程式碼上用臨時量測程式重新計算的（不納入 repo）。量測用的訊號、種子與頻率清單和正式測試相同。各項門檻則由正式測試斷言，本次全部通過。
- README 的 SNR 20 dB 量測數字已依本次重新量測的結果更新。
