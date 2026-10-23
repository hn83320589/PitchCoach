import XCTest

/// 以合成訊號（-syntheticScenario）驅動的端到端測試，同時產生 README 用的截圖。
///
/// 啟動參數：
/// - `-uiTesting`：SwiftData 使用記憶體內儲存
/// - `-syntheticScenario <tuner|longTone|scale>`：以合成訊號取代麥克風
/// - `-referenceA4 442`、`-showsLatencyOverlay NO`：固定設定（UserDefaults 參數網域）
/// - `-seedDemoData`：在記憶體內儲存放入 28 天示範紀錄（以真正的判定器產生）
@MainActor
final class PitchCoachUITests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    private func launch(_ scenario: String, extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-uiTesting", "-syntheticScenario", scenario, "-referenceA4", "442", "-showsLatencyOverlay", "NO"]
            + extraArguments
        app.launch()
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForValue(_ element: XCUIElement, _ expected: String, timeout: TimeInterval) {
        let predicate = NSPredicate(format: "value == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed,
                       "\(element) 的值應為 \(expected)，實際為 \(String(describing: element.value))")
    }

    private func attachScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openPractice(_ app: XCUIApplication, _ title: String) {
        app.buttons["練習"].firstMatch.tap()
        app.staticTexts[title].firstMatch.tap()
        XCTAssertTrue(app.buttons["practice.start"].waitForExistence(timeout: 5), "\(title) 的設定頁應顯示「開始」")
    }

    // MARK: - 測試

    func testTunerShowsSyntheticA4Reading() {
        let app = launch("tuner")
        // A4 +3 cents（A4 = 442 Hz）→ 442.77 Hz
        waitForValue(element(app, "tuner.frequency"), "442.8 Hz", timeout: 5)
        waitForValue(element(app, "tuner.cents"), "+3 ¢", timeout: 3)
        attachScreenshot("01-tuner")
    }

    func testLongToneRunsTenSecondsAndShowsResult() {
        let app = launch("longTone")
        openPractice(app, "長音練習")
        attachScreenshot("02-long-tone-setup")
        app.buttons["practice.start"].tap()

        let accuracy = element(app, "longTone.accuracy")
        XCTAssertTrue(accuracy.waitForExistence(timeout: 20), "10 秒後應顯示結果")
        // A4 +4 cents、±8 cents 擺動：約 3/4 的時間在 ±10 cents 以內
        let value = try? XCTUnwrap(accuracy.value as? String)
        let percent = Int(value?.replacingOccurrences(of: "%", with: "") ?? "") ?? -1
        XCTAssertTrue((55...95).contains(percent), "準確率 \(value ?? "nil") 不在預期範圍")
        XCTAssertFalse(app.staticTexts["中斷：App 進入背景"].exists)
        attachScreenshot("03-long-tone-result")
    }

    func testScaleReachesEveryStepAndFlagsWorstNotes() {
        let app = launch("scale")
        openPractice(app, "音階練習")
        attachScreenshot("04-scale-setup")
        app.buttons["practice.start"].tap()

        let reached = element(app, "scale.reached")
        XCTAssertTrue(reached.waitForExistence(timeout: 30), "所有音到位後應顯示結果")
        // 結果頁出現後數值已固定，直接斷言（XCTNSPredicateExpectation 約每秒才輪詢一次，不適合極短逾時）
        XCTAssertEqual(reached.value as? String, "8 / 8")
        // 合成情境的偏差：E4 +12、B4 −9、A4 +6
        XCTAssertEqual(element(app, "scale.worst").value as? String, "E4、B4、A4")
        attachScreenshot("05-scale-result")
    }

    func testBackgroundingDuringLongToneMarksSessionInterrupted() {
        let app = launch("longTone")
        openPractice(app, "長音練習")
        app.buttons["practice.start"].tap()
        sleep(3)

        XCUIDevice.shared.press(.home)
        sleep(1)
        app.activate()

        XCTAssertTrue(app.staticTexts["中斷：App 進入背景"].waitForExistence(timeout: 5), "應標記為中斷")
        XCTAssertTrue(element(app, "longTone.accuracy").exists, "應保留已完成的部分")
        attachScreenshot("06-long-tone-interrupted")

        // 回到前景後偵測恢復：調音器有讀數
        app.buttons["調音器"].firstMatch.tap()
        XCTAssertTrue(element(app, "tuner.frequency").waitForExistence(timeout: 5))
        let resumed = NSPredicate(format: "value != %@", "—")
        XCTAssertEqual(XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: resumed, object: element(app, "tuner.frequency"))],
                                        timeout: 5), .completed, "回到前景後應恢復偵測")
    }

    func testHistoryShowsTrendsAndGeneratesWeeklyReport() {
        let app = launch("tuner", extraArguments: ["-seedDemoData", "-studentName", "王小明"])
        app.buttons["紀錄"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["每日練習分鐘數"].waitForExistence(timeout: 5), "應顯示趨勢圖")
        attachScreenshot("07-trends")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["各音平均偏差"].waitForExistence(timeout: 3))
        attachScreenshot("08-trends-notes")

        app.buttons["history.report"].tap()
        app.buttons["report.generate"].tap()
        XCTAssertTrue(app.buttons["report.share"].waitForExistence(timeout: 5), "產生後應可分享")
        attachScreenshot("09-weekly-report")

        app.buttons["report.share"].tap()
        sleep(2)
        attachScreenshot("10-share-sheet")
    }

    func testPlayingWithTunerOpenIsRecordedAsFreePractice() {
        let app = launch("tuner")
        // 自由練習需演奏滿 30 秒才記錄
        sleep(33)
        app.buttons["紀錄"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["自由練習"].waitForExistence(timeout: 5), "離開調音器時應存下自由練習紀錄")
    }
}
