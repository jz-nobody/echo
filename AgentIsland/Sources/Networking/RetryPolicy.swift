import Foundation

struct RetryPolicy: Sendable {
    let maxAttempts: Int
    let baseDelay: TimeInterval
    let multiplier: Double

    static let standard = RetryPolicy(maxAttempts: 3, baseDelay: 2.0, multiplier: 2.0)

    func execute<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        var lastError: (any Error)?
        for attempt in 0..<maxAttempts {
            do {
                return try await operation()
            } catch let error as MCPError where error.isRetryable {
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delay = baseDelay * pow(multiplier, Double(attempt))
                    try await Task.sleep(for: .seconds(delay))
                }
            } catch {
                throw error
            }
        }
        throw lastError ?? MCPError.connectionFailed("All retry attempts exhausted")
    }

    func delayForAttempt(_ attempt: Int) -> TimeInterval {
        baseDelay * pow(multiplier, Double(attempt))
    }
}
