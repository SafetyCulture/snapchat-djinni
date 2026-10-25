public import Dispatch

// The async wrappers of --swift-async-wrap call these functions. A blocking C++ call that runs is not stopped.

/// The queue of one blocking C++ call when the generator has no `--swift-async-queue`. libdispatch runs a serial queue
/// on its overcommit threads, so a blocked call does not use a thread of the global queues. Those threads stay free for
/// the delivery of Swift futures. Each call has its own queue, so calls to one object can run at the same time.
public func djinniCallQueue() -> DispatchQueue {
    DispatchQueue(label: "djinni.call", qos: .userInitiated)
}

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
public func djinniCall<T>(_ queue: DispatchQueue = djinniCallQueue(), _ call: @escaping @Sendable () throws -> T) async throws -> sending T {
    try Task.checkCancellation()
    // SAFETY: the value of the call moves to the caller once; the queue keeps no reference.
    return try await djinniRun(queue) { Result { UncheckedSendable(try call()) } }.get().value
}

/// Runs a C++ call that returns a future on `queue`, then waits for the value of the future. A cancelled task stops
/// waiting and throws `CancellationError`.
public func djinniCallFuture<T>(_ queue: DispatchQueue = djinniCallQueue(), _ call: @escaping @Sendable () throws -> DJFuture<T>) async throws -> sending T {
    // SAFETY: the future is thread-safe through its lock.
    let future = UncheckedSendable(try await djinniCall(queue, call))
    return try await future.value.value
}

/// `djinniCall` for `--swift-error-type`: a cancellation and a C++ exception become `E`.
public func djinniCallTyped<T, E: CppExceptionConvertible>(_ type: E.Type, _ queue: DispatchQueue = djinniCallQueue(), _ call: @escaping @Sendable () throws -> T) async throws(E) -> sending T {
    do {
        return try await djinniCall(queue, call)
    } catch {
        let typed: E = djinniTypedError(error)
        throw typed
    }
}

/// `djinniCallFuture` for `--swift-error-type`: a cancellation, a C++ exception, a rejected future and a dropped promise
/// become `E`.
public func djinniCallFutureTyped<T, E: CppExceptionConvertible>(_ type: E.Type, _ queue: DispatchQueue = djinniCallQueue(), _ call: @escaping @Sendable () throws -> DJFuture<T>) async throws(E) -> sending T {
    do {
        return try await djinniCallFuture(queue, call)
    } catch {
        let typed: E = djinniTypedError(error)
        throw typed
    }
}
