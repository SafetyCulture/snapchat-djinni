import DjinniSupportCxx
@_spi(DjinniCxx) import DjinniSupportCore

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
