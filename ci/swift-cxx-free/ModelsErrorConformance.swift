public import DjinniSupportCore
public import Models

// The conformance of the extern error record of --swift-error-type, compiled into the generated module.
extension CruxError: @retroactive CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }

    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}
