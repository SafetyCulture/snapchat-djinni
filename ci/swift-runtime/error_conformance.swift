public import DjinniSupportCore

// The error types of --swift-error-type hold the C++ exception as a message, and a cancellation as code -2.
// This file is part of the generated module in the --swift-cxx-free-api variant, so the generated code sees the
// conformances at compile time.
extension CruxError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }
    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}

extension SyncError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }
    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}
