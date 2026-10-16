import Foundation
import Testing
@testable import IMC

struct SupportTypesTests {
    @Test func drainsLinesOnBothTerminators() {
        var buffer = "a\rb\r\nc"
        let lines = OutputCollector.drainLines(from: &buffer)

        #expect(lines == ["a", "b"])
        #expect(buffer == "c")
    }

    @Test func promptWatcherReportsEachPromptOnce() {
        let watcher = PromptWatcher()

        #expect(watcher.consume("Enter pass") == [])
        #expect(watcher.consume("word: ") == [.needsPassword])
        #expect(watcher.consume("Enter password: ") == [])
        #expect(watcher.consume("Enter 2FA code: ") == [.needsAuthCode])
    }

    @Test func setMembershipSubscriptInsertsAndRemoves() {
        var selection: Set<String> = []
        selection[contains: "a"] = true
        #expect(selection == ["a"])
        selection[contains: "a"] = false
        #expect(selection.isEmpty)
    }

    @Test func installedAppVersionLabel() {
        let app = InstalledApp(plist: [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleShortVersionString": "1.2",
            "CFBundleVersion": "45",
            "ApplicationType": "System",
        ])
        #expect(app.versionLabel == "1.2 (45)")
        #expect(app.name == "com.example.app")
        #expect(!app.isRemovable)
    }

    @Test func suggestedFileNameStripsPathSeparators() throws {
        let data = Data(#"{"id":1,"bundleID":"com.example","name":"A/B: C","version":"1.0"}"#.utf8)
        let app = try JSONDecoder().decode(StoreApp.self, from: data)
        #expect(app.suggestedFileName == "A-B- C 1.0.ipa")
    }
}
