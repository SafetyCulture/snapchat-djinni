import DjinniSupportCxx
import Foundation

// Define a C++ vtable like data structure for dispatching proxy methods to
// protocol methods.  Each entry in the table is function pointer that takes 3
// parameters
// - The object instance (that conforms to the protocol)
// - The parameter list
// - The return value (output parameter)
// The return value has to be an output parameter instead of the function's
// return type, otherwise the Swift compiler will crash (if this crash is fixed
// in a later version of the compiler, we may change this).
public typealias Vtbl<T> = [@Sendable (T, UnsafePointer<djinni.swift.ParameterList>?, UnsafeMutablePointer<djinni.swift.AnyValue>?) throws -> Void]

// Type erased interface for ProtocolWrapperContext. We don't have the type
// parameter T for ProtocolWrapperContext inside dispatcherProtocalCall (called
// by C++ code)
protocol GenericProtocolWrapperContext: AnyObject, Sendable {
    // The protocol type of the context. It is the proxy cache key of the interface, so the cleanup of one proxy
    // finds its own entry.
    var interface: ObjectIdentifier { get }
    func dispatch(idx: Int32, params: UnsafePointer<djinni.swift.ParameterList>?, ret: UnsafeMutablePointer<djinni.swift.AnyValue>?) -> Void
    func getInst() -> AnyObject
}

// The bridge between C++ caller and Swift protocol. We store
// - The object instance (that conforms to our protocol)
// - The dispatch table for each callable method in the protocol
final class ProtocolWrapperContext<T>: GenericProtocolWrapperContext, @unchecked Sendable { // SAFETY: `inst` and `vtbl` are immutable, the vtbl closures are `@Sendable`, and a conforming object must be safe to call from any thread
    let inst: T
    let vtbl: Vtbl<T>
    // ObjectIdentifier, not the type name: the name has no module, so two protocols with the same name in two modules
    // would share one cache key
    let interface = ObjectIdentifier(T.self)
    init(inst: T, vtbl: Vtbl<T>) {
        self.inst = inst
        self.vtbl = vtbl
    }
    func dispatch(idx: Int32, params: UnsafePointer<djinni.swift.ParameterList>?, ret: UnsafeMutablePointer<djinni.swift.AnyValue>?) -> Void {
        // No Swift error will cross the language boundary. They are converted
        // to `ErrorValue`s which will be translated into C++ exceptions on the
        // other side.
        do {
            try vtbl[Int(idx)](inst, params, ret)
        } catch let error as DjinniError {
            djinni.swift.setErrorValue(ret, error.wrapped)
        } catch {
            djinni.swift.setErrorMessage(ret, std.string(String(describing: error)))
        }
    }
    func getInst() -> AnyObject {
        return inst as AnyObject
    }
}

// This function has a C++ friendly signature. It is passed to C++ and will be
// used by proxy objects to dispatch protocol calls.
public func dispatcherProtocalCall(
  ptr: UnsafeMutableRawPointer?, // The Swift protocol wrapper object as an opaque pointer
  idx: Int32,                    // The method index (starting from 0)
  params: UnsafePointer<djinni.swift.ParameterList>?, // Input parameters from C++ caller
  ret: UnsafeMutablePointer<djinni.swift.AnyValue>?)  // Return value that will be passed back to C++
  -> Void {
    // A call without a context cannot run. C++ gets an error instead of a void result. The cleanup call has no `ret`.
    guard let pctx = ptr else {
        if let ret { djinni.swift.setErrorMessage(ret, std.string("the Swift object of the call is not available")) }
        return
    }
    guard let ctx = Unmanaged<AnyObject>.fromOpaque(pctx).takeUnretainedValue() as? GenericProtocolWrapperContext else { // SAFETY: the pointer is the retained context of ctxPtr, and it stays valid until the dispatch with a negative index
        if let ret { djinni.swift.setErrorMessage(ret, std.string("the Swift object of the call is not available")) }
        return
    }
    if (idx >= 0) {
        // Dynamic dispatch on the vtbl.  We use `takeUnretainedValue` here
        // because we want to keep the wrapper object alive inside the C++ side
        // proxy (inherits ProtocolWrapper).
        ctx.dispatch(idx: idx, params: params, ret: ret)
    } else {
        // If the index is negative, release and destroy the context.  We do
        // this when the C++ side proxy (ProtocolWrapper) is destroyed.
        let key = SwiftProxyCache.Key(object: Unmanaged.passUnretained(ctx.getInst()).toOpaque(), // SAFETY: the key is an identity only, and the cache never dereferences it
                                      interface: ctx.interface)
        SwiftProxyCache.shared.removeIfExpired(key)
        Unmanaged<AnyObject>.fromOpaque(pctx).release() // SAFETY: balances the passRetained of ctxPtr. The C++ proxy sends this index once, from its destructor
    }
}

