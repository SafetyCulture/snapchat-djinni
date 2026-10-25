import CruxBindings
import DjinniSupportCore

// A client of the generated Crux module without C++ interoperability. It imports no C++ module and names no C++ type.

final class MutationObserver: MutationProcessorObserverInterface, @unchecked Sendable { // SAFETY: the test keeps no state
    func onMutationProcessed(_ mutation: MutationProcessObject) throws -> Void {}
}

// The synchronous registration form of --swift-sync-method.
func register(_ api: CruxAPI, _ observer: MutationProcessorObserverInterface) throws(CruxError) -> String {
    return try api.addMutationProcessorObserverNow(observer)
}

// An async wrapper method with the error type of the app.
func login(_ api: CruxAPI, _ session: UserSession) async throws(CruxError) {
    try await api.login(session)
}

// No default case: the enum is @frozen, so the switch stays exhaustive across the module boundary.
func environmentName(_ environment: APIEnvironment) -> String {
    switch environment {
    case .production: return "production"
    case .sandpit: return "sandpit"
    case .development: return "development"
    }
}

// The error type reaches the client through CppExceptionConvertible.
func convert(_ error: DjinniError) -> CruxError {
    return CruxError(cppException: error)
}
