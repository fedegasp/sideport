import Testing
@testable import Sideport

struct InstalledAppTests {
    @Test func sumsAppAndDataSizes() {
        let app = InstalledApp(plist: [
            "CFBundleIdentifier": "com.example.app",
            "StaticDiskUsage": 25_157_632,
            "DynamicDiskUsage": 2_924_544,
        ])
        #expect(app.appDiskUsage == 25_157_632)
        #expect(app.dataDiskUsage == 2_924_544)
        #expect(app.diskUsage == 28_082_176)
    }

    @Test func usesWhicheverSizeIsAvailable() {
        let app = InstalledApp(plist: ["CFBundleIdentifier": "com.example.app", "DynamicDiskUsage": 100])
        #expect(app.diskUsage == 100)
    }

    @Test func reportsNoSizeWhenDeviceOmitsIt() {
        let app = InstalledApp(plist: ["CFBundleIdentifier": "com.example.app"])
        #expect(app.diskUsage == nil)
    }

    @Test func requestsEveryAttributeItReads() {
        for key in ["StaticDiskUsage", "DynamicDiskUsage", "CFBundleDisplayName", "ApplicationType"] {
            #expect(InstalledApp.requestedAttributes.contains(key))
        }
    }
}