// Base class for a Swift callable proxy of a C++ object
open class CppProxy: @unchecked Sendable { // SAFETY: `inst` is immutable. The C++ object owns its thread safety, and the generated wrappers only call it
    // Stores a C++ interface. A C++ interface value is a double pointer:
    // 1. A shared_ptr<> that keeps the C++ implementation object alive
    // 2. A shared_ptr<> to a ProtocolWrapper that facilitates dispatching
    public let inst: djinni.swift.AnyValue
    public init(inst: djinni.swift.AnyValue) {
        self.inst = inst
    }
    deinit {
        // Remove the C++ proxy pointer from the proxy cache
        withUnsafePointer(to: inst) { p in
            let info = djinni.swift.getInterfaceInfo(p)
            // A proxy of a null interface was never stored
            if info.valid, let key = info.cppPointer {
                CppProxyCache.shared.removeIfExpired(UnsafeRawPointer(key))
            }
        }
    }
}

final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}

final class CppProxyCache: @unchecked Sendable { // SAFETY: every access to `mapPtrToProxy` holds `lock`, and the cached proxies are `CppProxy` or wrapper objects that are safe to share
    static let shared = CppProxyCache()
    private let lock = NSLock()
    // C++ objects in swift.
    // Key:   raw C++ implementation object pointer
    // Value: weak reference to the Swift callable proxy
    private var mapPtrToProxy: [UnsafeRawPointer: WeakBox] = [:]

    func get(_ key: UnsafeRawPointer) -> AnyObject? {
        lock.lock()
        defer { lock.unlock() }
        return mapPtrToProxy[key]?.value
    }
    // Returns the live proxy of a C++ object, or creates and stores a new one.
    // `create` runs outside the lock. It can throw, and a proxy that dies calls removeIfExpired, which takes the lock.
    // When two threads create a proxy for one object, the first one that stores its proxy wins, and the other proxy is dropped.
    func getOrCreate(_ key: UnsafeRawPointer, _ create: () throws -> AnyObject) throws -> AnyObject {
        if let existing = get(key) {
            return existing
        }
        let proxy = try create()
        lock.lock()
        if let existing = mapPtrToProxy[key]?.value {
            lock.unlock()
            return existing
        }
        mapPtrToProxy[key] = WeakBox(proxy)
        lock.unlock()
        return proxy
    }
    // A newer proxy of the same C++ object keeps its entry.
    func removeIfExpired(_ key: UnsafeRawPointer) {
        // Release the loaded proxy after the unlock. Its deinit calls this function again.
        var alive: AnyObject?
        lock.lock()
        if let box = mapPtrToProxy[key] {
            alive = box.value
            if alive == nil {
                mapPtrToProxy.removeValue(forKey: key)
            }
        }
        lock.unlock()
        withExtendedLifetime(alive) {}
    }
}

