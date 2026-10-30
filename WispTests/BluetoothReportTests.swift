import XCTest

@testable import WispCore

final class BluetoothReportTests: XCTestCase {
    private let sample = Data(
        """
        {"SPBluetoothDataType":[{
          "controller_properties":{"controller_state":"attrib_on"},
          "device_connected":[
            {"Ayo's AirPods Pro":{"device_address":"00:00:00:00:00:01","device_minorType":"Headphones",
              "device_batteryLevelLeft":"100%","device_batteryLevelRight":"85%","device_batteryLevelCase":"40%"}},
            {"MX Master":{"device_address":"00:00:00:00:00:02","device_minorType":"Mouse",
              "device_batteryLevelMain":"62%"}},
            {"Speaker":{"device_address":"00:00:00:00:00:03","device_minorType":"Speaker"}}
          ],
          "device_not_connected":[{"Old Keyboard":{"device_address":"00:00:00:00:00:04"}}]
        }]}
        """.utf8)

    func testReadsConnectedDevicesWithTheirBatteries() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: sample))
        XCTAssertEqual(devices.map(\.name), ["Ayo's AirPods Pro", "MX Master", "Speaker"])
        XCTAssertEqual(devices[0].address, "00:00:00:00:00:01")
        XCTAssertEqual(devices[0].battery, [.left: 100, .right: 85, .case: 40])
        XCTAssertEqual(devices[1].battery, [.main: 62])
        XCTAssertEqual(devices[2].battery, [:])
    }

    func testPicksASymbolFromTheKind() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: sample))
        XCTAssertEqual(devices[0].symbol, "airpods.pro")
        XCTAssertEqual(devices[1].symbol, "computermouse.fill")
        XCTAssertEqual(devices[2].symbol, "hifispeaker.fill")
    }

    func testBudsShowTheLowerOfTheTwo() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: sample))
        XCTAssertEqual(devices[0].headline, 85)
        XCTAssertEqual(devices[1].headline, 62)
        XCTAssertNil(devices[2].headline)
    }

    func testNewlyConnectedComparesByAddress() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: sample))
        let fresh = BluetoothReport.newlyConnected(devices, previous: ["00:00:00:00:00:02"])
        XCTAssertEqual(fresh.map(\.name), ["Ayo's AirPods Pro", "Speaker"])
    }

    func testBadInputIsNil() {
        XCTAssertNil(BluetoothReport.connected(from: Data("nope".utf8)))
        XCTAssertEqual(BluetoothReport.connected(from: Data(#"{"SPBluetoothDataType":[{}]}"#.utf8)), [])
    }

    func testOnlyHeadphonesCountAsHeadphones() throws {
        let devices = try XCTUnwrap(BluetoothReport.connected(from: sample))
        XCTAssertEqual(devices.map(\.isHeadphones), [true, false, false])
    }
}
