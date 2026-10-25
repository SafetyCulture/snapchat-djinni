public import Foundation
internal import Dispatch

// A custom Future<> type thanks to Logan Shire <@LoganShireSnapchat>
public final class Cancellable: @unchecked Sendable { // SAFETY: `closure` is immutable, and the closures of this module only take a lock to cancel a subscription
    private let closure: () -> Void

    init(closure: @escaping () -> Void) {
        self.closure = closure
    }

    func cancel() {
        self.closure()
    }

    deinit {
        self.closure()
    }
}

public typealias Lock = NSLock

// A weak reference that a `@Sendable` closure can hold
private struct WeakReference<Object: AnyObject> {
    weak var object: Object?
    init(_ object: Object) { self.object = object }
}

public final class Future<Output, Failure> where Failure : Error {
    // A subscriber runs on a global queue, or before getResult returns when the future already has its result.
    // It must be `@Sendable`, and it must not take a lock that the caller of getResult holds.
    public typealias Promise = @Sendable (Result<Output, Failure>) -> Void

    // The token only needs to be unique within the scope of the Future object
    typealias Token = Int64
    private var nextTokenValue: Token = 0
    private func generateToken() -> Token {
        lock.lock()
        defer { lock.unlock() }
        nextTokenValue += 1
        return nextTokenValue
    }

    private let lock = Lock()
    private var storedResult: Result<Output, Failure>?
    private var subscriptions = [Token : Promise]()

    // The closure runs before the initialiser returns. The promise that it receives can run later, on any thread.
    public init(_ attemptToFulfill: (@escaping Promise) -> Void) {
        let weakSelf = UncheckedSendable(WeakReference(self)) // SAFETY: the reference is weak, and the future guards its state with its lock
        attemptToFulfill { result in
            guard let self = weakSelf.value.object else { return }

            self.lock.lock()

            // A future has one result. A later result is dropped, and the first one stays.
            if self.storedResult != nil {
                self.lock.unlock()
                return
            }

            // Otherwise, make a copy of the completion handlers and clear them out,
            // and then store the result and unlock:
            let copiedSubscriptions = self.subscriptions
            self.subscriptions = [:]
            self.storedResult = result
            self.lock.unlock()

            // Run the completion handlers in parallel after unlocking:
            nonisolated(unsafe) let delivered = result // SAFETY: the result is stored once and not changed, and the subscribers are @Sendable. A result of a reference type reaches every subscriber at the same time, so it must be safe to read from many threads
            for subscription in copiedSubscriptions.values {
                DispatchQueue.global(qos: .default).async {
                    subscription(delivered)
                }
            }
        }
    }

    // A cancelled task stops waiting and throws CancellationError. The future is not cancelled.
    public var value: Output {
        get async throws {
            let token = generateToken()
            let waiter = Waiter<Output, Failure>()
            // The future is thread-safe through its lock, so the closures can hold it across domains
            let box = UncheckedSendable(self) // SAFETY: the future guards its state with its lock
            return try await withTaskCancellationHandler {
                return try await withCheckedThrowingContinuation { continuation in
                    if waiter.install(continuation) {
                        box.value.subscribe(token: token) { result in
                            waiter.fulfill(result)
                        }
                        // onCancel can run before the subscription exists.
                        if waiter.isCancelled {
                            box.value.cancel(token: token)
                        }
                    }
                }
            } onCancel: {
                // Cancel the waiter first. Then a body that is between install and subscribe sees isCancelled.
                waiter.cancel()
                box.value.cancel(token: token)
            }
        }
    }

    public func getResult(subscription: @escaping Promise) -> Cancellable {
        let token = generateToken()
        self.subscribe(token: token, subscription: subscription)
        return Cancellable {
            self.cancel(token: token)
        }
    }

    // MARK: Private

    private func subscribe(token: Token, subscription: @escaping Promise) {
        self.lock.lock()
        if let result = self.storedResult {
            self.lock.unlock()
            subscription(result)
            return
        }

        self.subscriptions[token] = subscription
        self.lock.unlock()
    }

    private func cancel(token: Token) {
        self.lock.lock()
        self.subscriptions[token] = nil
        self.lock.unlock()
    }
}

// A future crosses concurrency domains only when its value is Sendable
extension Future: @unchecked Sendable where Output: Sendable {} // SAFETY: the future guards its state with its lock, and its value is Sendable

// Resumes the continuation of `Future.value` exactly once, with a result or with CancellationError.
private final class Waiter<Output, Failure: Error>: @unchecked Sendable { // SAFETY: every access to the state holds `lock`
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Output, Error>?
    private var cancelled = false
    private var done = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    // Returns false when the task was cancelled before, and the continuation is resumed.
    func install(_ continuation: CheckedContinuation<Output, Error>) -> Bool {
        lock.lock()
        if cancelled {
            done = true
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return false
        }
        self.continuation = continuation
        lock.unlock()
        return true
    }

    func fulfill(_ result: Result<Output, Failure>) {
        lock.lock()
        guard !done, let continuation else {
            lock.unlock()
            return
        }
        done = true
        self.continuation = nil
        lock.unlock()
        nonisolated(unsafe) let unchecked = result // SAFETY: `done` lets one call through, so the result moves to the continuation once
        continuation.resume(with: unchecked)
    }

    func cancel() {
        lock.lock()
        cancelled = true
        guard !done, let continuation else {
            lock.unlock()
            return
        }
        done = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: CancellationError())
    }
}

// DJinni future<> maps to Combine.Future<> in Swift
public typealias DJFuture<T> = Future<T, DjinniError>
