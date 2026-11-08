import XCTest

@testable import WispCore

final class AccessoryBatteryTests: XCTestCase {
    /// Recorded with `system_profiler SPBluetoothDataType -json` on macOS 27.2 (BCM_4387), with
    /// names, addresses and firmware versions replaced. Nothing was connected at the time, so
    /// `device_not_connected` is as recorded and the `device_connected` entries copy its shape
    /// plus the `device_batteryLevel*` keys the parser already reads for AirPods.
    private let recorded = Data(
        """
        {"SPBluetoothDataType":[{
          "controller_properties":{
            "controller_address":"00:00:00:00:00:00","controller_chipset":"BCM_4387",
            "controller_discoverable":"attrib_off","controller_firmwareVersion":"1.0",
            "controller_productID":"0x4A04","controller_state":"attrib_on",
            "controller_supportedServices":"0x1390039 < HFP AVRCP A2DP HID LEA AACP GATT SerialPort SCO >",
            "controller_transport":"PCIe","controller_vendorID":"0x004C (Apple)"},
          "device_connected":[
            {"Magic Mouse":{"device_address":"00:00:00:00:00:11","device_minorType":"Mouse",
              "device_productID":"0x0269","device_vendorID":"0x004C","device_batteryLevelMain":"18%"}},
            {"Magic Keyboard":{"device_address":"00:00:00:00:00:12","device_minorType":"Keyboard",
              "device_productID":"0x029C","device_vendorID":"0x004C","device_batteryLevelMain":"74%"}},
            {"Magic Trackpad":{"device_address":"00:00:00:00:00:13","device_minorType":"Mouse",
              "device_productID":"0x0265","device_vendorID":"0x004C","device_batteryLevelMain":"55%"}},
            {"Office Mouse":{"device_address":"00:00:00:00:00:14","device_minorType":"Mouse",
              "device_productID":"0xB034","device_vendorID":"0x046D"}},
            {"Headphones":{"device_address":"00:00:00:00:00:15","device_minorType":"Headphones",
              "device_batteryLevelLeft":"90%","device_batteryLevelRight":"88%"}}
          ],
          "device_not_connected":[
            {"Device 1":{"device_address":"00:00:00:00:00:01","device_rssi":"-60"}},
            {"Device 2":{"device_address":"00:00:00:00:00:02"}},
            {"Device 3":{"device_address":"00:00:00:00:00:03","device_minorType":"Mouse"}},
            {"Device 4":{"device_address":"00:00:00:00:00:04","device_firmwareVersion":"1.0",
              "device_minorType":"Mouse","device_productID":"0xB034","device_vendorID":"0x046D"}},
            {"Device 5":{"device_address":"00:00:00:00:00:05","device_firmwareVersion":"1.0",
              "device_minorType":"Keyboard","device_productID":"0xB367","device_vendorID":"0x046D"}},
            {"Device 6":{"device_address":"00:00:00:00:00:06","device_firmwareVersion":"1.0",
              "device_minorType":"Headset","device_productID":"0x022C","device_vendorID":"0x05AC"}}
          ]
        }]}
        """.utf8)

    private func device(_ address: String, _ level: Int?) -> BluetoothDevice {
        BluetoothDevice(
            name: "Mouse \(address)", address: address, kind: "Mouse",
            battery: level.map { [.main: $0] } ?? [:])
    }

    // MARK: Accessories

