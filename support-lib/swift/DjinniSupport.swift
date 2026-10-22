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
    func dispatch(idx: Int32, params: UnsafePointer<djinni.swift.ParameterList>?, ret: UnsafeMutablePointer<djinni.swift.AnyValue>?) -> Void
    func getInst() -> AnyObject
}

// The bridge between C++ caller and Swift protocol. We store
// - The object instance (that conforms to our protocol)
// - The dispatch table for each callable method in the protocol
final class ProtocolWrapperContext<T>: GenericProtocolWrapperContext, @unchecked Sendable {
    let inst: T
    let vtbl: Vtbl<T>
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
    guard let pctx = ptr else { return }
    let ctx = Unmanaged<AnyObject>.fromOpaque(pctx).takeUnretainedValue() as! GenericProtocolWrapperContext
    if (idx >= 0) {
        // Dynamic dispatch on the vtbl.  We use `takeUnretainedValue` here
        // because we want to keep the wrapper object alive inside the C++ side
        // proxy (inherits ProtocolWrapper).
        ctx.dispatch(idx: idx, params: params, ret: ret)
    } else {
        // If the index is negative, release and destroy the context.  We do
        // this when the C++ side proxy (ProtocolWrapper) is destroyed.
        let key = Unmanaged.passUnretained(ctx.getInst()).toOpaque()
        SwiftProxyCache.shared.removeIfExpired(key)
        Unmanaged<AnyObject>.fromOpaque(pctx).release()
    }
}

// Base class for a Swift callable proxy of a C++ object
open class CppProxy: @unchecked Sendable {
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
            CppProxyCache.shared.removeIfExpired(info.cppPointer)
        }
    }
}

final class WeakBox {
    weak var value: AnyObject?
    init(_ value: AnyObject) { self.value = value }
}

