import DjinniSupportCxx
import Foundation

// A custom Future<> type thanks to Logan Shire <@LoganShireSnapchat>
public final class Cancellable: @unchecked Sendable {
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


public final class Future<Output, Failure> where Failure : Error {
    public typealias Promise = (Result<Output, Failure>) -> Void

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

    public init(_ attemptToFulfill: @escaping (@escaping Promise) -> Void) {
        attemptToFulfill { [weak self] result in
            guard let self else { return }
            
            self.lock.lock()

            // If the promise was already fulfilled, fire an assertion failure, unlock and return:
            if self.storedResult != nil {
                assertionFailure("attempted to fulfill future multiple times")
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
            for subscription in copiedSubscriptions.values {
                let call = UncheckedSendable { subscription(result) }
                DispatchQueue.global(qos: .default).async {
                    call.value()
                }
            }
        }
    }

    // A cancelled task stops waiting and throws CancellationError. The future is not cancelled.
    public var value: Output {
        get async throws {
            let token = generateToken()
            let waiter = Waiter<Output, Failure>()
            return try await withTaskCancellationHandler {
                return try await withCheckedThrowingContinuation { continuation in
                    if waiter.install(continuation) {
                        self.subscribe(token: token) { result in
                            waiter.fulfill(result)
                        }
                        // onCancel can run before the subscription exists.
                        if waiter.isCancelled {
                            self.cancel(token: token)
                        }
                    }
                }
            } onCancel: {
                // Cancel the waiter first. Then a body that is between install and subscribe sees isCancelled.
                waiter.cancel()
                self.cancel(token: token)
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
extension Future: @unchecked Sendable where Output: Sendable {}

// Resumes the continuation of `Future.value` exactly once, with a result or with CancellationError.
private final class Waiter<Output, Failure: Error>: @unchecked Sendable {
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
        nonisolated(unsafe) let unchecked = result
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
}
// The Swift Future wrapper object that can be fulfilled by a C++ call
final class PromiseHolder<T: Marshaller>: AbstractPromiseHolder, @unchecked Sendable {
    let promise: DJFuture<T.SwiftType>.Promise
    init(marshaller: T.Type, promise: @escaping DJFuture<T.SwiftType>.Promise) {
        self.promise = promise
    }
    func fulfillPromise(value: UnsafePointer<djinni.swift.AnyValue>) {
        if (!djinni.swift.isError(value)) {
            do {
                promise(.success(try T.fromCpp(value.pointee)))
            } catch {
                promise(.failure(DjinniError("\(error)")))
            }
        } else {
            promise(.failure(DjinniError(djinni.swift.getError(value))))
        }
    }
}
// A C++ friendly function. This is passed to C++ as the continuation routine of
// the C++ future. It calls the PromiseHolder and forwards the C++ future's
// result or error to the Swift future.
public func futureCb(
  ptr: UnsafeMutableRawPointer?,
  result: UnsafeMutablePointer<djinni.swift.AnyValue>?)
  -> Void {
    guard let ptr, let result else { return }
    let ctx = Unmanaged<AnyObject>.fromOpaque(ptr).takeRetainedValue()
    guard let promiseHolder = ctx as? AbstractPromiseHolder else { return }
    promiseHolder.fulfillPromise(value: result)
}

// A C++ friendly function to release the subscription token stored with the C++
// future value.
public func cleanupCb(psubscription: UnsafeMutableRawPointer?) -> Void {
    guard let psubscription else { return }
    let _ = Unmanaged<Cancellable>.fromOpaque(psubscription).takeRetainedValue()
}

public enum FutureMarshaller<T: Marshaller>: Marshaller {
    public typealias SwiftType = DJFuture<T.SwiftType>
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return Future() { promise in
            // Allocate the Swift future wrapper
            let promiseHolder = PromiseHolder(marshaller: T.self, promise: promise)
            let promiseHolderPtr = Unmanaged.passRetained(promiseHolder).toOpaque()
            // And connect it with the C++ future
            withUnsafePointer(to: v) { p in
                djinni.swift.setFutureCb(p, futureCb, promiseHolderPtr)
            }
        }
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        // Create a C++ future
        var futureValue = djinni.swift.makeFutureValue(cleanupCb)
        // Connect it with the Swift future
        let cancellable = s.getResult { result in
            switch result {
            case .success(let value):
                do {
                    var cppValue = try T.toCpp(value)
                    djinni.swift.setFutureResult(&futureValue, &cppValue)
                } catch {
                    // A failed conversion becomes the error of the C++ future
                    var errorValue = djinni.swift.makeVoidValue()
                    djinni.swift.setErrorValue(&errorValue, DjinniError("\(error)").wrapped)
                    djinni.swift.setFutureResult(&futureValue, &errorValue)
                }
            case .failure(let error):
                var errorValue = djinni.swift.makeVoidValue()
                djinni.swift.setErrorValue(&errorValue, error.wrapped)
                djinni.swift.setFutureResult(&futureValue, &errorValue)
            }
        }
        // Store the cancellable token so that the connection remains alive.
        let pSubscription = Unmanaged.passRetained(cancellable).toOpaque()
        djinni.swift.storeSubscription(&futureValue, pSubscription)
        return futureValue
    }
}
