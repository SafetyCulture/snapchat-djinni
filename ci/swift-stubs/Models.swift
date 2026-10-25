// The stub of the extern module that holds the Swift type of test-suite/djinni/vendor/third-party/swift_models_error.yaml.
public struct CruxError: Error, Hashable, Sendable {
    public let message: String
    public let code: Int32

    public init(message: String, code: Int32) {
        self.message = message
        self.code = code
    }
}