final class CppProxyCache: @unchecked Sendable {
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
    func getOrCreate(_ key: UnsafeRawPointer, _ create: () -> AnyObject) -> AnyObject {
        lock.lock()
        defer { lock.unlock() }
        if let existing = mapPtrToProxy[key]?.value {
            return existing
        }
        let proxy = create()
        mapPtrToProxy[key] = WeakBox(proxy)
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

final class SwiftProxyCache: @unchecked Sendable {
    static let shared = SwiftProxyCache()
    private let lock = NSLock()
    // Swift objects in c++
    // Key:    Swift implementation object converted to an *Unretained* opaque pointer
    // Value : Weak proxy, no ownership, but can be converted to a C++ callable strong proxy
    private var mapPtrToProxy: [UnsafeMutableRawPointer: djinni.swift.WeakSwiftProxy] = [:]

    // Returns the live C++ proxy of a Swift object, or creates and stores a new one.
    func getOrCreate(_ key: UnsafeMutableRawPointer, _ create: () -> djinni.swift.AnyValue) -> djinni.swift.AnyValue {
        lock.lock()
        defer { lock.unlock() }
        if let weakProxy = mapPtrToProxy[key] {
            let strong = djinni.swift.strongify(weakProxy)
            if !isNullInterface(strong) {
                return strong
            }
        }
        let proxy = create()
        mapPtrToProxy[key] = djinni.swift.weakify(proxy)
        return proxy
    }
    // A newer proxy of the same Swift object keeps its entry.
    func removeIfExpired(_ key: UnsafeMutableRawPointer) {
        lock.lock()
        defer { lock.unlock() }
        if let weakProxy = mapPtrToProxy[key], djinni.swift.isExpired(weakProxy) {
            mapPtrToProxy.removeValue(forKey: key)
        }
    }

    private func isNullInterface(_ v: djinni.swift.AnyValue) -> Bool {
        return withUnsafePointer(to: v) { p in djinni.swift.getInterfaceInfo(p).cppPointer == nil }
    }
}

// 1. Object is a an existing cpp proxy  : return cpp proxy
// 2. Object is a an existing swift proxy: unwrap the original swift object
// 3. Need to create a new proxy         : call newProxyFunc
public func cppInterfaceToSwift<I>(_ c: djinni.swift.AnyValue,
                                   _ newProxyFunc: ()->I) -> I {
    return withUnsafePointer(to: c) { p in
        let info = djinni.swift.getInterfaceInfo(p)
        // 1. Check the CppProxyCache
        if let s = CppProxyCache.shared.get(info.cppPointer) {
            return s as! I
        }
        // 2. Check if c++ ptr exists in SwiftProxyCache
        if let pctx = info.ctxPointer {
            let ctx = Unmanaged<AnyObject>.fromOpaque(pctx).takeUnretainedValue() as! GenericProtocolWrapperContext
            return ctx.getInst() as! I
        }
        // 3. Create new proxy and store a weak reference in CppProxyCache
        return CppProxyCache.shared.getOrCreate(info.cppPointer) { newProxyFunc() as AnyObject } as! I
    }
}

// Returns the one wrapper of a C++ object, so that all calls to the object use the queue of that wrapper.
public func cppWrapperToSwift<W: AnyObject>(_ c: djinni.swift.AnyValue,
                                            _ newWrapper: () -> W) -> W {
    return withUnsafePointer(to: c) { p in
        let info = djinni.swift.getInterfaceInfo(p)
        return CppProxyCache.shared.getOrCreate(info.cppPointer) { newWrapper() } as! W
    }
}

// 1. object is a an existing cpp proxy  : unwrap swift proxy
// 2. object is a an existing swift proxy: return existing
// 3. need to create a new proxy         : call newProxyFunc
public func swiftInterfaceToCpp<I>(_ s: I,
                                   _ newProxyFunc: ()->djinni.swift.AnyValue) -> djinni.swift.AnyValue {
    // 1. Try cast to CppProxy and unwrap
    if let cppproxy = s as? CppProxy {
        return cppproxy.inst
    }
    // 2. Reuse the live swift proxy, or 3. create new proxy and store a weak reference
    let key = Unmanaged.passUnretained(s as AnyObject).toOpaque()
    return SwiftProxyCache.shared.getOrCreate(key, newProxyFunc)
}

// Shortcut function to create a Swift protocol wrapper context and return its
// *Retained* pointer. The returned pointer is owned by the C++ side
// ProtocolWrapper, and released in ProtocolWrapper::~ProtocolWrapper() by
// sending a dispatch request with index -1.
public func ctxPtr<I> (_ s: I, _ vtbl: Vtbl<I>) -> UnsafeMutableRawPointer {
    let ctx = ProtocolWrapperContext(inst: s, vtbl: vtbl)
    return Unmanaged.passRetained(ctx).toOpaque()
}

// Wraps C++ ErrorValue as a Swift throwable Error
public final class DjinniError: Error, @unchecked Sendable {
    let wrapped: djinni.swift.ErrorValue
    init(_ wrapped: djinni.swift.ErrorValue) {
        self.wrapped = wrapped
    }
    public init(_ msg: String) {
        self.wrapped = djinni.swift.ErrorValue(std.string(msg))
    }
    public var errorMessage: String { return String(wrapped.msg) }
}

// Called by stubs to convert C++ exceptions stored as ErrorValue to Swift errors
public func handleCppErrors(_ ret: UnsafePointer<djinni.swift.AnyValue>) throws {
    if (djinni.swift.isError(ret)) {
        throw DjinniError(djinni.swift.getError(ret))
    }
}

// Called by the proxy of a wrapped interface. A C++ exception stops the program.
public func handleCppErrorsAsFatal(_ ret: UnsafePointer<djinni.swift.AnyValue>, _ method: String) {
    if (djinni.swift.isError(ret)) {
        fatalError("\(method) threw a C++ exception: \(String(djinni.swift.getError(ret).msg))")
    }
}

// Carries a value across a concurrency boundary when the caller guarantees that the use is safe.
public struct UncheckedSendable<Value>: @unchecked Sendable {
    public let value: Value
    public init(_ value: Value) { self.value = value }
}
