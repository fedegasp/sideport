import Foundation
import Network
import Testing
@testable import Sideport

struct DeviceTransportTests {
    @Test func passesTheNetworkFlagOnlyForNetworkDevices() {
        #expect(Device.Transport.usb.toolArguments == [])
        #expect(Device.Transport.network.toolArguments == ["-n"])
    }

    @Test func keepsTheConnectionOrderOfTheTwoLists() {
        let merged = DeviceMonitor.merge(usb: ["a"], network: ["b", "c"])

        #expect(merged == [
            .init(udid: "a", transport: .usb),
            .init(udid: "b", transport: .network),
            .init(udid: "c", transport: .network),
        ])
    }

    @Test func prefersTheCableWhenADeviceIsOnBoth() {
        let merged = DeviceMonitor.merge(usb: ["a"], network: ["a"])

        #expect(merged == [.init(udid: "a", transport: .usb)])
    }

    @Test func explainsAMuxErrorOnlyForNetworkDevices() {
        let raw = "ERROR: Could not connect to lockdownd: Mux error (-8)"

        guard case .error(let overNetwork) = DeviceMonitor.interpretFailure(raw, transport: .network),
              case .error(let overCable) = DeviceMonitor.interpretFailure(raw, transport: .usb) else {
            Issue.record("Un mux error resta uno stato di errore.")
            return
        }
        #expect(overNetwork != raw)
        #expect(overCable == raw)
    }

    @Test func keepsReadingPairingAndPasscodeFailures() {
        #expect(DeviceMonitor.interpretFailure("Please accept the trust dialog", transport: .network) == .untrusted)
        #expect(DeviceMonitor.interpretFailure("device is passcode protected", transport: .network) == .locked)
    }

    @Test func recognizesOnlyThePolicyDenialAmongDNSErrors() {
        #expect(LocalNetworkAccess.isPolicyDenial(.dns(DNSServiceErrorType(kDNSServiceErr_PolicyDenied))))
        #expect(!LocalNetworkAccess.isPolicyDenial(.dns(DNSServiceErrorType(kDNSServiceErr_NoSuchRecord))))
        #expect(!LocalNetworkAccess.isPolicyDenial(.posix(.ECONNREFUSED)))
    }

    @Test func reportsNetworkDevicesInTheInterface() {
        var device = Device(udid: "a", transport: .network)
        #expect(device.isOnNetwork)
        #expect(device.transportSymbolName == "wifi")

        device.transport = .usb
        #expect(!device.isOnNetwork)
    }
}
