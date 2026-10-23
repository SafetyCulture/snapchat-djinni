import DjinniSupportCxx
import Foundation

// DataView and DataRef are bridged to `NSData` instead of `Data` because `Data`
// uses small buffer optimization and it does not always provide a stable
// pointer that can be safely accessed in C++ (the pointer we can get from a
// small Data object will only work within the scope of `withUnsafeBytes` block)
public enum DataViewMarshaller: Marshaller {
    public typealias SwiftType = NSData
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let range = try binaryRange(v)
        if (range.size == 0) {
            return SwiftType()
        }
        guard let bytes = range.bytes else { throw DjinniError("a DataView value has no bytes") }
        return SwiftType(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), length: range.size, deallocator:.none)
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return djinni.swift.makeRangeValue(s.bytes, s.length)
    }
}
// The C++ side implementation of DataRef uses CFData which is toll-free bridged
// to NSData.
// The C++ value owns its own reference to the CFData until the value is destroyed, so a conversion that throws
// before it reaches the DataRef does not leak the reference. Swift never has to balance a retain by hand.
public enum DataRefMarshaller: Marshaller {
    public typealias SwiftType = NSData
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return try withUnsafePointer(to: v) { p in
            guard let object = djinni.swift.getDataRefObject(p) else { throw DjinniError("a DataRef value has no data") }
            // Swift takes its own reference. The value keeps the one that it owns.
            return Unmanaged<CFData>.fromOpaque(object).takeUnretainedValue() as NSData // SAFETY: the value `v` owns the CFData, and it stays alive during this call
        }
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        // C++ retains the object for its own value, so `s` only has to stay alive during the call
        let value = withExtendedLifetime(s) {
            if let nsMutableData = s as? NSMutableData {
                return djinni.swift.makeDataRefValue(Unmanaged.passUnretained(nsMutableData).toOpaque(), true) // SAFETY: `s` is alive here, and C++ takes its own reference
            } else {
                return djinni.swift.makeDataRefValue(Unmanaged.passUnretained(s as CFData).toOpaque(), false) // SAFETY: `s` is alive here, and C++ takes its own reference
            }
        }
        return try checkedValue(value)
    }
}
