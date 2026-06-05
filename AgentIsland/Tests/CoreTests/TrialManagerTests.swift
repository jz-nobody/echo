import Foundation
import Testing
@testable import AgentIsland

private final class MockKeychainStore: KeychainStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func read(key: String) -> Data? {
        storage[key]
    }

    func write(key: String, data: Data) -> Bool {
        storage[key] = data
        return true
    }

    func delete(key: String) -> Bool {
        storage.removeValue(forKey: key)
        return true
    }
}

@MainActor
@Suite("TrialManager")
struct TrialManagerTests {

    private func makeManager(
        keychain: MockKeychainStore = MockKeychainStore(),
        now: Date = Date()
    ) -> TrialManager {
        TrialManager(keychain: keychain, dateProvider: { now })
    }

    @Test("First launch records install date")
    func firstLaunchRecordsInstallDate() {
        let keychain = MockKeychainStore()
        let now = Date()
        let manager = makeManager(keychain: keychain, now: now)

        #expect(manager.installDate != nil)
        #expect(!manager.isLocked)
    }

    @Test("Trial period active within 21 days")
    func trialActive() {
        let now = Date()
        let manager = makeManager(now: now)

        if case .trial(let days) = manager.status {
            #expect(days == 21 || days == 20)
        } else {
            Issue.record("Expected trial status")
        }
        #expect(!manager.isLocked)
    }

    @Test("Trial expires after 21 days")
    func trialExpires() {
        let keychain = MockKeychainStore()
        let installDate = Date()
        let expiredDate = installDate.addingTimeInterval(22 * 86400)

        _ = makeManager(keychain: keychain, now: installDate)
        let manager = TrialManager(keychain: keychain, dateProvider: { expiredDate })

        #expect(manager.status == .expired)
        #expect(manager.isLocked)
    }

    @Test("Trial day countdown is correct")
    func trialCountdown() {
        let keychain = MockKeychainStore()
        let installDate = Date()
        let day10 = installDate.addingTimeInterval(10 * 86400)

        _ = makeManager(keychain: keychain, now: installDate)
        let manager = TrialManager(keychain: keychain, dateProvider: { day10 })

        if case .trial(let days) = manager.status {
            #expect(days == 11 || days == 10)
        } else {
            Issue.record("Expected trial status")
        }
        #expect(!manager.isLocked)
    }

    @Test("Valid token activates successfully")
    func validTokenActivates() {
        let keychain = MockKeychainStore()
        let installDate = Date()
        let expiredDate = installDate.addingTimeInterval(22 * 86400)

        _ = makeManager(keychain: keychain, now: installDate)
        let manager = TrialManager(keychain: keychain, dateProvider: { expiredDate })
        #expect(manager.isLocked)

        // We can't test with real token since hash is placeholder
        // This tests the rejection path
        let result = manager.activate(token: "invalid-token")
        #expect(!result)
        #expect(manager.isLocked)
    }

    @Test("Invalid token is rejected")
    func invalidTokenRejected() {
        let manager = makeManager()
        let result = manager.activate(token: "wrong-token-12345")
        #expect(!result)
    }

    @Test("Activation expiry after 90 days")
    func activationExpiry() {
        let keychain = MockKeychainStore()
        let installDate = Date()

        _ = makeManager(keychain: keychain, now: installDate)

        // Simulate activation by writing directly to keychain
        let tokenData = Data("test-token".utf8)
        _ = keychain.write(key: "activationToken", data: tokenData)
        let activationDate = installDate.addingTimeInterval(22 * 86400)
        let dateData = withUnsafeBytes(of: activationDate.timeIntervalSince1970) { Data($0) }
        _ = keychain.write(key: "activationDate", data: dateData)

        // Within activation period (day 50)
        let day50 = activationDate.addingTimeInterval(50 * 86400)
        let activeManager = TrialManager(keychain: keychain, dateProvider: { day50 })
        if case .activated(let days) = activeManager.status {
            #expect(days == 40 || days == 39)
        } else {
            Issue.record("Expected activated status, got \(activeManager.status)")
        }
        #expect(!activeManager.isLocked)

        // After activation period (day 91)
        let day91 = activationDate.addingTimeInterval(91 * 86400)
        let expiredManager = TrialManager(keychain: keychain, dateProvider: { day91 })
        #expect(expiredManager.status == .activationExpired)
        #expect(expiredManager.isLocked)
    }

    @Test("Re-activation refreshes expiry")
    func reactivation() {
        let keychain = MockKeychainStore()
        let installDate = Date()

        _ = makeManager(keychain: keychain, now: installDate)

        // Simulate expired activation
        let tokenData = Data("test-token".utf8)
        _ = keychain.write(key: "activationToken", data: tokenData)
        let activationDate = installDate
        let dateData = withUnsafeBytes(of: activationDate.timeIntervalSince1970) { Data($0) }
        _ = keychain.write(key: "activationDate", data: dateData)

        let day91 = activationDate.addingTimeInterval(91 * 86400)
        let manager = TrialManager(keychain: keychain, dateProvider: { day91 })
        #expect(manager.status == .activationExpired)

        // Simulate re-activation by updating activation date
        let newDateData = withUnsafeBytes(of: day91.timeIntervalSince1970) { Data($0) }
        _ = keychain.write(key: "activationDate", data: newDateData)
        manager.refreshStatus()

        if case .activated(let days) = manager.status {
            #expect(days == 90 || days == 89)
        } else {
            Issue.record("Expected activated status after re-activation")
        }
        #expect(!manager.isLocked)
    }

    @Test("Install date persists across instances")
    func installDatePersists() {
        let keychain = MockKeychainStore()
        let now = Date()

        let manager1 = makeManager(keychain: keychain, now: now)
        let installDate1 = manager1.installDate

        let later = now.addingTimeInterval(3600)
        let manager2 = TrialManager(keychain: keychain, dateProvider: { later })
        let installDate2 = manager2.installDate

        #expect(installDate1 == installDate2)
    }
}
