import XCTest

final class StoreShotsUITests: XCTestCase {
    private let languages = [("zh-Hans", "zh_CN"), ("en", "en_US"), ("zh-Hant", "zh_TW")]
    private let pages = [
        ("1-tonight", [String](), "startButton"),
        ("2-recording", ["-recording"], "stopButton"),
        ("3-result", ["-night"], "nightScore"),
        ("4-factors", ["-factors"], "factorsPage"),
        ("5-share", ["-share"], "shareCard"),
        ("6-paywall", ["-paywall"], "paywallPage")
    ]

    override func setUp() { continueAfterFailure = false }

    func testStoreScreenshots() throws {
        for (language, locale) in languages {
            for (shot, arguments, identifier) in pages {
                let app = XCUIApplication()
                app.launchArguments = ["-demo-night", "-paid-mode", "-AppleLanguages", "(\(language))", "-AppleLocale", locale] + arguments
                app.launch()
                XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: 12), "\(language) \(shot)")
                try attach(app, named: "store-\(language)-\(shot)")
                app.terminate()
            }
        }
    }

    func testCoreFlowAndExpiry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-uitest-fresh", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let start = app.buttons["startButton"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let stop = element("stopButton", in: app)
        XCTAssertTrue(stop.waitForExistence(timeout: 6))
        stop.press(forDuration: 0.8)
        let score = app.staticTexts["nightScore"]
        XCTAssertTrue(score.waitForExistence(timeout: 8))
        let before = score.label
        let notMe = app.buttons["notMe_0"]
        XCTAssertTrue(notMe.waitForExistence(timeout: 5))
        notMe.tap()
        XCTAssertNotEqual(score.label, before)
        try attach(app, named: "flow-result-excluded")

        let factor = app.buttons["factor_0"]
        for _ in 0..<3 where !factor.isHittable { app.swipeUp() }
        XCTAssertTrue(factor.isHittable)
        factor.tap()
        XCTAssertTrue(factor.isSelected)
        app.tabBars.buttons["因素"].tap()
        XCTAssertTrue(element("factorsPage", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["喝酒"].exists)
        app.tabBars.buttons["设置"].tap()
        for identifier in ["fullAudioSetting", "autoEndSetting", "exportSetting", "helpSetting", "purchaseSetting"] {
            XCTAssertTrue(element(identifier, in: app).waitForExistence(timeout: 5), identifier)
        }

        app.terminate()
        app.launchArguments = ["-demo-night", "-expired", "-night", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.staticTexts["nightScore"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["playClip_0"].exists)
        app.tabBars.buttons["History"].tap()
        XCTAssertTrue(element("historyPage", in: app).waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()
        XCTAssertTrue(element("exportSetting", in: app).exists)
        app.buttons["purchaseSetting"].tap()
        XCTAssertTrue(app.buttons["restorePurchases"].waitForExistence(timeout: 5))
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func attach(_ app: XCUIApplication, named name: String) throws {
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        let paths = ProcessInfo.processInfo.environment
        if let path = paths["SHOTS_DIR"] ?? paths["TEST_RUNNER_SHOTS_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        }
    }
}
