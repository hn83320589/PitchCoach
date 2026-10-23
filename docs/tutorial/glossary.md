# 名詞對照表

## 樂理與領域術語

| 名詞 | 說明 | 出現位置 |
|---|---|---|
| A4 基準 | A4 對應的頻率，本 App 預設 442 Hz、可設 415–466 Hz | `TuningReference`、02 章 |
| cents | 對數的音高偏差，一個半音 = 100 cents | `NoteConverter`、02 章 |
| 八度 | 頻率加倍 | 02 章 |
| 半音 | 一個八度等比分成 12 份 | 02 章 |
| MIDI 編號 | 每個半音一個整數，A4 = 69、C4 = 60 | `Note` |
| 基頻（f₀） | 週期訊號的最低頻率成分，決定聽到的音高 | 08 章 |
| 泛音（諧波） | 基頻的整數倍頻率成分 | 08 章 |
| 共振峰（formant） | 母音造成的頻譜包絡峰，會讓某些泛音特別強 | `VoiceSynthesizer`、08 章 |
| 持續音（drone） | 練習時持續播放的主音 | `DroneSynthesizer` |
| 長音練習 | 對準目標音持續 10 秒，看準確率與穩定度 | `LongToneEvaluator` |
| 音階練習 | 依序演奏大調音階，每音 ±15 cents 持續 300 ms 到位 | `ScaleEvaluator` |
| 到位 | 音階練習中在範圍內持續 ≥ 300 ms | 08 章 8.4 節 |
| 顫音（vibrato） | 歌聲每秒 5–7 次的週期性音高擺動 | `VibratoAnalyzer` |
| 滑音 | 從下方滑進目標音 | 08 章 8.5 節 |
| 起音（onset） | 一個音實際開始的時刻 | `OnsetDetector` |
| 預備拍（count-in） | 歌曲開始前的 4 拍 click | `SongTimeline`、`SongPlayer` |
| 容許八度 | 唱高或低一個八度仍以偏差判定 | `SingingOptions.allowsOctaveShift` |
| 沒有分開唱 | 同音重複卻連成一個長音，量不到起音 | `RhythmVerdict.notSeparated` |
| 自由練習 | 調音器開著且偵測到演奏的時間 | `FreePracticeTracker` |

## 專案自訂名稱

| 名詞 | 說明 | 出現位置 |
|---|---|---|
| frame | 一次分析的結果：時間戳＋頻率（或無）＋電平，每 512 個樣本一個 | `PitchFrame` |
| 分析窗 | 一次分析使用的最近 2,048 個樣本 | `StreamingPitchAnalyzer` |
| hop | 相鄰兩次分析的間隔，512 個樣本 | `StreamingPitchAnalyzer` |
| clarity | NSDF 峰值，對「有明確週期」的信心 | `PitchEstimate` |
| 讀數 | 調音器顯示的音名、cents、Hz，多個 frame 平滑後的結果 | `TunerReading`、`TunerTracker` |
| 在範圍內 | 有音高且相對目標 \|cents\| ≤ 門檻（含邊界） | 02 章 |
| 歌曲時間 | 以學生聽到歌曲第一拍為 0 的時間 | `SongClock`、`SungFrame` |
| 延遲校正 | 播放 8 個提示音，量出 iOS 回報延遲之外的殘餘延遲，依路由儲存 | `LatencyCalibration` |
| 路由鍵 | 輸出埠類型＋裝置 UID，作為校正值的索引 | `AudioPipeline.routeKey` |
| 信箱 | IO 執行緒 → 主執行緒的無等待資料交換 | `RealtimeMailbox` |
| 合成輸入 | UI 測試用的合成訊號，取代麥克風 | `SyntheticInputSource` |
| 最常唱不準的音高區段 | 連續 5 個半音中不準比例最高、至少 3 個音的區段 | `WeakRange` |
| D1–D13、D-S1–D-S13 | 樂器模式與歌唱模式的設計決策編號 | `docs/ARCHITECTURE.md` §16、`docs/SINGING_MODE.md` §12 |
| M0–M8、S1–S6 | 樂器模式與歌唱模式的開發里程碑 | 同上 |

## 技術縮寫

| 縮寫 | 全名 | 說明 |
|---|---|---|
| FR／NFR | Functional／Non-Functional Requirement | 功能需求／非功能需求 |
| AC | Acceptance Criterion | 驗收標準 |
| ADR | Architecture Decision Record | 架構決策紀錄 |
| MPM | McLeod Pitch Method | 本專案的粗估偵測演算法 |
| NSDF | Normalized Square Difference Function | 正規化平方差函數 |
| YIN | — | 另一種常見的音高偵測演算法 |
| FFT | Fast Fourier Transform | 快速傅立葉轉換 |
| SNR | Signal-to-Noise Ratio | 訊雜比 |
| CRLB | Cramér–Rao Lower Bound | 估計誤差的理論下限 |
| EMA | Exponential Moving Average | 指數移動平均 |
| RMS | Root Mean Square | 均方根，表示訊號電平 |
| dBFS | Decibels relative to Full Scale | 相對滿刻度的分貝 |
| vDSP | — | Apple Accelerate 框架的訊號處理函式庫 |
| A2DP | Advanced Audio Distribution Profile | 藍牙高音質單向播放 |
| HFP | Hands-Free Profile | 藍牙通話，可用耳機麥克風但降到 16 kHz |
| AGC | Automatic Gain Control | 自動增益 |
| AEC | Acoustic Echo Cancellation | 回音消除（iOS 的 voice processing） |
| IO 執行緒 | — | iOS 呼叫音訊回呼的即時執行緒 |
| DI | Dependency Injection | 相依性注入 |
| CI | Continuous Integration | 持續整合 |
| UDID | Unique Device Identifier | 裝置唯一識別碼 |
