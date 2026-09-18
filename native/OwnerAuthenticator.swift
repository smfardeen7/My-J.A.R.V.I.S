import Foundation
import LocalAuthentication

protocol OwnerAuthenticationContext: AnyObject {
    var localizedFallbackTitle: String? { get set }
    var touchIDAuthenticationAllowableReuseDuration: TimeInterval { get set }
    func canEvaluatePolicy(_ policy: LAPolicy, error: NSErrorPointer) -> Bool
    func evaluatePolicy(_ policy: LAPolicy, localizedReason: String, reply: @escaping @Sendable (Bool, Error?) -> Void)
    func invalidate()
}

extension LAContext: OwnerAuthenticationContext {}

enum OwnerAuthenticationError: LocalizedError, Equatable {
    case biometryUnavailable, notConfirmed

    var errorDescription: String? {
        switch self {
        case .biometryUnavailable:
            return "Touch ID is required. Enable Touch ID for this Mac account, then try again. No action was performed."
        case .notConfirmed:
            return "Touch ID was not confirmed. No action was performed."
        }
    }
}

/// Fresh biometric confirmation for each operation; never reuse an unlock.
/// State is confined to the main thread; LocalAuthentication callbacks only enqueue work there.
final class OwnerAuthenticator: @unchecked Sendable {
    private let contextFactory: () -> OwnerAuthenticationContext
    private var context: OwnerAuthenticationContext?
    private var generation = UUID()

    init(contextFactory: @escaping () -> OwnerAuthenticationContext = { LAContext() }) {
        self.contextFactory = contextFactory
    }

    deinit { context?.invalidate() }

    func cancel() {
        precondition(Thread.isMainThread)
        generation = UUID()
        context?.invalidate()
        context = nil
    }

    func confirm(_ reason: String, completion: @escaping (Result<Void, Error>) -> Void) {
        precondition(Thread.isMainThread)
        cancel()
        let token = generation
        let context = contextFactory()
        context.localizedFallbackTitle = ""
        context.touchIDAuthenticationAllowableReuseDuration = 0
        self.context = context
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            self.context = nil
            context.invalidate()
            completion(.failure(OwnerAuthenticationError.biometryUnavailable))
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, _ in
            DispatchQueue.main.async {
                guard let self = self, self.generation == token, let context = self.context else { return }
                self.context = nil
                context.invalidate()
                if success { completion(.success(())) }
                else { completion(.failure(OwnerAuthenticationError.notConfirmed)) }
            }
        }
    }
}
