import Foundation
import Testing
@testable import RetextCore

@Suite struct IdentityTests {
    @Test func repositoryFallsBackWhenMissingOrMalformed() {
        #expect(Identity.repository("someone/retext-fork") == "someone/retext-fork")
        #expect(Identity.repository(nil) == Identity.repository)
        #expect(Identity.repository("") == Identity.repository)
        #expect(Identity.repository("evil.com/x?y") == Identity.repository)
        #expect(Identity.repository("a/b/c") == Identity.repository)
    }

    @Test func urlsUseTheRepository() {
        #expect(Identity.latestReleaseURL(repository: "someone/fork").absoluteString == "https://api.github.com/repos/someone/fork/releases/latest")
        #expect(Identity.pageURL(repository: "someone/fork").absoluteString == "https://github.com/someone/fork")
    }
}

/// A fake Keychain: (service, account) -> key.
private final class FakeKeychain {
    var items: [String: String] = [:]
    var saveWorks = true
    var corruptOnSave = false
    var deletes: [String] = []
    var reads: [String] = []
    /// Runs once on the first legacy read: another writer (Settings → Save) while the read waits on a prompt.
    var onLegacyRead: (() -> Void)?

    func read(_ service: String, _ account: String) -> String? {
        reads.append(service)
        if service == "old", let hook = onLegacyRead { onLegacyRead = nil; hook() }
        return items["\(service)|\(account)"]
    }
    /// Add-only, like the real migration save: an existing item is never overwritten.
    func save(_ key: String, _ service: String, _ account: String) -> Bool {
        guard saveWorks, items["\(service)|\(account)"] == nil else { return false }
        items["\(service)|\(account)"] = corruptOnSave ? key + "x" : key
        return true
    }
    func delete(_ service: String, _ account: String) {
        deletes.append(service)
        items["\(service)|\(account)"] = nil
    }

    func key(service: String = "new", legacy: String = "old") -> String? {
        KeychainMigration.key(account: "acct", service: service, legacyService: legacy, read: read, save: save, delete: delete)
    }
}

@Suite struct KeychainMigrationTests {
    @Test func currentKeySkipsTheLegacyLookup() {
        let k = FakeKeychain()
        k.items = ["new|acct": "k1", "old|acct": "k0"]
        #expect(k.key() == "k1")
        #expect(k.reads == ["new"])
        #expect(k.deletes.isEmpty)
    }

    @Test func legacyKeyMovesAndIsDeletedAfterReadBack() {
        let k = FakeKeychain()
        k.items = ["old|acct": "k0"]
        #expect(k.key() == "k0")
        #expect(k.items == ["new|acct": "k0"])
        #expect(k.deletes == ["old"])
    }

    @Test func failedSaveKeepsTheLegacyItem() {
        let k = FakeKeychain()
        k.items = ["old|acct": "k0"]
        k.saveWorks = false
        #expect(k.key() == "k0")
        #expect(k.items == ["old|acct": "k0"])
        #expect(k.deletes.isEmpty)
        #expect(k.reads == ["new", "old", "new"])
    }

    @Test func keySavedDuringTheMoveIsNotOverwritten() {
        let k = FakeKeychain()
        k.items = ["old|acct": "k0"]
        k.onLegacyRead = { k.items["new|acct"] = "k1" }
        #expect(k.key() == "k1")
        #expect(k.items == ["new|acct": "k1", "old|acct": "k0"])
        #expect(k.deletes.isEmpty)
    }

    @Test func mismatchedReadBackKeepsTheLegacyItem() {
        let k = FakeKeychain()
        k.items = ["old|acct": "k0"]
        k.corruptOnSave = true
        #expect(k.key() == "k0")
        #expect(k.items["old|acct"] == "k0")
        #expect(k.deletes.isEmpty)
    }

    @Test func nothingSavedReturnsNil() {
        let k = FakeKeychain()
        #expect(k.key() == nil)
        #expect(k.deletes.isEmpty)
    }

    @Test func sameServiceNeverDeletes() {
        let k = FakeKeychain()
        #expect(k.key(service: "old", legacy: "old") == nil)
        k.items = ["old|acct": "k0"]
        #expect(k.key(service: "old", legacy: "old") == "k0")
        #expect(k.deletes.isEmpty)
    }

    @Test func defaultLegacyServiceIsTheOldBundleID() {
        #expect(Identity.legacyKeychainService != Identity.bundleID)
    }
}
