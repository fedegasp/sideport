import Testing
@testable import Sideport

struct PlistParsingTests {
    private let plist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict><key>DeviceName</key><string>iPhone di prova</string><key>Count</key><integer>3</integer></dict></plist>
    """

    @Test func extractsDocumentSurroundedByLogLines() throws {
        let output = "Connessione al dispositivo...\n\(plist)\nFatto."
        let data = try #require(PlistParsing.extractPlistData(from: output))
        let dictionary = try PlistParsing.dictionary(from: data)

        #expect(dictionary.string("DeviceName") == "iPhone di prova")
        #expect(dictionary.int("Count") == 3)
        #expect(dictionary.string("Count") == "3")
    }

    @Test func returnsNilWithoutPlist() {
        #expect(PlistParsing.extractPlistData(from: "ERROR: No device found.") == nil)
    }

    @Test func wrapsSingleDictionaryInArray() throws {
        let data = try #require(PlistParsing.extractPlistData(from: plist))
        #expect(try PlistParsing.dictionaryArray(from: data).count == 1)
    }
}
