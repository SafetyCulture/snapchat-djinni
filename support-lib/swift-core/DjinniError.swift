public import Foundation

// A Swift error that holds the C++ exception of a failed call, or the message alone when C++ made no exception value.
public final class DjinniError: Error, @unchecked Sendable { // SAFETY: the payload is immutable, and the C++ exception inside it is only rethrown, which is thread-safe
    public let errorMessage: String
    // Opaque here: the C++ layer boxes its own error value.
    @_spi(DjinniCxx) public let payload: AnyObject?

    public init(_ msg: String) {
        self.errorMessage = msg
        self.payload = nil
    }

    @_spi(DjinniCxx) public init(_ message: String, payload: AnyObject?) {
        self.errorMessage = message
        self.payload = payload
    }
}

// Logs and `String(describing:)` show the message of the C++ exception, not only the type name
extension DjinniError: CustomStringConvertible, LocalizedError {
    public var description: String { return "DjinniError: \(errorMessage)" }
    public var errorDescription: String? { return errorMessage }
}

/// The error type of `--swift-error-type` conforms to this protocol. Every method that Swift calls into C++ throws the
/// error type. The application decides how the error type holds each failure:
/// - `init(cppException:)`: C++ threw, rejected a future, or dropped a promise. `DjinniError.errorMessage` is the message
///   of the C++ exception.
/// - `init(cancellation:)`: the task was cancelled before the C++ call, or while it waited for a C++ future.
public protocol CppExceptionConvertible: Error {
    init(cppException error: DjinniError)
    init(cancellation: CancellationError)
}

// An error of a C++ call becomes the error type: an error of an outcome stays as it is.
func djinniTypedError<E: CppExceptionConvertible>(_ error: any Error) -> E {
    switch error {
    case let typed as E: return typed
    case let cancellation as CancellationError: return E(cancellation: cancellation)
    case let cpp as DjinniError: return E(cppException: cpp)
    default: return E(cppException: DjinniError(String(describing: error)))
    }
}

/// Runs a C++ call on the thread of the caller and throws its errors as `E`.
public func djinniTyped<T, E: CppExceptionConvertible>(_ type: E.Type, _ call: () throws -> T) throws(E) -> T {
    do {
        return try call()
    } catch {
        let typed: E = djinniTypedError(error)
        throw typed
    }
}

// Carries a value across a concurrency boundary when the caller guarantees that the use is safe.
public struct UncheckedSendable<Value>: @unchecked Sendable { // SAFETY: the caller of the initialiser guarantees that `value` is used in one place at a time
    public let value: Value
    public init(_ value: Value) { self.value = value }
}
