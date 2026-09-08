import XCTest

final class BlackGodUITests: XCTestCase {
    @MainActor
    func testOAuthLoginEntryAndBrowserCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["tab.4"].tap()
        app.buttons["api.open"].tap()
        let login = app.buttons["oauth.login"]
        XCTAssertTrue(login.waitForExistence(timeout: 10))
        for id in ["kimi-oauth", "grok-oauth", "minimax-oauth", "minimax-cn-oauth"] {
            XCTAssertTrue(app.buttons["oauth." + id].exists)
        }
        let entry = XCTAttachment(screenshot: app.screenshot()); entry.name = "OAuth登录入口"; entry.lifetime = .keepAlways; add(entry)
        login.tap()
        // Only open the provider's login page and cancel; never submit credentials or consent.
        let done = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "关闭", "Close")).firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 15), app.debugDescription)
        let browser = XCTAttachment(screenshot: app.screenshot()); browser.name = "OAuth官方授权页面"; browser.lifetime = .keepAlways; add(browser)
        done.tap()
        XCTAssertTrue(login.waitForExistence(timeout: 10))
        let status = app.staticTexts["oauth.status"]
        let cancelled = NSPredicate(format: "label == %@", "已取消登录。")
        expectation(for: cancelled, evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(login.isEnabled)
    }

    @MainActor
    func testDeviceLoginBrowserReturnAndExplicitCancellation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); app.buttons["tab.4"].tap(); app.buttons["api.open"].tap()
        let login = app.buttons["oauth.kimi-oauth"]
        XCTAssertTrue(login.waitForExistence(timeout: 10)); login.tap()
        // Anonymous authorization only. Never submit account details or consent.
        let close = app.buttons.matching(NSPredicate(format: "label == %@ OR label == %@", "关闭", "Close")).firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 25)); close.tap()
        let cancel = app.buttons["oauth.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertFalse(login.isEnabled)
        if !cancel.isHittable { app.swipeUp() }
        cancel.tap()
        let status = app.staticTexts["oauth.status"]
        expectation(for: NSPredicate(format: "label == %@", "已取消登录。"), evaluatedWith: status)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(login.isEnabled)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "设备授权取消后"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testClaudeConfigurationAndExplicitDataPermission() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); app.buttons["tab.4"].tap(); app.buttons["api.open"].tap()
        let claude = app.buttons["claude.api"]
        for _ in 0..<5 where !claude.isHittable { app.swipeUp() }
        XCTAssertTrue(claude.isHittable); claude.tap()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Claude接入说明"; shot.lifetime = .keepAlways; add(shot)
        let consent = app.switches["api.data-consent"]
        for _ in 0..<8 where !consent.isHittable { app.swipeUp() }
        XCTAssertTrue(consent.isHittable)
        XCTAssertEqual(consent.value as? String, "0")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: consent)
        waitForExpectations(timeout: 3)
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: consent)
        waitForExpectations(timeout: 3)
        let privacy = XCTAttachment(screenshot: app.screenshot()); privacy.name = "模型数据发送许可"; privacy.lifetime = .keepAlways; add(privacy)
    }

    @MainActor
    func testBuiltInPracticeAndStorageControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["tab.1"].tap(); app.swipeUp()
        app.buttons["shuyu.open"].tap()
        app.buttons["shuyu.generate"].tap()
        XCTAssertTrue(app.staticTexts["shuyu.word"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["词形与汉译反查一致"].exists)
        let language = XCTAttachment(screenshot: app.screenshot()); language.name = "枢语语言"; language.lifetime = .keepAlways; add(language)
        app.buttons["完成"].tap()
        app.buttons["storage.open"].tap()
        XCTAssertTrue(app.buttons["storage.budget.8"].waitForExistence(timeout: 10))
        let capacity = app.staticTexts["手机剩余空间"]
        XCTAssertTrue(capacity.waitForExistence(timeout: 20))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "运行空间"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["完成"].tap()
        app.buttons["tab.4"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "任务技能")).firstMatch.tap()
        let start = app.buttons["practice.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 10))
        start.tap()
        let report = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "12/12个样例通过")).firstMatch
        for _ in 0..<3 where !report.exists { app.swipeUp() }
        XCTAssertTrue(report.waitForExistence(timeout: 30))
        let practice = XCTAttachment(screenshot: app.screenshot()); practice.name = "技能演练"; practice.lifetime = .keepAlways; add(practice)
    }

    @MainActor
    func testNaturalTaskEntryHidesTerminalAndLiveOutputArrivesBeforeExit() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["tab.1"].tap()
        XCTAssertTrue(app.buttons["execution.start"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["execution.start"].isEnabled)
        XCTAssertFalse(app.textViews["linux.command"].exists)
        let entry = XCTAttachment(screenshot: app.screenshot())
        entry.name = "自然语言任务入口"; entry.lifetime = .keepAlways; add(entry)
        app.swipeUp()
        app.buttons["linux.advanced"].tap()
        XCTAssertTrue(app.buttons["linux.clear"].waitForExistence(timeout: 10))
        app.buttons["linux.clear"].tap()
        app.textViews["linux.command"].tap()
        app.textViews["linux.command"].typeText("printf 'LIVE_FIRST\\n'; sleep 20; printf 'LIVE_LAST\\n'")
        app.buttons["linux.run"].tap()
        let first = app.staticTexts["LIVE_FIRST"]
        XCTAssertTrue(first.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["live.stop"].exists)
        XCTAssertFalse(app.staticTexts["LIVE_LAST"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["live.stop"].tap()
        XCTAssertTrue(app.staticTexts["任务已停止"].waitForExistence(timeout: 1) || app.staticTexts["命令已取消，子进程已终止。"].waitForExistence(timeout: 10))
    }

    @MainActor
    func testMonitorSeparatesTelemetryFromIndependentAcceptance() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["tab.3"].tap()
        XCTAssertTrue(app.staticTexts["无警告答复率"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["模型复核通过率"].exists)
        app.buttons["benchmark.open"].tap()
        XCTAssertTrue(app.buttons["benchmark.start"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "不采纳模型自评")).firstMatch.exists)
        // Inspect only: starting this suite could make paid provider requests.
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["完成"].tap()
    }

    @MainActor
    func testBackgroundStopAndRelaunchRecovery() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        func openTools() {
            let tab = app.buttons["tab.1"]
            XCTAssertTrue(tab.waitForExistence(timeout: 10))
            tab.tap()
            app.swipeUp()
        app.buttons["linux.advanced"].tap()
            XCTAssertTrue(app.buttons["linux.run"].waitForExistence(timeout: 10))
        }
        func enter(_ script: String) {
            app.buttons["linux.clear"].tap()
            let editor = app.textViews["linux.command"]
            editor.tap()
            editor.typeText(script)
            app.buttons["linux.run"].tap()
        }
        func finished(containing text: String) {
            let result = app.staticTexts["linux.result"]
            let predicate = NSPredicate(format: "label CONTAINS %@", text)
            expectation(for: predicate, evaluatedWith: result)
            waitForExpectations(timeout: 20)
        }
        func pauseForStart() {
            let started = expectation(description: "Allow guest command to start")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { started.fulfill() }
            wait(for: [started], timeout: 5)
        }
        openTools()
        let file = ".ui-check-" + UUID().uuidString
        enter("printf retained > " + file + "; printf ready")
        finished(containing: "ready")
        enter("sleep 20")
        pauseForStart()
        XCUIDevice.shared.press(.home)
        app.activate()
        finished(containing: "后台")
        enter("sleep 20")
        pauseForStart()
        app.terminate()
        app.launch()
        openTools()
        // This record comes from forced termination, not an automatic retry.
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["意外中断"].firstMatch.waitForExistence(timeout: 10))
        app.swipeDown()
        enter("cat " + file + "; rm " + file)
        finished(containing: "retained")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    @MainActor
    func testProviderPresetsAndModelDiscoveryControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["tab.4"].tap()
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "神枢连接")).firstMatch.tap()
        let provider = app.buttons["api.provider"]
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        provider.tap()
        let gemini = app.buttons["Google Gemini"]
        XCTAssertTrue(gemini.waitForExistence(timeout: 5))
        gemini.tap()
        XCTAssertEqual(app.textFields["api.base"].value as? String, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertTrue(app.staticTexts["Gemini 原生"].exists)
        let models = app.buttons["api.models"]
        XCTAssertTrue(models.exists)
        XCTAssertFalse(models.isEnabled) // No credential entered; no real call is sent.
        provider.tap()
        app.buttons["阿里云百炼 / 通义千问"].tap()
        XCTAssertEqual(app.textFields["api.base"].value as? String, "HTTPS 接口地址")
        XCTAssertFalse(models.isEnabled)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCuratedMemoryCreateCorrectPersistAndDelete() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        func openMemory() {
            app.buttons["tab.4"].tap()
            let button = app.buttons["memory.open"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            XCTAssertTrue(app.buttons["memory.add"].waitForExistence(timeout: 10))
        }
        let label = "记忆验收" + UUID().uuidString.prefix(8)
        func save(_ value: String) {
            app.buttons["memory.add"].tap()
            let field = app.textFields["memory.label"]
            XCTAssertTrue(field.waitForExistence(timeout: 5))
            field.tap()
            field.typeText(label)
            let editor = app.textViews["memory.text"]
            editor.tap()
            editor.typeText(value)
            app.buttons["memory.save"].tap()
            XCTAssertTrue(app.buttons["memory.add"].waitForExistence(timeout: 5))
        }
        openMemory()
        save("请用英文")
        save("请用中文")
        XCTAssertFalse(app.staticTexts["请用英文"].exists)
        app.terminate()
        app.launch()
        openMemory()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.textViews["memory.text"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textViews["memory.text"].value as? String, "请用中文")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["memory.delete"].tap()
        XCTAssertTrue(app.buttons["memory.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch.exists)
    }

    @MainActor
    func testSkillsCreateEditRestoreAndDelete() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        func openSkills() {
            app.buttons["tab.4"].tap()
            let button = app.buttons["skills.open"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            XCTAssertTrue(app.buttons["skills.add"].waitForExistence(timeout: 5))
        }
        let name = "技能验收" + UUID().uuidString.prefix(8)
        func openEditor() {
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5))
            row.tap()
            XCTAssertTrue(app.textFields["skills.name"].waitForExistence(timeout: 5))
        }
        openSkills()
        app.buttons["skills.add"].tap()
        app.textFields["skills.name"].tap()
        app.textFields["skills.name"].typeText(name)
        let conditions = app.textViews["skills.conditions"].exists ? app.textViews["skills.conditions"] : app.textFields["skills.conditions"]
        conditions.tap(); conditions.typeText("需要核对加法时")
        app.textViews["skills.steps"].tap(); app.textViews["skills.steps"].typeText("用计算工具计算3+4")
        let verification = app.textViews["skills.verification"].exists ? app.textViews["skills.verification"] : app.textFields["skills.verification"]
        verification.tap(); verification.typeText("结果应为7")
        app.buttons["skills.save"].tap()
        XCTAssertTrue(app.buttons["skills.add"].waitForExistence(timeout: 5))
        app.terminate(); app.launch(); openSkills(); openEditor()
        XCTAssertEqual(app.textViews["skills.steps"].value as? String, "用计算工具计算3+4")
        let check = app.textViews["skills.verification"].exists ? app.textViews["skills.verification"] : app.textFields["skills.verification"]
        check.tap(); check.typeText("；核对最终输出")
        app.buttons["skills.save"].tap()
        XCTAssertTrue(app.buttons["skills.add"].waitForExistence(timeout: 5))
        openEditor()
        app.swipeUp()
        let restore = app.buttons["skills.restore.1"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        restore.tap()
        XCTAssertTrue(app.buttons["skills.add"].waitForExistence(timeout: 5))
        openEditor()
        let restored = app.textViews["skills.verification"].exists ? app.textViews["skills.verification"] : app.textFields["skills.verification"]
        XCTAssertEqual(restored.value as? String, "结果应为7")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.lifetime = .keepAlways; add(screenshot)
        app.swipeUp()
        app.buttons["skills.delete"].tap()
        XCTAssertTrue(app.buttons["skills.add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", name)).firstMatch.exists)
    }

}
