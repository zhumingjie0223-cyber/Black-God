import XCTest
@testable import BlackGod

@MainActor
final class NexusHapticsTests: XCTestCase {
    private let hapticKey = "blackgod.haptic.enabled"
    private let taskKey = "blackgod.haptic.taskComplete"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: hapticKey)
        UserDefaults.standard.removeObject(forKey: taskKey)
    }

    func testDefaultsEnableBothHaptics() {
        let state = AppState()
        XCTAssertTrue(state.hapticEnabled)
        XCTAssertTrue(state.taskCompleteHapticEnabled)
    }

    func testPersistsTaskCompleteToggle() {
        let first = AppState()
        first.taskCompleteHapticEnabled = false
        XCTAssertEqual(UserDefaults.standard.object(forKey: taskKey) as? Bool, false)

        let second = AppState()
        XCTAssertFalse(second.taskCompleteHapticEnabled)

        second.taskCompleteHapticEnabled = true
        let third = AppState()
        XCTAssertTrue(third.taskCompleteHapticEnabled)
    }

    func testPersistsLightHapticToggle() {
        let first = AppState()
        first.hapticEnabled = false
        let second = AppState()
        XCTAssertFalse(second.hapticEnabled)
    }
}
