# 12　延伸練習與自我檢核

把閱讀變成動手。理解檢核的答案收合在 `<details>` 中，先自己想再展開。

---

## 12.1 理解檢核

1. 為什麼 `LongToneEvaluator` 裡完全沒有 `Date()` 或計時器，卻能判斷「10 秒到了」？
   <details><summary>答案</summary>
   時間由 `PitchFrame.time` 帶進來，判定器比較的是 frame 的時間戳。這讓測試不必真的等 10 秒，也不會因電腦忙碌而結果不同。見 03 章 3.4 節、`Packages/PitchCoachKit/Sources/PracticeEngine/LongToneEvaluator.swift`。
   </details>

2. MPM 選峰時為什麼是「第一個 ≥ 0.9 × 最高峰」，而不是「最高峰」？0.9 這個門檻能防住多強的二次泛音？
   <details><summary>答案</summary>
   「第一個」防止選到 2T（八度偏低），因為週期訊號在 2T 的峰和 T 幾乎一樣高。「0.9 門檻」防止選到 T/2（八度偏高）：n(T/2) ≈ (a² − 1)/(a² + 1)，要 a ≥ 4.36 才會誤判，題目條件 a = 2 有約 2 倍的餘量。見 08 章 8.1 節。
   </details>

3. 只用 MPM 已經能選對八度，為什麼還要諧波精修？
   <details><summary>答案</summary>
   MPM 的 NSDF 只看單一延遲的重疊段，SNR 20 dB 時低頻誤差達 8 cents；泛音讓峰變尖，拋物線內插偏差變大。諧波最小平方用到所有樣本與所有諧波，對 H 以內的週期訊號沒有內插偏差。見 08 章 8.1–8.2 節、`docs/ARCHITECTURE.md` §4.5。
   </details>

4. IO 執行緒把 frame 交給主執行緒時，為什麼不用 `DispatchQueue.main.async`？`RealtimeMailbox` 拿不到鎖時資料會遺失嗎？
   <details><summary>答案</summary>
   `async` 每次都會配置 closure 與排程結構，即時執行緒不能配置記憶體。拿不到鎖時值留在生產者專屬的 `pending` 暫存區，下次成功時一併送出，不會遺失；只有暫存區也滿時才丟掉最舊的值並累計 `droppedCount`。見 06 章 6.5 節。
   </details>

5. 歌唱判定為什麼要「先把每個 frame 折算到最近的八度，再取中位數」，而不是反過來？
   <details><summary>答案</summary>
   若偵測器在同一個音符內於兩個八度間跳動（例如 −1190 與 +10 cents），先取中位數會得到無意義的中間值；先折算則所有 frame 都在 ±600 cents 內，中位數正確。見 08 章 8.5 節。
   </details>

6. 用藍牙耳機唱歌時，系統怎麼避免學生被判定為「延遲約 200 ms」？為什麼還需要延遲校正？
   <details><summary>答案</summary>
   歌曲時間以「學生聽到歌曲起點」為 0，也就是歌曲起點被 render 的 host time 加上 iOS 回報的輸出延遲。iOS 回報的藍牙延遲是估計值，實機上少算了約 55 ms，所以用回授校正依路由補上。見 08 章 8.6 節、`Packages/PitchCoachKit/Sources/SingingEngine/SongClock.swift`。
   </details>

7. 「開啟回音消除時引擎無限重啟」這個問題，為什麼 7 個 UI 測試都沒抓到？
   <details><summary>答案</summary>
   UI 測試用 `-syntheticScenario` 以合成訊號驅動，完全不經過 AVAudioEngine，所以引擎層的行為不在測試範圍內。見 09 章 9.11 節、11 章踩坑 6。
   </details>

8. 同一個學生把「C C」連成一個長音時，為什麼不計入節奏正確率，而不是直接算錯？
   <details><summary>答案</summary>
   三種起音線索都不存在，量不到起音時間，算準或算錯都沒有依據；輕聲重新咬字（電平下降不到 6 dB）也會落在這一類，算錯會冤枉有咬字的學生。這是使用者在審查意見後做的決定。見 01 章 1.6 節例四、08 章 8.5 節。
   </details>

---

## 12.2 動手練習

### 練習 1：改參數，看哪個測試失敗

把 `Packages/PitchCoachKit/Sources/PitchDetection/PitchDetectorConfiguration.swift` 的 `peakThreshold` 預設值從 0.9 改成 0.6，執行：

