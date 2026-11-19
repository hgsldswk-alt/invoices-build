import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!
    override func setUp() { continueAfterFailure = false; app = XCUIApplication() }
    private func launch(_ arguments: [String], language: String = "en", locale: String = "en_US") {
        app.launchArguments = arguments + ["-AppleLanguages", "(\(language))", "-AppleLocale", locale]
        app.launch()
    }
    private func revealButton(_ id: String) -> XCUIElement {
        let element = app.buttons[id].firstMatch
        for _ in 0..<8 { if element.exists && element.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(element.waitForExistence(timeout: 8), id)
        XCTAssertTrue(element.isHittable, id)
        return element
    }
    private func tap(_ id: String) { revealButton(id).tap() }
    private func fill(_ id: String, _ value: String) {
        let element = app.textFields[id].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), id); element.tap()
        if let old = element.value as? String, !old.isEmpty && old != element.placeholderValue { element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        element.typeText(value)
    }
    private func tab(_ label: String) { let item = app.tabBars.buttons[label]; XCTAssertTrue(item.waitForExistence(timeout: 8)); item.tap() }
    private func shot(_ name: String) throws {
        let screenshot = app.screenshot(), attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        if let path = ProcessInfo.processInfo.environment["SHOTS_DIR"] ?? ProcessInfo.processInfo.environment["TEST_RUNNER_SHOTS_DIR"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: directory.appendingPathComponent(name + ".png"))
        }
    }
    func testStoreScreenshotsEnglish() throws {
        try captureStoreScreenshots(language: "en", locale: "en_US", sendLabel: "Send")
    }
    func testStoreScreenshotsSimplifiedChinese() throws {
        try captureStoreScreenshots(language: "zh-Hans", locale: "zh_CN", sendLabel: "发送")
    }
    func testStoreScreenshotsTraditionalChinese() throws {
        try captureStoreScreenshots(language: "zh-Hant", locale: "zh_TW", sendLabel: "傳送")
    }
    private func captureStoreScreenshots(language: String, locale: String, sendLabel: String) throws {
        launch(["-demo"], language: language, locale: locale)
        let invoice = app.buttons["document.INV-0042"]
        XCTAssertTrue(invoice.waitForExistence(timeout: 8))
        try shot("\(language)-01-store-invoices")
        tap("document.INV-0042")
        let send = app.buttons["editor.send"]
        XCTAssertTrue(send.waitForExistence(timeout: 8))
        XCTAssertEqual(send.label, sendLabel)
        try shot("\(language)-02-store-editor")
        tap("editor.preview")
        XCTAssertTrue(app.otherElements["pdf.canvas"].waitForExistence(timeout: 8))
        try shot("\(language)-03-store-pdf")

        app.terminate()
        launch(["-demo", "-estimates"], language: language, locale: locale)
        let estimate = app.buttons["document.EST-0012"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 8)); estimate.tap()
        XCTAssertTrue(app.textFields["editor.number"].waitForExistence(timeout: 8))
        _ = revealButton("estimate.convert")
        try shot("\(language)-04-store-estimate")

        app.terminate()
        launch(["-demo"], language: language, locale: locale)
        XCTAssertTrue(invoice.waitForExistence(timeout: 8))
        invoice.swipeLeft()
        tap("paid.INV-0042")
        XCTAssertTrue(app.staticTexts["paid.toast"].waitForExistence(timeout: 3))
        try shot("\(language)-05-store-paid")
    }
    func testFirstLaunchDirectlyCreatesInvoiceAndAutosaves() throws {
        launch(["-uitest-fresh"])
        XCTAssertTrue(app.textFields["editor.number"].waitForExistence(timeout: 8)); XCTAssertEqual(app.textFields["editor.number"].value as? String,"INV-0001")
        try shot("01-first-launch")
        fill("editor.business","Acme Plumbing"); fill("editor.clientName","Sam Carter")
        tap("editor.addItem"); fill("line.name","Kitchen repair"); fill("line.price","120")
        tap("line.done"); try shot("02-first-invoice-filled")
        tap("editor.close"); XCTAssertTrue(app.buttons["document.INV-0001"].waitForExistence(timeout: 8)); try shot("03-first-invoice-saved")
        tap("document.INV-0001"); XCTAssertEqual(app.textFields["editor.clientName"].value as? String,"Sam Carter")
    }
    func testMarkPaidAndUndo() throws {
        launch(["-demo"])
        let row = app.buttons["document.INV-0042"]; XCTAssertTrue(row.waitForExistence(timeout: 8)); row.swipeLeft()
        tap("paid.INV-0042"); XCTAssertTrue(app.staticTexts["paid.toast"].waitForExistence(timeout: 3)); try shot("04-paid-toast")
        tap("toast.undo"); XCTAssertTrue(row.waitForExistence(timeout: 3)); try shot("05-paid-undone")
        XCTAssertTrue(row.label.contains("due") || row.label.contains("Partially paid"))
    }
    func testEstimateConvertsInOneTap() throws {
        launch(["-demo","-estimates"])
        let estimate = app.buttons["document.EST-0012"]
        XCTAssertTrue(estimate.waitForExistence(timeout: 8)); estimate.tap(); try shot("06-estimate")
        tap("estimate.convert")
        XCTAssertTrue(app.textFields["editor.number"].waitForExistence(timeout: 8)); XCTAssertEqual(app.textFields["editor.number"].value as? String,"INV-0043")
        try shot("07-converted-invoice")
    }
    func testPreviewTemplates() throws {
        launch(["-demo","-editor"])
        XCTAssertTrue(app.buttons["editor.preview"].waitForExistence(timeout: 8))
        tap("editor.preview"); tap("template.Classic"); XCTAssertTrue(app.otherElements["pdf.canvas"].waitForExistence(timeout: 5)); try shot("08-classic-pdf")
        tap("template.Modern"); tap("accent.23466B"); try shot("09-modern-pdf")
    }
    func testBackupExportAlwaysAvailable() throws {
        launch(["-demo","-more"])
        XCTAssertTrue(app.buttons["more.reports"].waitForExistence(timeout: 8))
        tap("more.backup")
        XCTAssertTrue(app.buttons["backup.export"].waitForExistence(timeout: 5)); XCTAssertTrue(app.buttons["backup.csv"].exists); try shot("10-backup")
    }
    func testPaywallAndRestore() throws {
        launch(["-paywall"])
        XCTAssertTrue(app.staticTexts["paywall.title"].waitForExistence(timeout: 8)); XCTAssertTrue(app.buttons["paywall.restore"].exists); try shot("11-paywall")
    }
    func testPaidLaunchStartsTrialWithPremiumAccess() throws {
        launch(["-uitest-fresh"])
        XCTAssertTrue(app.buttons["editor.close"].waitForExistence(timeout: 8))
        tap("editor.close")
        for label in ["Invoices","Estimates","Clients","More"] {
            tab(label)
            XCTAssertFalse(app.staticTexts["paywall.title"].exists, label)
            try shot("12-trial-" + label.lowercased())
        }
        tap("more.reports")
        XCTAssertTrue(app.descendants(matching: .any)["reports.period"].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["paywall.title"].exists)
    }
    func testExpiredCanCreateAndExport() throws {
        launch(["-demo","-expired"])
        let newDocument = app.buttons["document.new"]
        XCTAssertTrue(newDocument.waitForExistence(timeout: 8)); newDocument.tap()
        XCTAssertTrue(app.textFields["editor.number"].waitForExistence(timeout: 8)); tap("editor.close")
        tab("More"); tap("more.backup"); XCTAssertTrue(app.buttons["backup.export"].exists); try shot("13-expired-data-available")
    }
}
