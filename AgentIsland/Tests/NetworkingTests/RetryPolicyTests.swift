import Testing
import Foundation
@testable import AgentIsland

@Suite("RetryPolicy Tests")
struct RetryPolicyTests {

    @Test("execute succeeds on first attempt")
    func executeSucceedsOnFirstAttempt() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2.0)
        var callCount = 0

        let result = try await policy.execute {
            callCount += 1
            return "success"
        }

        #expect(result == "success")
        #expect(callCount == 1)
    }

    @Test("execute retries on retryable error and succeeds")
    func executeRetriesOnRetryableError() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2.0)
        var callCount = 0

        let result: String = try await policy.execute {
            callCount += 1
            if callCount < 3 {
                throw MCPError.connectionFailed("refused")
            }
            return "recovered"
        }

        #expect(result == "recovered")
        #expect(callCount == 3)
    }

    @Test("execute throws after max attempts exhausted")
    func executeThrowsAfterMaxAttempts() async {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2.0)
        var callCount = 0

        do {
            let _: String = try await policy.execute {
                callCount += 1
                throw MCPError.timeout
            }
            Issue.record("Should have thrown")
        } catch let error as MCPError {
            #expect(error == .timeout)
            #expect(callCount == 3)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("execute throws immediately on non-retryable error")
    func executeThrowsImmediatelyOnNonRetryableError() async {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, multiplier: 2.0)
        var callCount = 0

        do {
            let _: String = try await policy.execute {
                callCount += 1
                throw MCPError.rpcError(code: -1, message: "bad")
            }
            Issue.record("Should have thrown")
        } catch let error as MCPError {
            #expect(error == .rpcError(code: -1, message: "bad"))
            #expect(callCount == 1)
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("delay increases exponentially")
    func delayIncreasesExponentially() {
        let policy = RetryPolicy.standard

        #expect(policy.delayForAttempt(0) == 2.0)
        #expect(policy.delayForAttempt(1) == 4.0)
        #expect(policy.delayForAttempt(2) == 8.0)
    }
}
