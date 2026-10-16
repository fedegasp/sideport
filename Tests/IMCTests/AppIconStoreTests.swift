import Testing
@testable import IMC

struct AppIconStoreTests {
    @Test func readsOnlySuccessfulLines() {
        let output = """
        OK com.example.a
        ERR com.example.b servizio-3
        ERR ../evil nome-non-valido
        OK com.example.c
        """
        #expect(AppIconStore.fetchedBundleIdentifiers(in: output) == ["com.example.a", "com.example.c"])
    }

    @Test func cacheKeyChangesWithVersionAndIsFileSafe() {
        let old = InstalledApp(plist: [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1/2",
        ])
        let new = InstalledApp(plist: [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleShortVersionString": "1.1",
            "CFBundleVersion": "3",
        ])

        #expect(AppIconStore.cacheKey(for: old) == "com.example.app_1.0_1-2")
        #expect(AppIconStore.cacheKey(for: old) != AppIconStore.cacheKey(for: new))
    }
}