final class SwiftProxyCache: @unchecked Sendable { // SAFETY: every access to `mapPtrToProxy` holds `lock`, and a weak proxy is a pair of `weak_ptr`, which is thread-safe
    static let shared = SwiftProxyCache()
    private let lock = NSLock()
    // Swift objects in c++
    // Key:    Swift implementation object converted to an *Unretained* opaque pointer, plus the
    //         protocol type: one object can conform to two djinni protocols, and each gets its
    //         own proxy
    // Value : Weak proxy, no ownership, but can be converted to a C++ callable strong proxy
    struct Key: Hashable {
        let object: UnsafeMutableRawPointer
        let interface: ObjectIdentifier
    }
    private var mapPtrToProxy: [Key: djinni.swift.WeakSwiftProxy] = [:]

    // The live C++ proxy of the key, if there is one. The caller holds the lock.
    private func liveProxy(_ key: Key) -> djinni.swift.AnyValue? {
        guard let weakProxy = mapPtrToProxy[key] else { return nil }
        let strong = djinni.swift.strongify(weakProxy)
        return isNullInterface(strong) ? nil : strong
    }

    // Returns the live C++ proxy of a Swift object, or creates and stores a new one.
    // `create` runs outside the lock, for the reasons of CppProxyCache.getOrCreate.
    func getOrCreate(_ key: Key, _ create: () throws -> djinni.swift.AnyValue) throws -> djinni.swift.AnyValue {
        lock.lock()
        let live = liveProxy(key)
        lock.unlock()
        if let live {
            return live
        }
        let proxy = try create()
        lock.lock()
        if let live = liveProxy(key) {
            lock.unlock()
            return live
        }
        mapPtrToProxy[key] = djinni.swift.weakify(proxy)
        lock.unlock()
        return proxy
    }
    // A newer proxy of the same Swift object keeps its entry.
    func removeIfExpired(_ key: Key) {
        lock.lock()
        defer { lock.unlock() }
        if let weakProxy = mapPtrToProxy[key], djinni.swift.isExpired(weakProxy) {
            mapPtrToProxy.removeValue(forKey: key)
        }
    }

    private func isNullInterface(_ v: djinni.swift.AnyValue) -> Bool {
        return withUnsafePointer(to: v) { p in
            let info = djinni.swift.getInterfaceInfo(p)
            return !info.valid || info.cppPointer == nil
        }
    }
}

private let nullInterfaceMessage = "null value for a non-optional interface"

// 1. Object is a an existing cpp proxy  : return cpp proxy
// 2. Object is a an existing swift proxy: unwrap the original swift object
// 3. Need to create a new proxy         : call newProxyFunc
public func cppInterfaceToSwift<I>(_ c: djinni.swift.AnyValue,
                                   _ newProxyFunc: () throws -> I) throws -> I {
    return try withUnsafePointer(to: c) { p in
        let info = try interfaceInfo(p)
        // C++ can return a null pointer for a non-optional interface. An optional interface does not reach this function with null.
        guard let cppKey = info.cppPointer else { throw DjinniError(nullInterfaceMessage) }
        let key = UnsafeRawPointer(cppKey)
        // 1. Check the CppProxyCache
        if let s = CppProxyCache.shared.get(key) {
            guard let proxy = s as? I else { return try newProxyFunc() }
            return proxy
        }
        // 2. Check if c++ ptr exists in SwiftProxyCache
        if let pctx = info.ctxPointer {
            guard let ctx = Unmanaged<AnyObject>.fromOpaque(pctx).takeUnretainedValue() as? GenericProtocolWrapperContext, // SAFETY: a ctxPointer is the retained context of ctxPtr, and the C++ proxy that the value holds keeps it alive
                  let inst = ctx.getInst() as? I else { return try newProxyFunc() }
            return inst
        }
        // 3. Create new proxy and store a weak reference in CppProxyCache
        guard let proxy = try CppProxyCache.shared.getOrCreate(key, { try newProxyFunc() as AnyObject }) as? I else { return try newProxyFunc() }
        return proxy
    }
}

