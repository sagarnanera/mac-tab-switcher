import Testing
@testable import TabCore

@Suite("ThumbKeyDerivation")
struct ThumbKeyDerivationTests {

    @Test("keys are 128-bit hex")
    func keyShape() {
        let key = ThumbKeyDerivation.weak(bundleID: "com.apple.finder", title: "Downloads")
        #expect(key.count == 32)
        #expect(key.allSatisfy { $0.isHexDigit })
    }

    @Test("same inputs give the same key across calls")
    func deterministic() {
        let a = ThumbKeyDerivation.weak(bundleID: "com.apple.finder", title: "Downloads")
        let b = ThumbKeyDerivation.weak(bundleID: "com.apple.finder", title: "Downloads")
        #expect(a == b)
    }

    @Test("the same title in two apps gives different keys")
    func namespacedByApp() {
        let finder = ThumbKeyDerivation.weak(bundleID: "com.apple.finder", title: "Downloads")
        let chrome = ThumbKeyDerivation.weak(bundleID: "com.google.Chrome", title: "Downloads")
        #expect(finder != chrome)
    }

    @Test("strong and weak keys never collide for the same string")
    func domainSeparation() {
        #expect(
            ThumbKeyDerivation.strong(bundleID: "a", documentURL: "x")
                != ThumbKeyDerivation.weak(bundleID: "a", title: "x")
        )
    }

    @Test("pid-derived keys are distinct per pid")
    func pidFallback() {
        #expect(
            ThumbKeyDerivation.weak(pid: 100, title: "t") != ThumbKeyDerivation.weak(pid: 101, title: "t")
        )
    }
}
