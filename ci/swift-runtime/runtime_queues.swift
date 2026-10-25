import Dispatch

// The queue of --swift-async-queue in the run of runtime.djinni. The generated module evaluates it.
enum RuntimeQueues {
    static let blocking = DispatchQueue(label: "djinni.runtime.blocking", attributes: .concurrent)
}