    func testListsConnectedAccessoriesWithALevelByName() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: recorded))
        let accessories = BluetoothReport.accessories(devices)
        XCTAssertEqual(accessories.map(\.name), ["Magic Keyboard", "Magic Mouse", "Magic Trackpad"])
        XCTAssertEqual(accessories.map { $0.battery[.main] }, [74, 18, 55])
    }

    func testIgnoresDisconnectedDevices() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: recorded))
        XCTAssertFalse(devices.contains { $0.name.hasPrefix("Device ") })
    }

    func testATrackpadThatCallsItselfAMouseKeepsItsSymbol() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: recorded))
        let trackpad = try XCTUnwrap(devices.first { $0.name == "Magic Trackpad" })
        XCTAssertEqual(trackpad.symbol, "rectangle.and.hand.point.up.left.fill")
        XCTAssertTrue(trackpad.isAccessory)
    }

    func testHeadphonesAndSpeakersAreNotAccessories() {
        let buds = BluetoothDevice(name: "Buds", address: "a", kind: "Headphones", battery: [.main: 10])
        let speaker = BluetoothDevice(name: "Box", address: "b", kind: "Speaker", battery: [.main: 10])
        XCTAssertEqual(BluetoothReport.accessories([buds, speaker]), [])
    }

    func testLowestPicksTheWeakestFirst() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: recorded))
        let accessories = BluetoothReport.accessories(devices)
        XCTAssertEqual(
            BluetoothReport.lowest(accessories, limit: 2).map(\.name), ["Magic Mouse", "Magic Trackpad"])
        XCTAssertEqual(BluetoothReport.lowest(accessories, limit: 10).count, 3)
        XCTAssertEqual(BluetoothReport.lowest(accessories, limit: 0), [])
        XCTAssertEqual(BluetoothReport.lowest(accessories, limit: -1), [])
    }

    func testLowestBreaksTiesByName() {
        let zed = BluetoothDevice(name: "Zed", address: "z", kind: "Mouse", battery: [.main: 40])
        let able = BluetoothDevice(name: "Able", address: "a", kind: "Keyboard", battery: [.main: 40])
        let none = BluetoothDevice(name: "Aardvark", address: "n", kind: "Mouse", battery: [:])
        XCTAssertEqual(BluetoothReport.lowest([none, zed, able], limit: 3).map(\.name), ["Able", "Zed", "Aardvark"])
    }

    // MARK: Alerts

    func testWarnsOnceAtTwentyPercent() {
        var alerts = AccessoryBatteryAlerts()
        XCTAssertEqual(alerts.check([device("m", 40)]), [])
        XCTAssertEqual(alerts.check([device("m", 21)]), [])
        XCTAssertEqual(alerts.check([device("m", 20)]).map(\.address), ["m"])
        XCTAssertEqual(alerts.check([device("m", 19)]), [])
        XCTAssertEqual(alerts.check([device("m", 5)]), [])
    }

    func testWarnsAtTheLevelItIsGiven() {
        var alerts = AccessoryBatteryAlerts()
        XCTAssertEqual(alerts.check([device("m", 31)], lowLevel: 30), [])
        XCTAssertEqual(alerts.check([device("m", 30)], lowLevel: 30).map(\.address), ["m"])

        var lower = AccessoryBatteryAlerts()
        XCTAssertEqual(lower.check([device("m", 11)], lowLevel: 10), [])
        XCTAssertEqual(lower.check([device("m", 10)], lowLevel: 10).map(\.address), ["m"])
    }

    func testTheDefaultLevelIsTwentyPercent() {
        XCTAssertEqual(AccessoryBatteryAlerts.defaultLowLevel, 20)
    }

    func testAFirstReadingThatIsAlreadyLowWarns() {
        var alerts = AccessoryBatteryAlerts()
        XCTAssertEqual(alerts.check([device("m", 12)]).map(\.address), ["m"])
    }

    func testRearmsOnlyAfterChargingPastTheRearmLevel() {
        var alerts = AccessoryBatteryAlerts()
        _ = alerts.check([device("m", 20)])
        // A small bounce isn't a charge.
        _ = alerts.check([device("m", 35)])
        XCTAssertEqual(alerts.check([device("m", 20)]), [])
        _ = alerts.check([device("m", AccessoryBatteryAlerts.rearmLevel)])
        XCTAssertEqual(alerts.check([device("m", 18)]), [])
        _ = alerts.check([device("m", AccessoryBatteryAlerts.rearmLevel + 1)])
        XCTAssertEqual(alerts.check([device("m", 18)]).map(\.address), ["m"])
    }

    func testEachDeviceHasItsOwnWarning() {
        var alerts = AccessoryBatteryAlerts()
        XCTAssertEqual(alerts.check([device("a", 15), device("b", 60)]).map(\.address), ["a"])
        XCTAssertEqual(alerts.check([device("a", 14), device("b", 20)]).map(\.address), ["b"])
    }

    func testADeviceThatReconnectsLowDoesNotWarnAgain() {
        var alerts = AccessoryBatteryAlerts()
        _ = alerts.check([device("m", 15)])
        XCTAssertEqual(alerts.check([]), [])
        XCTAssertEqual(alerts.check([device("m", 15)]), [])
    }

    func testDevicesWithoutALevelAreIgnored() {
        var alerts = AccessoryBatteryAlerts()
        XCTAssertEqual(alerts.check([device("m", nil)]), [])
        XCTAssertEqual(alerts.warned, [])
    }

    func testWorksOnTheRecordedReport() throws {
        var alerts = AccessoryBatteryAlerts()
        let devices = try XCTUnwrap(BluetoothReport.connected(from: recorded))
        XCTAssertEqual(alerts.check(BluetoothReport.accessories(devices)).map(\.name), ["Magic Mouse"])
    }
}
