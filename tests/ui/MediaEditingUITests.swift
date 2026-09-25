import XCTest

final class MediaEditingUITests: XCTestCase {
    @MainActor
    private func openEditor() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BLACKGOD_UI_TEST_NO_CONTINUOUS_ANIMATIONS"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["tab.2"].waitForExistence(timeout: 10))
        app.buttons["tab.2"].tap()
        let prompt = app.descendants(matching: .any)["media.prompt"]
        reveal(prompt, in: app)
        prompt.tap()
        prompt.typeText("A quiet forest cabin")
        return app
    }

    @MainActor
    func testDoneEditingRestoresNavigationWithoutCopying() {
        let app = openEditor()
        let done = app.buttons["media.editing.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 10))
        done.tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(app.buttons["media.copy"].label, "复制描述")
        XCTAssertTrue(app.buttons["tab.3"].waitForExistence(timeout: 10))
        app.buttons["tab.3"].tap()
        XCTAssertTrue(app.staticTexts["monitor.sample-count"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testCopyButtonPaddingCopiesAndEndsEditing() {
        let app = openEditor()
        let copy = app.buttons["media.copy"]
        reveal(copy, in: app)
        XCTAssertTrue(copy.isEnabled)
        // Verify the padded visible button, rather than only its text glyphs.
        copy.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "label == %@", "已复制描述"), evaluatedWith: copy)
        waitForExpectations(timeout: 10)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["tab.0"].waitForExistence(timeout: 10))
    }
}