// Returns the one wrapper of a C++ object, so that all calls to the object use the queue of that wrapper.
public func cppWrapperToSwift<W: AnyObject>(_ c: djinni.swift.AnyValue,
                                            _ newWrapper: () throws -> W) throws -> W {
    return try withUnsafePointer(to: c) { p in
        let info = try interfaceInfo(p)
        guard let cppKey = info.cppPointer else { throw DjinniError(nullInterfaceMessage) }
        guard let wrapper = try CppProxyCache.shared.getOrCreate(UnsafeRawPointer(cppKey), { try newWrapper() }) as? W else { return try newWrapper() }
        return wrapper
    }
}

// The C++ values that Swift reads. The C++ helpers do not throw: a value of the wrong kind or an index out of
// range comes back as a flag or as an error value, and these functions throw it as a DjinniError.
public func compositeSize(_ p: UnsafePointer<djinni.swift.AnyValue>) throws -> Int {
    let result = djinni.swift.getSize(p)
    guard result.valid else { throw DjinniError("the value is not a composite") }
    return Int(result.size)
}

public func compositeMember(_ p: UnsafePointer<djinni.swift.AnyValue>, _ index: Int) throws -> djinni.swift.AnyValue {
    guard index >= 0 else { throw DjinniError("the composite has no member \(index)") }
    return try checkedValue(djinni.swift.getMember(p, index))
}

public func addMember(_ composite: inout djinni.swift.AnyValue, _ member: djinni.swift.AnyValue) throws {
    guard djinni.swift.addMember(&composite, member) else { throw DjinniError("the value is not a composite") }
}

public func parameter(_ p: UnsafePointer<djinni.swift.ParameterList>?, _ index: Int) throws -> djinni.swift.AnyValue {
    guard index >= 0 else { throw DjinniError("the call has no parameter \(index)") }
    return try checkedValue(djinni.swift.getMember(p, index))
}

public func int32Value(_ v: djinni.swift.AnyValue) throws -> Int32 {
    let result = djinni.swift.getI32Value(v)
    guard result.valid else { throw DjinniError("the value is not a 32-bit integer") }
    return result.value
}

public func int64Value(_ v: djinni.swift.AnyValue) throws -> Int64 {
    let result = djinni.swift.getI64Value(v)
    guard result.valid else { throw DjinniError("the value is not a 64-bit integer") }
    return result.value
}

public func doubleValue(_ v: djinni.swift.AnyValue) throws -> Double {
    let result = djinni.swift.getDoubleValue(v)
    guard result.valid else { throw DjinniError("the value is not a floating point number") }
    return result.value
}

public func binaryRange(_ v: djinni.swift.AnyValue) throws -> djinni.swift.BinaryRangeResult {
    let range = djinni.swift.getBinaryRange(v)
    guard range.valid else { throw DjinniError("the value is not a string, a binary or a range") }
    return range
}

public func interfaceInfo(_ p: UnsafePointer<djinni.swift.AnyValue>) throws -> djinni.swift.InterfaceInfo {
    let info = djinni.swift.getInterfaceInfo(p)
    guard info.valid else { throw DjinniError("the value is not an interface") }
    return info
}

// A C++ helper that cannot throw gives an error value instead. This turns it into a Swift error.
func checkedValue(_ value: consuming djinni.swift.AnyValue) throws -> djinni.swift.AnyValue {
    // The check borrows the value, and the result moves it, so a string or a binary is not copied again
    try withUnsafePointer(to: value) { p in
        if djinni.swift.isError(p) {
            throw DjinniError(djinni.swift.getError(p))
        }
    }
    return value
}

// The C++ `make` function of a Swift proxy gives an error value when it fails.
public func checkedProxy(_ v: djinni.swift.AnyValue) throws -> djinni.swift.AnyValue {
    return try checkedValue(v)
}


