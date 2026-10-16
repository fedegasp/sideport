import Testing
@testable import IMC

struct IPAContentsTests {
    private let entries = [
        IPAEntry(path: "Payload/A.app/Info.plist", size: 10, isDirectory: false),
        IPAEntry(path: "Payload/A.app/icon.png", size: 20, isDirectory: false),
        IPAEntry(path: "Payload/A.app/Frameworks", size: 0, isDirectory: true),
        IPAEntry(path: "iTunesMetadata.plist", size: 5, isDirectory: false),
    ]

    @Test func buildsIntermediateFoldersAndSumsSizes() throws {
        let tree = IPAContents.tree(from: entries)

        #expect(tree.map(\.name) == ["Payload", "iTunesMetadata.plist"])
        let payload = try #require(tree.first)
        #expect(payload.isDirectory)
        #expect(payload.size == 30)

        let app = try #require(payload.children?.first)
        #expect(app.id == "Payload/A.app")
        #expect(app.children?.map(\.name) == ["Frameworks", "icon.png", "Info.plist"])
    }

    @Test func explicitEmptyFolderStaysADirectory() throws {
        let tree = IPAContents.tree(from: entries)
        let index = IPAContents.index(tree)
        let frameworks = try #require(index["Payload/A.app/Frameworks"])

        #expect(frameworks.isDirectory)
        #expect(frameworks.children == [])
    }

    @Test func expandsChainUpToAppBundle() {
        let tree = IPAContents.tree(from: entries)
        #expect(IPAContents.defaultExpansion(in: tree) == ["Payload", "Payload/A.app"])
    }

    @Test func indexesEveryNode() {
        let index = IPAContents.index(IPAContents.tree(from: entries))
        #expect(index.count == 6)
        #expect(index["Payload/A.app/Info.plist"]?.size == 10)
    }
}
