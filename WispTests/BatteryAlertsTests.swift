import XCTest

@testable import WispCore

final class BatteryAlertsTests: XCTestCase {
    private func state(_ percent: Int, plugged: Bool, charging: Bool? = nil) -> BatteryState {
        BatteryState(percent: percent, isPluggedIn: plugged, isCharging: charging ?? plugged)
    }

    func testFirstReadingIsSilent() {
        XCTAssertEqual(BatteryAlerts.events(from: nil, to: state(50, plugged: true)), [])
    }

    func testPlugAndUnplug() {
        XCTAssertEqual(
            BatteryAlerts.events(from: state(50, plugged: false), to: state(50, plugged: true)), [.pluggedIn])
        XCTAssertEqual(
            BatteryAlerts.events(from: state(50, plugged: true), to: state(50, plugged: false)), [.unplugged])
    }

    func testFullOnceWhenReaching100OnPower() {
        XCTAssertEqual(BatteryAlerts.events(from: state(99, plugged: true), to: state(100, plugged: true)), [.full])
        XCTAssertEqual(BatteryAlerts.events(from: state(100, plugged: true), to: state(100, plugged: true)), [])
    }

    func testLowThresholdsOnlyWhenCrossingDownOnBattery() {
        XCTAssertEqual(BatteryAlerts.events(from: state(21, plugged: false), to: state(20, plugged: false)), [.low(20)])
        XCTAssertEqual(BatteryAlerts.events(from: state(11, plugged: false), to: state(10, plugged: false)), [.low(10)])
        XCTAssertEqual(BatteryAlerts.events(from: state(20, plugged: false), to: state(19, plugged: false)), [])
        XCTAssertEqual(BatteryAlerts.events(from: state(21, plugged: true), to: state(20, plugged: true)), [])
    }
}
