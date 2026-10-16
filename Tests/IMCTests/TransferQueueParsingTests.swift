import Testing
@testable import IMC

struct TransferQueueParsingTests {
    @Test func parsesKnownStageWithPercentage() throws {
        let progress = try #require(TransferQueue.parseProgress(" - ExtractingPackage (15%)"))
        #expect(progress.stage == "ExtractingPackage")
        #expect(progress.fraction == 0.15)
    }

    @Test func keepsUnknownStageName() throws {
        let progress = try #require(TransferQueue.parseProgress("FutureStage (100%)"))
        #expect(progress.stage == "FutureStage")
        #expect(progress.fraction == 1)
    }

    /// Il testo dipende dalla lingua, la copertura delle fasi no.
    @Test func labelsKnownStagesOnly() {
        #expect(TransferQueue.stageLabel(for: "ExtractingPackage") != "ExtractingPackage")
        #expect(TransferQueue.stageLabel(for: "FutureStage") == "FutureStage")
    }

    @Test func ignoresLinesWithoutProgress() {
        #expect(TransferQueue.parseProgress("Copying 'App.ipa' to device... DONE.") == nil)
    }

    @Test func humanizesSignatureFailure() {
        let message = TransferQueue.humanize("ERROR: Install failed. Got error \"ApplicationVerificationFailed\"")
        #expect(message == TransferQueue.Failure.invalidSignature.message)
    }

    @Test func passesThroughUnknownErrors() {
        #expect(TransferQueue.humanize("qualcosa di inatteso") == "qualcosa di inatteso")
    }
}
