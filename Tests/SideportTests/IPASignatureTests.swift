import Foundation
import Testing
@testable import Sideport

struct IPASignatureTests {
    private func profile(
        getTaskAllow: Bool = false,
        provisionsAllDevices: Bool? = nil,
        devices: [String]? = nil
    ) -> [String: Any] {
        var plist: [String: Any] = [
            "Name": "Team Provisioning Profile: com.example.app",
            "TeamName": "Example S.p.A.",
            "TeamIdentifier": ["AB12CD34EF"],
            "Entitlements": ["get-task-allow": getTaskAllow],
        ]
        if let provisionsAllDevices { plist["ProvisionsAllDevices"] = provisionsAllDevices }
        if let devices { plist["ProvisionedDevices"] = devices }
        return plist
    }

    @Test func readsDevelopmentProfile() {
        var signature = IPASignature()
        signature.apply(profile: profile(getTaskAllow: true, devices: ["0001", "0002"]))

        #expect(signature.kind == .development)
        #expect(signature.teamLabel == "Example S.p.A. (AB12CD34EF)")
        #expect(signature.profileName == "Team Provisioning Profile: com.example.app")
        #expect(signature.provisionedDeviceCount == 2)
    }

    @Test func distinguishesDistributionProfiles() {
        var adHoc = IPASignature()
        adHoc.apply(profile: profile(devices: ["0001"]))
        #expect(adHoc.kind == .adHoc)

        var enterprise = IPASignature()
        enterprise.apply(profile: profile(provisionsAllDevices: true))
        #expect(enterprise.kind == .enterprise)

        var store = IPASignature()
        store.apply(profile: profile())
        #expect(store.kind == .distribution)
        #expect(store.provisionedDeviceCount == nil)
    }

    @Test func purchaseMetadataWinsOverTheProfile() {
        var signature = IPASignature()
        signature.apply(profile: profile(getTaskAllow: true))
        signature.apply(storeMetadata: [
            "artistName": "Example Publisher",
            "apple-id": "someone@example.com",
            "userName": "ignored@example.com",
        ])

        #expect(signature.kind == .appStore)
        #expect(signature.seller == "Example Publisher")
        #expect(signature.appleID == "someone@example.com")
        // I dati del profilo restano: l'archivio li contiene comunque.
        #expect(signature.teamName == "Example S.p.A.")
    }

    /// Certificato autofirmato con CN "Apple Development: Mario Rossi (AB12CD34EF)".
    private var certificate: Data {
        Data(base64Encoded:
        "MIICJzCCAZCgAwIBAgIUBL92ZRFZFi9NABlmHRfJBMfvxlkwDQYJKoZIhvcNAQELBQAwNjE0MDIGA1UEAwwrQXBwbGUg" +
        "RGV2ZWxvcG1lbnQ6IE1hcmlvIFJvc3NpIChBQjEyQ0QzNEVGKTAeFw0yNjEwMjYxNDM0MjhaFw0zNjEwMjMxNDM0Mjha" +
        "MDYxNDAyBgNVBAMMK0FwcGxlIERldmVsb3BtZW50OiBNYXJpbyBSb3NzaSAoQUIxMkNEMzRFRikwgZ8wDQYJKoZIhvcN" +
        "AQEBBQADgY0AMIGJAoGBAPCkkG1lMuQZfGkY62wu4g5hl67MRZ4pYW/EaYrXIsDAxMG46hmSXhQI5Hl4YpI82bB/DfS/" +
        "GuCfkRuXuK7zjIXUA8Hj9nBEst3jtxQYbXjRHLiz6XK+10+3XaB5WAo7IW6NzA/bHJ/zaXUokpm+sweFWylIg1KySmfv" +
        "xS+fQpsnAgMBAAGjMjAwMB0GA1UdDgQWBBTcHKF0lW0pfp5AFMuPQqiH7LZMzzAPBgNVHRMBAf8EBTADAQH/MA0GCSqG" +
        "SIb3DQEBCwUAA4GBAOUmRXzjCTkG6ggU5y0JLg57IN4sznKlT660hZxkoRvEEGzvoTOfEZkrBPwNcfp+jOsSfK7RFKbC" +
        "pxxhu+Q4k72rnLsh57BOy1ASvKk9VsTx0uxV7da0NWV54QPe/Nc0RxgSHxzGVxRrCocrq/0cfSCl0gs3w8oPjgEijpIH" +
        "2ZgU"
        )!
    }

