import Testing
@testable import IMC

struct TransferQueueParsingTests {
    @Test func parsesKnownStageWithPercentage() throws {
        let progress = try #require(TransferQueue.parseProgress(" - ExtractingPackage (15%)"))
        #expect(progress.stage == "Estrazione pacchetto")
        #expect(progress.fraction == 0.15)
    }

    @Test func keepsUnknownStageName() throws {
        let progress = try #require(TransferQueue.parseProgress("FutureStage (100%)"))
        #expect(progress.stage == "FutureStage")
        #expect(progress.fraction == 1)
    }

    @Test func ignoresLinesWithoutProgress() {
        #expect(TransferQueue.parseProgress("Copying 'App.ipa' to device... DONE.") == nil)
    }

    @Test func humanizesSignatureFailure() {
        let message = TransferQueue.humanize("ERROR: Install failed. Got error \"ApplicationVerificationFailed\"")
        #expect(message.hasPrefix("Firma non valida"))
    }

    @Test func passesThroughUnknownErrors() {
        #expect(TransferQueue.humanize("qualcosa di inatteso") == "qualcosa di inatteso")
    }
}