```sh
swift test --package-path Packages/PitchCoachKit --filter PitchDetectionTests
```

哪些測試失敗？用 08 章 8.1 節的公式解釋。再試著把 `maxRefinementHarmonics` 設成 0（只用 MPM），看 SNR 20 dB 與性質測試的誤差變化。

> 提示：二次泛音的測試在 `MPMPitchDetectorTests.swift`；改完記得還原。

### 練習 2：新增一條判定規則需要改哪些檔案

需求：音階練習加一個「寬鬆模式」，到位門檻從 ±15 cents 放寬成 ±25 cents，並記錄在練習紀錄中。

列出需要改動的檔案，並為每個檔案寫一句要改什麼。

> 提示：判定器本身已經有 `tolerance` 參數（`ScaleEvaluator.init`）。要想的是：設定從哪裡來（畫面、`ScalePracticeModel`）、要不要存進資料庫（`PracticeSessionRecord`，05 章 5.5 節的 schema 演進方式）、週報是否要區分兩種模式（`PracticeAnalytics`）、要補哪些測試。

### 練習 3：補一個邊界測試

讀 `Packages/PitchCoachKit/Tests/PracticeEngineTests/ScaleEvaluatorTests.swift`，找出一個沒被測到的情況（例如負偏差側剛好 −15 cents 之後立刻空檔 50 ms 再到位），寫成測試。先預測結果再執行。

### 練習 4：把一個決策抽成純函式

`PitchCoach/Features/Singing/PitchRollView.swift` 的 KTV 音高條把「歌曲時間、音高」換算成畫面座標。把這個換算抽成一個純函式（例如放在 `PitchCoach/Features/Singing/` 下的新檔案），並在 `PitchCoachTests` 寫單元測試：現在線固定在寬度 30% 處、縱軸上下各留 3 個半音。

> 提示：09 章 9.11 節的「建議補強」第三項。

---

## 12.3 延伸專題

| 專題 | 內容 | 起點 |
|---|---|---|
| 依時間決定窗長 | 讓分析窗在 96 kHz 下仍是約 43 ms，hop 依比例調整；補上 96 kHz 的精度測試 | `StreamingPitchAnalyzer`、`PitchDetectorConfiguration` |
| 次諧波現象調查 | 錄一段確定沒有人聲的提示音，分析衰減時被讀成 1/2～1/5 頻率的原因（電平門檻？clarity？），做成回歸測試資料 | `docs/TEST_REPORT.md` §7 #4 |
| YIN 對照實作 | 在 `PitchDetection` 加一個 YIN 偵測器，用同一組精度、泛音、噪音、性質測試比較 | 08 章 8.1 節 |
| 引擎工廠注入 | 為 `AudioPipeline` 抽出可注入的引擎建立協定，用假引擎測試「啟動後立刻停下」的情境 | 09 章 9.11 節 |
| 延遲漂移偵測 | 演唱中持續觀察起音偏移的中位數，偏離校正值太多時提示重新校正 | 08 章 8.6 節 |
| 回音消除效果驗證 | 設計實機測試：喇叭外放、故意唱偏半音，確認判定為偏高；量化提示音被消除的程度 | `docs/DEVICE_TESTING.md`「喇叭外放時的回音消除」 |

---

## 12.4 延伸學習關鍵字

| 主題 | 搜尋關鍵字 |
|---|---|
| 音高偵測 | `McLeod pitch method`、`NSDF normalized square difference`、`YIN pitch detection de Cheveigné`、`octave error pitch detection` |
| 頻率估計 | `harmonic least squares frequency estimation`、`Cramér–Rao bound frequency estimation`、`Dirichlet kernel`、`window function spectral leakage` |
| 數值方法 | `Brent's method minimization`、`Cholesky decomposition quadratic form`、`Welford online variance`、`separable nonlinear least squares` |
| 穩健統計 | `robust statistics trimmed median`、`hysteresis thresholding` |
| 即時音訊 | `real-time audio programming rules`、`lock-free audio thread`、`priority inversion audio`、`AVAudioSinkNode latency` |
| Swift 併發 | `Swift 6 strict concurrency MainActor inference closure`、`@unchecked Sendable`、`OSAllocatedUnfairLock withLockIfAvailable` |
| 系統分析 | `functional core imperative shell`、`architecture decision record`、`requirements traceability matrix` |
| 測試 | `property-based testing`、`metamorphic testing`、`test pyramid`、`deterministic simulation testing` |