    /// Un profilo di squadra elenca i certificati di tutti: senza leggere il
    /// binario non si sa chi ha firmato, quindi non si tira a indovinare.
    @Test func namesTheCertificateOnlyWhenTheProfileAdmitsOne() {
        var alone = IPASignature()
        alone.apply(profile: ["DeveloperCertificates": [certificate]])
        #expect(alone.certificateCount == 1)
        #expect(alone.certificate == "Apple Development: Mario Rossi (AB12CD34EF)")
        #expect(alone.signerLabel == "Mario Rossi (AB12CD34EF)")

        var shared = IPASignature()
        shared.apply(profile: [
            "TeamName": "Example S.p.A.",
            "DeveloperCertificates": [certificate, certificate],
        ])
        #expect(shared.certificateCount == 2)
        #expect(shared.certificate == nil)
        #expect(shared.signerLabel == "Example S.p.A.")
    }

    @Test func signerLabelDropsTheCertificatePrefix() {
        var signature = IPASignature()
        signature.certificate = "Apple Development: Mario Rossi (9LNABE2FAA)"
        #expect(signature.signerLabel == "Mario Rossi (9LNABE2FAA)")

        signature.certificate = "iPhone Distribution: Example spa"
        #expect(signature.signerLabel == "Example spa")

        // Senza certificato resta il team, e per le copie dello Store il venditore.
        signature.certificate = nil
        signature.teamName = "Example S.p.A."
        #expect(signature.signerLabel == "Example S.p.A.")

        signature.teamName = nil
        signature.seller = "Example Publisher"
        #expect(signature.signerLabel == "Example Publisher")
    }

    @Test func teamLabelDropsTheMissingHalf() {
        var signature = IPASignature()
        signature.teamName = "Example S.p.A."
        #expect(signature.teamLabel == "Example S.p.A.")

        signature.teamName = nil
        signature.teamIdentifier = "AB12CD34EF"
        #expect(signature.teamLabel == "AB12CD34EF")

        signature.teamIdentifier = nil
        #expect(signature.teamLabel == nil)
    }

    @Test func expiryIsReadFromTheProfileDate() {
        var signature = IPASignature()
        signature.expirationDate = Date(timeIntervalSinceNow: -60)
        #expect(signature.isExpired)

        signature.expirationDate = Date(timeIntervalSinceNow: 60)
        #expect(!signature.isExpired)

        signature.expirationDate = nil
        #expect(!signature.isExpired)
    }

    /// Il plist viene ritagliato da un contenitore CMS, quindi ha dati binari
    /// prima e dopo: qui si simulano con l'intestazione DER e una firma finta.
    @Test func carvesThePlistOutOfTheSignedContainer() throws {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Name</key><string>Profilo</string>
        <key>TeamName</key><string>Example S.p.A.</string>
        <key>Entitlements</key><dict><key>get-task-allow</key><true/></dict>
        </dict></plist>
        """
        var data = Data([0x30, 0x82, 0x0d, 0x61, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7])
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0xff, 0xfe, 0x80, 0x53, 0x1d, 0x10]))

        let parsed = try #require(IPASignature.profile(inProvisioning: data))
        #expect(parsed.string("Name") == "Profilo")
        #expect(IPASignature.kind(ofProfile: parsed) == .development)
    }

    @Test func rejectsAContainerWithoutAPlist() {
        #expect(IPASignature.profile(inProvisioning: Data([0x30, 0x82, 0x00, 0xff])) == nil)
    }
}
