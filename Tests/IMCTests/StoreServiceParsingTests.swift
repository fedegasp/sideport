import Testing
@testable import IMC

struct StoreServiceParsingTests {
    @Test func parsesAppsInBothKeyConventions() {
        let output = """
        {"level":"info","message":"searching"}
        {"apps":[{"id":1,"bundleID":"com.example.a","name":"A","version":"1.0","price":0},{"trackId":2,"bundleId":"com.example.b","trackName":"B","price":1.99},{"unexpected":true}]}
        """
        let apps = StoreService.parseApps(from: output)

        #expect(apps.map(\.trackId) == [1, 2])
        #expect(apps.map(\.bundleId) == ["com.example.a", "com.example.b"])
        #expect(apps.map(\.trackName) == ["A", "B"])
        #expect(apps[0].isFree)
        #expect(!apps[1].isFree)
    }

    @Test func returnsNoAppsWithoutAppsKey() {
        #expect(StoreService.parseApps(from: #"{"level":"error"}"#).isEmpty)
    }

    @Test func parsesNestedAccount() {
        let account = StoreService.parseAccount(from: #"{"account":{"email":"utente@example.com","name":"Utente"}}"#)
        #expect(account == StoreAccount(email: "utente@example.com", name: "Utente"))
    }

    @Test func parsesRootLevelAccount() {
        let account = StoreService.parseAccount(from: #"{"email":"utente@example.com"}"#)
        #expect(account == StoreAccount(email: "utente@example.com", name: nil))
    }

    @Test func parsesAndClampsPercentages() {
        #expect(StoreService.parsePercentage("Downloading 42%") == 0.42)
        #expect(StoreService.parsePercentage("150 %") == 1)
        #expect(StoreService.parsePercentage("nessun avanzamento") == nil)
    }

    @Test func humanizesReportedErrors() {
        let message = StoreService.errorMessage(stdout: #"{"error":"license is required"}"#, stderr: "")
        #expect(message.hasPrefix("Licenza mancante"))
    }

    @Test func fallsBackToStderrThenGenericMessage() {
        #expect(StoreService.errorMessage(stdout: "", stderr: "  boom \n") == "boom")
        #expect(StoreService.errorMessage(stdout: "", stderr: "") == "ipatool e' terminato con un errore.")
    }

    @Test func reportsOutputPath() {
        let output = """
        {"level":"info"}
        {"output":"/tmp/App 1.0.ipa","success":true}
        """
        #expect(StoreService.parseString(key: "output", from: output) == "/tmp/App 1.0.ipa")
    }
}
