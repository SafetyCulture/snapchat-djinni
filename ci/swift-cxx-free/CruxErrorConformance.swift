public import DjinniSupportCore

// The conformance of the Crux error record, compiled into the generated module of the Crux check.
extension CruxError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }

    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}
