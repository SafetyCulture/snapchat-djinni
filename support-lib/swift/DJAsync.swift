import Dispatch

// The async wrappers of --swift-async-wrap call these functions. A blocking C++ call that runs is not stopped.

/// Runs `call` on `queue` and returns its value. The executor of the caller does not block.
public func djinniRun<T>(_ queue: DispatchQueue, _ call: @escaping @Sendable () -> T) async -> sending T {
    let box = await withCheckedContinuation { (continuation: CheckedContinuation<UncheckedSendable<T>, Never>) in
        // SAFETY: the queue makes the value and moves it to the continuation once; it keeps no reference.
        queue.async { continuation.resume(returning: UncheckedSendable(call())) }
    }
    return box.value
}

/// Runs a blocking C++ call on `queue`. A task that is already cancelled when the function starts throws
/// `CancellationError` and does not call C++.
public func djinniCall<T>(_ queue: DispatchQueue, _ call: @escaping @Sendable () throws -> T) async throws -> sending T {
    try Task.checkCancellation()
    // SAFETY: the value of the call moves to the caller once; the queue keeps no reference.
    return try await djinniRun(queue) { Result { UncheckedSendable(try call()) } }.get().value
}

/// Runs a C++ call that returns a future on `queue`, then waits for the value of the future. A cancelled task stops
/// waiting and throws `CancellationError`.
public func djinniCallFuture<T>(_ queue: DispatchQueue, _ call: @escaping @Sendable () throws -> DJFuture<T>) async throws -> sending T {
    // SAFETY: the future is thread-safe through its lock.
    let future = UncheckedSendable(try await djinniCall(queue, call))
    return try await future.value.value
}
