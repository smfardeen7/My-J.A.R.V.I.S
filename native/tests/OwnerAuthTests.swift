import Foundation
import LocalAuthentication

private final class TestAuthenticationContext: OwnerAuthenticationContext {
    var localizedFallbackTitle: String? = "Use Password"
    var touchIDAuthenticationAllowableReuseDuration: TimeInterval = 300
    var available = true
    var checkedPolicies: [LAPolicy] = []
    var evaluatedPolicies: [LAPolicy] = []
    var reasons: [String] = []
    var invalidationCount = 0
    var reply: ((Bool, Error?) -> Void)?

    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool {
        checkedPolicies.append(policy)
        return available
    }

    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void) {
        evaluatedPolicies.append(policy)
        reasons.append(localizedReason)
        self.reply = reply
    }

    func invalidate() { invalidationCount += 1 }
}

@main
enum OwnerAuthTests {
    static func main() {
        var failures: [String] = []
        var count = 0
        func expect(_ condition: Bool, _ label: String) {
            count += 1
            if !condition { failures.append(label) }
        }
        func drainMainQueue() {
            var drained = false
            DispatchQueue.main.async { drained = true }
            let deadline = Date().addingTimeInterval(1)
            while !drained && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
        }
        func successful(_ result: Result<Void, Error>) -> Bool {
            if case .success = result { return true }
            return false
        }
        func failure(_ result: Result<Void, Error>, is expected: OwnerAuthenticationError) -> Bool {
            if case .failure(let error) = result { return (error as? OwnerAuthenticationError) == expected }
            return false
        }

        // No real LAContext is created: every request receives one controlled test context.
        var contexts: [TestAuthenticationContext] = []
        let authenticator = OwnerAuthenticator(contextFactory: {
            let context = TestAuthenticationContext()
            contexts.append(context)
            return context
        })
        var results: [Result<Void, Error>] = []
        authenticator.confirm("Open Safari") { results.append($0) }
        let first = contexts[0]
        expect(results.isEmpty, "A request cannot approve before biometric success")
        expect(first.localizedFallbackTitle == "", "No password fallback is offered")
        expect(first.touchIDAuthenticationAllowableReuseDuration == 0, "Previous Touch ID approval cannot be reused")
        expect(first.checkedPolicies == [.deviceOwnerAuthenticationWithBiometrics], "Availability check requires biometrics")
        expect(first.evaluatedPolicies == [.deviceOwnerAuthenticationWithBiometrics], "Evaluation requires biometrics")
        expect(first.reasons == ["Open Safari"], "Native action reason is passed to authentication")
        first.reply?(true, nil)
        drainMainQueue()
        expect(results.count == 1 && successful(results[0]), "Fresh successful authentication approves once")
        expect(first.invalidationCount == 1, "Successful context is invalidated immediately")
        first.reply?(true, nil)
        drainMainQueue()
        expect(results.count == 1, "Repeated callback cannot reuse a completed grant")

        authenticator.confirm("Set volume") { results.append($0) }
        expect(contexts.count == 2 && contexts[1] !== first, "Each action creates a fresh context")
        expect(results.count == 1, "Second action cannot reuse first action's success")
        let second = contexts[1]
        second.reply?(false, NSError(domain: LAErrorDomain, code: LAError.authenticationFailed.rawValue))
        drainMainQueue()
        expect(results.count == 2 && failure(results[1], is: .notConfirmed), "Failed authentication never approves")
        expect(second.invalidationCount == 1, "Failed context is invalidated")

        var canceledCallbackCount = 0
        authenticator.confirm("Canceled action") { _ in canceledCallbackCount += 1 }
        let canceled = contexts[2]
        authenticator.cancel()
        expect(canceled.invalidationCount == 1, "Cancel invalidates pending authentication")
        canceled.reply?(true, nil)
        drainMainQueue()
        expect(canceledCallbackCount == 0, "Delayed success after cancel cannot approve")
        canceled.reply?(false, nil)
        drainMainQueue()
        expect(canceledCallbackCount == 0, "Delayed failure after cancel cannot alter a later state")

        var replacedCallbackCount = 0
        var replacementResults: [Result<Void, Error>] = []
        authenticator.confirm("Old action") { _ in replacedCallbackCount += 1 }
        let replaced = contexts[3]
        authenticator.confirm("Replacement action") { replacementResults.append($0) }
        let replacement = contexts[4]
        expect(replaced.invalidationCount == 1, "Replacement invalidates the older context")
        replaced.reply?(true, nil)
        drainMainQueue()
        expect(replacedCallbackCount == 0 && replacementResults.isEmpty, "Old success cannot approve a replacement action")
        replacement.reply?(true, nil)
        drainMainQueue()
        expect(replacementResults.count == 1 && successful(replacementResults[0]), "Replacement requires and receives its own approval")

        // A callback may already be queued on main when the user cancels.
        var queuedCallbackCount = 0
        authenticator.confirm("Queued result") { _ in queuedCallbackCount += 1 }
        let queued = contexts[5]
        queued.reply?(true, nil)
        authenticator.cancel()
        drainMainQueue()
        expect(queuedCallbackCount == 0, "Cancel wins over a success already queued for delivery")

        let unavailableContext = TestAuthenticationContext()
        unavailableContext.available = false
        let unavailable = OwnerAuthenticator(contextFactory: { unavailableContext })
        var unavailableResults: [Result<Void, Error>] = []
        unavailable.confirm("Cannot run") { unavailableResults.append($0) }
        expect(unavailableResults.count == 1 && failure(unavailableResults[0], is: .biometryUnavailable), "Unavailable biometrics fails closed")
        expect(unavailableContext.evaluatedPolicies.isEmpty, "No evaluation or fallback when Touch ID is unavailable")
        expect(unavailableContext.invalidationCount == 1, "Unavailable context is invalidated")

        // Completion may synchronously begin a new request without granting it the old result.
        var nestedCompletions = 0
        authenticator.confirm("Outer action") { _ in
            authenticator.confirm("Inner action") { _ in nestedCompletions += 1 }
        }
        let outer = contexts[6]
        outer.reply?(true, nil)
        drainMainQueue()
        expect(contexts.count == 8 && nestedCompletions == 0, "Reentrant action still waits for fresh authentication")
        contexts[7].reply?(true, nil)
        drainMainQueue()
        expect(nestedCompletions == 1, "Reentrant action completes with its own authentication")

        if !failures.isEmpty {
            failures.forEach { print("FAIL: \($0)") }
            exit(1)
        }
        print("\(count) owner authentication checks passed; no Touch ID prompts or Mac actions.")
    }
}
