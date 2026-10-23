import DjinniSupportCxx
import Foundation

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
    // A subscriber runs on a global queue when the result comes later, and before getResult returns, on the thread of
    // the caller, when the future already has its result. So it must be `@Sendable`, and it must not take a lock that
    // the caller of getResult holds.
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

// Type erased interface for PromiseHolder because in futureCb() we don't have
// the type parameter.
protocol AbstractPromiseHolder: AnyObject {
    func fulfillPromise(value: UnsafePointer<djinni.swift.AnyValue>)
    func fail(_ error: DjinniError)
}
// The Swift Future wrapper object that can be fulfilled by a C++ call
final class PromiseHolder<T: Marshaller>: AbstractPromiseHolder, @unchecked Sendable { // SAFETY: `promise` is immutable, and a promise is safe to call from any thread
    let promise: DJFuture<T.SwiftType>.Promise
    init(marshaller: T.Type, promise: @escaping DJFuture<T.SwiftType>.Promise) {
        self.promise = promise
    }
    func fulfillPromise(value: UnsafePointer<djinni.swift.AnyValue>) {
        if (!djinni.swift.isError(value)) {
            do {
                promise(.success(try T.fromCpp(value.pointee)))
            } catch {
                // An inner DjinniError keeps its message (for example the protobuf type name)
                promise(.failure(error as? DjinniError ?? DjinniError(String(describing: error))))
            }
        } else {
            promise(.failure(DjinniError(djinni.swift.getError(value))))
        }
    }
    func fail(_ error: DjinniError) {
        promise(.failure(error))
    }
}
// A C++ friendly function. This is passed to C++ as the continuation routine of
// the C++ future. It calls the PromiseHolder and forwards the C++ future's
// result or error to the Swift future.
public func futureCb(
  ptr: UnsafeMutableRawPointer?,
  result: UnsafeMutablePointer<djinni.swift.AnyValue>?)
  -> Void {
    guard let ptr else { return }
    // SAFETY: the pointer is the retained PromiseHolder of FutureMarshaller.fromCpp, and C++ calls this function once
    let ctx = Unmanaged<AnyObject>.fromOpaque(ptr).takeRetainedValue()
    guard let promiseHolder = ctx as? AbstractPromiseHolder else { return }
    guard let result else {
        // The future must complete, or the task that awaits it waits for ever
        promiseHolder.fail(DjinniError("the C++ future gave no result"))
        return
    }
    promiseHolder.fulfillPromise(value: result)
}

// A C++ friendly function to release the subscription token stored with the C++
// future value.
public func cleanupCb(psubscription: UnsafeMutableRawPointer?) -> Void {
    guard let psubscription else { return }
    // SAFETY: the pointer is the retained Cancellable of FutureMarshaller.toCpp, and C++ calls this function once
    let _ = Unmanaged<Cancellable>.fromOpaque(psubscription).takeRetainedValue()
}

public enum FutureMarshaller<T: Marshaller>: Marshaller {
    public typealias SwiftType = DJFuture<T.SwiftType>
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return Future() { promise in
            // Allocate the Swift future wrapper
            let promiseHolder = PromiseHolder(marshaller: T.self, promise: promise)
            let promiseHolderPtr = Unmanaged.passRetained(promiseHolder).toOpaque() // SAFETY: futureCb balances this retain, and C++ always calls it once, with a result or with an error
            // And connect it with the C++ future
            withUnsafePointer(to: v) { p in
                djinni.swift.setFutureCb(p, futureCb, promiseHolderPtr)
            }
        }
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        // Create a C++ future
        let futureValue = try checkedValue(djinni.swift.makeFutureValue(cleanupCb))
        // The holder of the C++ side completes its promise once and is safe to use from any thread.
        let target = UncheckedSendable(futureValue) // SAFETY: setFutureResult only reads the holder pointer, and the holder completes its promise once
        // The converter of the element type. A metatype is static data, and a function value does not capture it.
        let convert = UncheckedSendable(T.toCpp) // SAFETY: T.toCpp is a static function without state
        // Connect it with the Swift future
        let cancellable = s.getResult { result in
            var futureValue = target.value
            switch result {
            case .success(let value):
                do {
                    var cppValue = try convert.value(value)
                    djinni.swift.setFutureResult(&futureValue, &cppValue)
                } catch {
                    // A failed conversion becomes the error of the C++ future
                    var errorValue = djinni.swift.makeVoidValue()
                    djinni.swift.setErrorValue(&errorValue, (error as? DjinniError ?? DjinniError(String(describing: error))).wrapped)
                    djinni.swift.setFutureResult(&futureValue, &errorValue)
                }
            case .failure(let error):
                var errorValue = djinni.swift.makeVoidValue()
                djinni.swift.setErrorValue(&errorValue, error.wrapped)
                djinni.swift.setFutureResult(&futureValue, &errorValue)
            }
        }
        // Store the cancellable token so that the connection remains alive.
        let pSubscription = Unmanaged.passRetained(cancellable).toOpaque() // SAFETY: cleanupCb balances this retain when the C++ future value is destroyed
        var stored = futureValue
        djinni.swift.storeSubscription(&stored, pSubscription)
        return futureValue
    }
}
