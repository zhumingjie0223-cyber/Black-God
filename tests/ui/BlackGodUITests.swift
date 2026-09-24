import XCTest

final class BlackGodUITests: XCTestCase {
    @MainActor
    func testRedesignedMainPanelsAndCreationState() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.actions"].waitForExistence(timeout: 8))
        capture(app, name: "新版-对话")
        XCTAssertFalse(app.buttons["tab.1"].exists)
        XCTAssertFalse(app.buttons["execution.start"].exists)
        app.buttons["tab.2"].tap()
        let generate = app.buttons["media.generate"]
        reveal(generate, in: app)
        XCTAssertTrue(generate.exists)
        XCTAssertFalse(generate.isEnabled)
        let field = app.descendants(matching: .any)["media.prompt"]
        field.tap(); field.typeText("A quiet forest cabin")
        let copy = app.buttons["media.copy"]
        reveal(copy, in: app); copy.tap()
        XCTAssertTrue(app.buttons["已复制描述"].waitForExistence(timeout: 3))
        app.swipeDown()
        app.swipeDown()
        capture(app, name: "新版-创作")
        // End editing before changing the phone's bottom navigation.
        _ = app.buttons["tab.3"].waitForExistence(timeout: 3)
        if !app.buttons["tab.3"].exists { app.swipeDown() }
        app.buttons["tab.3"].tap()
        XCTAssertTrue(app.staticTexts["monitor.sample-count"].waitForExistence(timeout: 5))
        capture(app, name: "新版-监测")
        app.buttons["tab.4"].tap()
        XCTAssertTrue(app.buttons["api.open"].waitForExistence(timeout: 5))
        capture(app, name: "新版-我的")
        app.buttons["api.open"].tap()
        XCTAssertTrue(app.navigationBars["模型连接"].waitForExistence(timeout: 5))
        capture(app, name: "新版-模型连接")
        app.buttons["完成"].tap()
        app.buttons["tab.0"].tap()
        XCTAssertTrue(app.buttons["chat.connection"].isHittable)
    }

    @MainActor
    func testLargeTextKeepsPrimaryControlsReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityL"]
        app.launch()
        XCTAssertTrue(app.buttons["chat.connection"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["chat.connection"].isHittable)
        XCTAssertTrue(app.buttons["chat.send"].exists)
        capture(app, name: "新版-辅助大字体对话")
        app.buttons["tab.3"].tap()
        let benchmark = app.buttons["benchmark.open"]
        reveal(benchmark, in: app, upSwipes: 12)
        benchmark.tap()
        XCTAssertTrue(app.buttons["benchmark.start"].waitForExistence(timeout: 5))
        app.buttons["完成"].tap()
        app.buttons["tab.4"].tap()
        let connection = app.buttons["api.open"]
        reveal(connection, in: app); connection.tap()
        let login = app.buttons["oauth.login"]
        reveal(login, in: app)
        XCTAssertTrue(login.isHittable)
        capture(app, name: "新版-辅助大字体连接")
        app.buttons["完成"].tap()
    }

    @MainActor
    func testTabletSidebarAndLandscapeComposer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        guard app.frame.width >= 700 else { throw XCTSkip("此用例用于原生 iPad 布局") }
        for i in [0, 2, 3, 4] { XCTAssertTrue(app.buttons["tab.\(i)"].isHittable) }
        capture(app, name: "新版-iPad竖屏")
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["tab.0"].tap()
        XCTAssertGreaterThan(app.frame.width, app.frame.height)
        XCTAssertTrue(app.buttons["chat.connection"].isHittable)
        XCTAssertTrue(app.descendants(matching: .any)["chat.input"].isHittable)
        capture(app, name: "新版-iPad横屏")
        XCTAssertFalse(app.buttons["tab.1"].exists)
        app.buttons["tab.3"].tap()
        XCTAssertTrue(app.staticTexts["monitor.sample-count"].waitForExistence(timeout: 5))
        capture(app, name: "新版-iPad监测")
        app.buttons["tab.4"].tap(); app.buttons["api.open"].tap()
        XCTAssertTrue(app.navigationBars["模型连接"].waitForExistence(timeout: 5))
        capture(app, name: "新版-iPad连接面板")
        app.buttons["完成"].tap()
    }

    @MainActor
    private func openAdvanced(in app: XCUIApplication) {
        app.buttons["tab.4"].tap()
        let advanced = app.buttons["advanced.open"]
        reveal(advanced, in: app)
        advanced.tap()
        XCTAssertTrue(app.navigationBars["高级设置"].waitForExistence(timeout: 5))
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testConversationManagementEntryIsDiscoverable() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); app.buttons["tab.0"].tap()
        let actions = app.buttons["chat.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 8))
        XCTAssertTrue(actions.isHittable)
        XCTAssertEqual(actions.label, "对话管理")
        XCTAssertTrue(app.buttons["chat.connection"].isHittable)
        actions.tap()
        XCTAssertTrue(app.buttons["清空当前对话"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "对话管理入口"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testChatComposerChipsUseJadePrompts() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.buttons["tab.0"].tap()
        XCTAssertTrue(app.buttons["chat.chip.plan"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["chat.chip.calc"].exists)
        XCTAssertTrue(app.buttons["chat.chip.shuyu"].exists)
        XCTAssertTrue(app.buttons["chat.chip.pulse"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["chat.empty"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["chat.breath"].exists)
        XCTAssertTrue(["就绪", "在场", "该练", "可续", "处理中", "开口", "刚歇", "在听", "余韵", "看着", "还在", "顿笔", "惦记", "收笔", "落定", "应声", "衔着", "跟上", "等下文", "侧耳", "让开", "挨着", "守着", "偎着", "陪着", "依着", "候着"].contains(app.staticTexts["chat.mood"].label))
        let field = app.descendants(matching: .any)["chat.input"]
        XCTAssertTrue(field.waitForExistence(timeout: 4))
        field.tap()
        XCTAssertEqual(app.staticTexts["chat.mood"].label, "看着")
        app.buttons["chat.chip.plan"].tap()
        XCTAssertEqual(app.staticTexts["chat.mood"].label, "在听")
        expectation(for: NSPredicate(format: "label == %@", "顿笔"), evaluatedWith: app.staticTexts["chat.mood"])
        // 保留同一个状态断言；额外时间只用于繁忙运行器的界面快照调度，不改变产品的 1.6 秒停笔时间。
        waitForExpectations(timeout: 10)
        app.descendants(matching: .any)["chat.title"].tap()
        expectation(for: NSPredicate(format: "label == %@", "惦记"), evaluatedWith: app.staticTexts["chat.mood"])
        waitForExpectations(timeout: 3)
        field.tap()
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let prompt = "把这件事拆成可检查的步骤："
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: prompt.count + 4))
        expectation(for: NSPredicate(format: "label == %@", "收笔"), evaluatedWith: app.staticTexts["chat.mood"])
        waitForExpectations(timeout: 6)
        let giveBack = app.buttons["chat.act"]
        XCTAssertTrue(giveBack.waitForExistence(timeout: 2))
        XCTAssertEqual(giveBack.label, "还给你")
        giveBack.tap()
        expectation(for: NSPredicate(format: "label == %@", "在听"), evaluatedWith: app.staticTexts["chat.mood"])
        waitForExpectations(timeout: 3)
        XCTAssertEqual(field.value as? String, prompt)
        XCTAssertFalse(app.buttons["chat.regenerate"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "对话快捷芯片"; shot.lifetime = .keepAlways; add(shot)
    }

    @MainActor
    func testSelfContinuityEntryPauseAndClear() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); app.buttons["tab.4"].tap()
        let entry = app.buttons["cognitive.open"]
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        entry.tap(); app.buttons["self.open"].tap()
        XCTAssertTrue(app.navigationBars["自我状态流"].waitForExistence(timeout: 5))
        let toggle = app.switches["self.enabled"]
        XCTAssertTrue(toggle.isHittable)
        let knob = toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5))
        if toggle.value as? String == "0" {
            knob.tap()
            expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: toggle)
            waitForExpectations(timeout: 3)
        }
        knob.tap()
        expectation(for: NSPredicate(format: "label == %@", "记录已暂停或不可用"), evaluatedWith: app.staticTexts["self.status"])
        waitForExpectations(timeout: 3)
        knob.tap()
        expectation(for: NSPredicate(format: "label == %@", "等待任务"), evaluatedWith: app.staticTexts["self.status"])
        waitForExpectations(timeout: 3)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "自我状态流"; shot.lifetime = .keepAlways; add(shot)
        let clear = app.buttons["self.clear"]
        for _ in 0..<4 where !clear.isHittable { app.swipeUp() }
        clear.tap(); app.buttons["清空记录"].tap()
        XCTAssertTrue(app.staticTexts["self.empty"].exists)
    }

    @MainActor
    func testCognitivePermissionsAndObservationEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); app.buttons["tab.4"].tap()
        let entry = app.buttons["cognitive.open"]
        for _ in 0..<4 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.navigationBars["神枢成长"].waitForExistence(timeout: 5))
        let grant = app.buttons["cognitive.grant"]
        for _ in 0..<4 where !grant.isHittable { app.swipeUp() }
        XCTAssertTrue(grant.isHittable)
        grant.tap()
        let granted = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "工作区授权至")).firstMatch
        // 状态文字在按钮上方；页面若已滑过，需要慢速回滚一小段（sheet 内不能整屏下拉，会关掉面板）。
        if !granted.waitForExistence(timeout: 3) {
            for _ in 0..<3 where !granted.exists { app.swipeDown(velocity: .slow) }
        }
        let afterGrant = XCTAttachment(screenshot: app.screenshot()); afterGrant.name = "授权后"; afterGrant.lifetime = .keepAlways; add(afterGrant)
        XCTAssertTrue(granted.waitForExistence(timeout: 3))
        let revoke = app.buttons["cognitive.revoke"]
        reveal(revoke, in: app)
        revoke.tap()
        let stopped = app.staticTexts["已停止"]
        reveal(stopped, in: app)
        XCTAssertTrue(stopped.exists)
        app.buttons["仅允许本地分析与候选记录"].tap()
        let photo = app.buttons["cognitive.photo"]
        for _ in 0..<4 where !photo.isHittable { app.swipeUp() }
        XCTAssertTrue(photo.isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "神枢成长与图片观察"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["完成"].tap()
    }

    @MainActor
    func testVersionAndBundledLicensePage() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch(); app.buttons["tab.4"].tap()
        let entry = app.buttons["licenses.open"]
        for _ in 0..<5 where !entry.isHittable { app.swipeUp() }
        // 版本文案随 project.yml 的版本号变化；只校验“x.y.z（build）”格式，避免每次升 build 都改测试。
        let versionText = app.staticTexts["app.version"]
        reveal(versionText, in: app)
        XCTAssertTrue(versionText.exists, "应显示版本文案")
        XCTAssertNotNil(versionText.label.range(of: #"\d+\.\d+\.\d+（\d+）"#, options: .regularExpression), "版本文案应形如 1.2.0（8），实际：\(versionText.label)")
        reveal(entry, in: app)
        XCTAssertTrue(entry.isHittable); entry.tap()
        XCTAssertTrue(app.navigationBars["开源许可"].waitForExistence(timeout: 5))
        let text = app.staticTexts["document.paragraph.0"]
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        XCTAssertTrue(text.isHittable)
        XCTAssertTrue(text.label.contains("Black God 开源许可与源码"))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Embedded runtime source and notices")).firstMatch.exists)
        app.swipeDown()
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "开源许可"; shot.lifetime = .keepAlways; add(shot)
        app.buttons["完成"].tap()
    }

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
        openAdvanced(in: app)
        reveal(app.buttons["shuyu.open"], in: app)
        app.buttons["shuyu.open"].tap()
        app.buttons["shuyu.generate"].tap()
        assertShuyuResult(in: app)
        let verified = app.staticTexts["词形与汉译反查一致"]
        reveal(verified, in: app)
        XCTAssertTrue(verified.exists)
        reveal(app.buttons["shuyu.analogy"], in: app)
        app.buttons["shuyu.analogy"].tap()
        reveal(verified, in: app)
        XCTAssertTrue(verified.waitForExistence(timeout: 5))
        reveal(app.buttons["shuyu.near"], in: app)
        app.buttons["shuyu.near"].tap()
        assertShuyuResult(in: app)
        let pulse = app.buttons["shuyu.pulse"]
        reveal(pulse, in: app)
        pulse.tap()
        assertShuyuResult(in: app)
        let trail = app.buttons["shuyu.trail"]
        reveal(trail, in: app)
        trail.tap()
        assertShuyuResult(in: app)
        let echo = app.buttons["shuyu.echo"]
        reveal(echo, in: app)
        echo.tap()
        assertShuyuResult(in: app)
        let sway = app.buttons["shuyu.sway"]
        reveal(sway, in: app)
        sway.tap()
        assertShuyuResult(in: app)
        let land = app.buttons["shuyu.land"]
        reveal(land, in: app)
        land.tap()
        assertShuyuResult(in: app)
        let stir = app.buttons["shuyu.stir"]
        reveal(stir, in: app)
        stir.tap()
        assertShuyuResult(in: app)
        let perch = app.buttons["shuyu.perch"]
        reveal(perch, in: app)
        perch.tap()
        assertShuyuResult(in: app)
        let turn = app.buttons["shuyu.turn"]
        reveal(turn, in: app)
        turn.tap()
        assertShuyuResult(in: app)
        let gaze = app.buttons["shuyu.gaze"]
        reveal(gaze, in: app)
        gaze.tap()
        assertShuyuResult(in: app)
        let incline = app.buttons["shuyu.incline"]
        reveal(incline, in: app)
        incline.tap()
        assertShuyuResult(in: app)
        let nestle = app.buttons["shuyu.nestle"]
        reveal(nestle, in: app)
        nestle.tap()
        assertShuyuResult(in: app)
        let hold = app.buttons["shuyu.hold"]
        reveal(hold, in: app)
        hold.tap()
        assertShuyuResult(in: app)
        let warm = app.buttons["shuyu.warm"]
        reveal(warm, in: app)
        warm.tap()
        assertShuyuResult(in: app)
        let rouse = app.buttons["shuyu.rouse"]
        reveal(rouse, in: app)
        rouse.tap()
        assertShuyuResult(in: app)
        let language = XCTAttachment(screenshot: app.screenshot()); language.name = "枢语语言"; language.lifetime = .keepAlways; add(language)
        app.navigationBars["枢语"].buttons["完成"].tap()
        reveal(app.buttons["storage.open"], in: app)
        app.buttons["storage.open"].tap()
        XCTAssertTrue(app.buttons["storage.budget.8"].waitForExistence(timeout: 10))
        let capacity = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "手机剩余空间")).firstMatch
        XCTAssertTrue(capacity.waitForExistence(timeout: 20))
        // LabeledContent exposes this read-only label separately from its hittable List row.
        // Verify its actual visible frame instead of requiring the text to accept taps.
        XCTAssertFalse(capacity.frame.isEmpty)
        XCTAssertTrue(app.windows.firstMatch.frame.contains(capacity.frame))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "运行空间"; shot.lifetime = .keepAlways; add(shot)
        app.navigationBars["运行空间"].buttons["完成"].tap()
        app.navigationBars["高级设置"].buttons["完成"].tap()
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
    func testAdvancedTerminalAndLiveOutputArrivesBeforeExit() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertFalse(app.buttons["tab.1"].exists)
        XCTAssertFalse(app.textViews["linux.command"].exists)
        openAdvanced(in: app)
        let entry = XCTAttachment(screenshot: app.screenshot())
        entry.name = "高级设置入口"; entry.lifetime = .keepAlways; add(entry)
        reveal(app.buttons["linux.advanced"], in: app)
        app.buttons["linux.advanced"].tap()
        XCTAssertTrue(app.buttons["linux.clear"].waitForExistence(timeout: 10))
        app.buttons["linux.clear"].tap()
        app.textViews["linux.command"].tap()
        app.textViews["linux.command"].typeText("printf 'LIVE_FIRST\\n'; sleep 20; printf 'LIVE_LAST\\n'")
        reveal(app.buttons["linux.run"], in: app)
        app.buttons["linux.run"].tap()
        let first = app.staticTexts["LIVE_FIRST"]
        XCTAssertTrue(first.waitForExistence(timeout: 30))
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
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "无警告答复率")).firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "模型自检通过率")).firstMatch.exists)
        reveal(app.buttons["benchmark.open"], in: app)
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
            openAdvanced(in: app)
            let advanced = app.buttons["linux.advanced"]
            reveal(advanced, in: app)
            advanced.tap()
            XCTAssertTrue(app.buttons["linux.run"].waitForExistence(timeout: 10))
        }
        func enter(_ script: String) {
            let back = app.buttons["linux.backToCommand"]
            if back.exists && back.isHittable { back.tap() }
            let clear = app.buttons["linux.clear"]
            reveal(clear, in: app)
            clear.tap()
            let editor = app.textViews["linux.command"]
            reveal(editor, in: app)
            editor.tap()
            editor.typeText(script)
            reveal(app.buttons["linux.run"], in: app)
            app.buttons["linux.run"].tap()
        }
        func finished(containing text: String) {
            let result = app.staticTexts["linux.result"]
            reveal(result, in: app)
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
        let executionStarted = NSPredicate(format: "label == %@", "正在执行命令")
        expectation(for: executionStarted, evaluatedWith: app.staticTexts["live.status"])
        waitForExpectations(timeout: 30)
        app.terminate()
        app.launch()
        openTools()
        // This record comes from forced termination, not an automatic retry.
        let interrupted = app.staticTexts["linux.latestStatus"]
        reveal(interrupted, in: app, upSwipes: 8)
        XCTAssertEqual(interrupted.label, "意外中断")
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
        reveal(provider, in: app)
        XCTAssertTrue(provider.waitForExistence(timeout: 10))
        provider.tap()
        let gemini = app.buttons["Google Gemini"]
        XCTAssertTrue(gemini.waitForExistence(timeout: 5))
        gemini.tap()
        let base = app.textFields["api.base"]
        reveal(base, in: app)
        XCTAssertEqual(base.value as? String, "https://generativelanguage.googleapis.com/v1beta")
        XCTAssertTrue(app.staticTexts["Gemini 原生"].exists)
        let models = app.buttons["api.models"]
        reveal(models, in: app)
        XCTAssertTrue(models.exists)
        XCTAssertFalse(models.isEnabled) // No credential entered; no real call is sent.
        reveal(provider, in: app)
        provider.tap()
        app.buttons["阿里云百炼 / 通义千问"].tap()
        reveal(base, in: app)
        XCTAssertEqual(base.value as? String, "https://")
        reveal(models, in: app)
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

extension XCTestCase {
    /// Form 只生成当前可见的行；每次操作后先滚回结果行，再检查真实结果。
    @MainActor
    func assertShuyuResult(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let result = app.staticTexts["shuyu.word"]
        reveal(result, in: app, upSwipes: 12, downSwipes: 16, file: file, line: line)
        XCTAssertTrue(result.waitForExistence(timeout: 10), "枢语结果行未出现", file: file, line: line)
        XCTAssertFalse(result.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                       "枢语结果不能为空", file: file, line: line)
    }

    /// 列表/表单页面只渲染可见区域；页面变长后需要先滑到元素处再断言，否则不是功能缺陷而是查找失败。
    /// 用短距离拖动代替整屏 swipe：整屏 swipeDown 会把以 sheet 弹出的页面直接关掉。
    @MainActor
    func reveal(_ element: XCUIElement, in app: XCUIApplication, upSwipes: Int = 6, downSwipes: Int = 8, file: StaticString = #filePath, line: UInt = #line) {
        func contentBounds() -> CGRect {
            let window = app.windows.firstMatch.frame
            var top = window.minY + 48
            var bottom = window.maxY - 16
            if app.navigationBars.firstMatch.exists { top = max(top, app.navigationBars.firstMatch.frame.maxY) }
            let keyboard = app.keyboards.firstMatch
            if keyboard.exists { bottom = min(bottom, keyboard.frame.minY) }
            let tab = app.buttons["tab.0"]
            if tab.exists && tab.isHittable && tab.frame.midY > window.midY {
                bottom = min(bottom, tab.frame.minY - 8)
            }
            return CGRect(x: window.minX, y: top, width: window.width, height: max(80, bottom - top))
        }
        func visible() -> Bool {
            guard element.exists, element.isHittable else { return false }
            let bounds = contentBounds(), frame = element.frame
            return frame.minY >= bounds.minY && frame.maxY <= bounds.maxY
        }
        if visible() { return }
        func nudge(contentUp: Bool) {
            let bounds = contentBounds()
            let container = app.scrollViews.firstMatch.exists ? app.scrollViews.firstMatch.frame : bounds
            let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            let x = max(bounds.minX + 30, min(container.midX, bounds.maxX - 30))
            let from = origin.withOffset(CGVector(dx: x, dy: bounds.minY + bounds.height * (contentUp ? 0.74 : 0.28)))
            let to = origin.withOffset(CGVector(dx: x, dy: bounds.minY + bounds.height * (contentUp ? 0.28 : 0.74)))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        for attempt in 0..<(upSwipes + downSwipes) {
            if visible() { return }
            if element.exists {
                let frame = element.frame, bounds = contentBounds()
                if frame.minY < bounds.minY { nudge(contentUp: false); continue }
                if frame.maxY > bounds.maxY { nudge(contentUp: true); continue }
            }
            nudge(contentUp: attempt < upSwipes)
        }
        XCTAssertTrue(visible(), "未能将元素完整显示在可操作区域：\(element)", file: file, line: line)
    }
}