// 1. object is a an existing cpp proxy  : unwrap swift proxy
// 2. object is a an existing swift proxy: return existing
// 3. need to create a new proxy         : call newProxyFunc
public func swiftInterfaceToCpp<I>(_ s: I,
                                   _ newProxyFunc: () throws -> djinni.swift.AnyValue) throws -> djinni.swift.AnyValue {
    // 1. Try cast to CppProxy and unwrap
    if let cppproxy = s as? CppProxy {
        return cppproxy.inst
    }
    // 2. Reuse the live swift proxy, or 3. create new proxy and store a weak reference
    let key = SwiftProxyCache.Key(object: Unmanaged.passUnretained(s as AnyObject).toOpaque(), // SAFETY: the key is an identity only, and the cache never dereferences it
                                  interface: ObjectIdentifier(I.self))
    return try SwiftProxyCache.shared.getOrCreate(key, newProxyFunc)
}

// Shortcut function to create a Swift protocol wrapper context and return its
// *Retained* pointer. The returned pointer is owned by the C++ side
// ProtocolWrapper, and released in ProtocolWrapper::~ProtocolWrapper() by
// sending a dispatch request with index -1.
public func ctxPtr<I> (_ s: I, _ vtbl: Vtbl<I>) -> UnsafeMutableRawPointer {
    let ctx = ProtocolWrapperContext(inst: s, vtbl: vtbl)
    return Unmanaged.passRetained(ctx).toOpaque() // SAFETY: the C++ ProtocolWrapper owns this retain, and the dispatch with index -1 releases it
}

// Wraps C++ ErrorValue as a Swift throwable Error
public final class DjinniError: Error, @unchecked Sendable { // SAFETY: `wrapped` is immutable, and the `exception_ptr` inside it is only rethrown, which is thread-safe
    let wrapped: djinni.swift.ErrorValue
    init(_ wrapped: djinni.swift.ErrorValue) {
        self.wrapped = wrapped
    }
    public init(_ msg: String) {
        self.wrapped = djinni.swift.ErrorValue(std.string(msg))
    }
    public var errorMessage: String { return String(wrapped.msg) }
}

// Logs and `String(describing:)` show the message of the C++ exception, not only the type name
extension DjinniError: CustomStringConvertible, LocalizedError {
    public var description: String { return "DjinniError: \(errorMessage)" }
    public var errorDescription: String? { return errorMessage }
}

// Called by stubs to convert C++ exceptions stored as ErrorValue to Swift errors
public func handleCppErrors(_ ret: UnsafePointer<djinni.swift.AnyValue>) throws {
    if (djinni.swift.isError(ret)) {
        throw DjinniError(djinni.swift.getError(ret))
    }
}

/// The error type of `--swift-error-type` conforms to this protocol. Every method that Swift calls into C++ throws the
/// error type. The application decides how the error type holds each failure:
/// - `init(cppException:)`: C++ threw, rejected a future, or dropped a promise. `DjinniError.errorMessage` is the message
///   of the C++ exception.
/// - `init(cancellation:)`: the task was cancelled before the C++ call, or while it waited for a C++ future.
public protocol CppExceptionConvertible: Error {
    init(cppException error: DjinniError)
    init(cancellation: CancellationError)
}

// An error of a C++ call becomes the error type: an error of an outcome stays as it is.
func djinniTypedError<E: CppExceptionConvertible>(_ error: any Error) -> E {
    switch error {
    case let typed as E: return typed
    case let cancellation as CancellationError: return E(cancellation: cancellation)
    case let cpp as DjinniError: return E(cppException: cpp)
    default: return E(cppException: DjinniError(String(describing: error)))
    }
}

/// Runs a C++ call on the thread of the caller and throws its errors as `E`.
public func djinniTyped<T, E: CppExceptionConvertible>(_ type: E.Type, _ call: () throws -> T) throws(E) -> T {
    do {
        return try call()
    } catch {
        let typed: E = djinniTypedError(error)
        throw typed
    }
}

// Carries a value across a concurrency boundary when the caller guarantees that the use is safe.
public struct UncheckedSendable<Value>: @unchecked Sendable { // SAFETY: the caller of the initialiser guarantees that `value` is used in one place at a time
    public let value: Value
    public init(_ value: Value) { self.value = value }
}
