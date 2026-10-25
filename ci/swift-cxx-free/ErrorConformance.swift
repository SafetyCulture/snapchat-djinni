public import DjinniSupportCore

// The application decides how the error record of --swift-error-type holds a C++ exception.
extension SwiftCxxFreeFailure: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }

    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}
