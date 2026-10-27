import Testing
@testable import Sideport

struct VersionCompareTests {
    @Test(arguments: [
        ("1.9", "1.10"),
        ("2.0", "2.0.1"),
        ("16.4", "17.0"),
    ])
    func lowerVersions(lhs: String, rhs: String) {
        #expect(VersionCompare.isLower(lhs, than: rhs))
        #expect(VersionCompare.isHigher(rhs, than: lhs))
    }

    @Test func equalVersionsAreNeitherLowerNorHigher() {
        #expect(!VersionCompare.isLower("3.1", than: "3.1"))
        #expect(!VersionCompare.isHigher("3.1", than: "3.1"))
    }
}
