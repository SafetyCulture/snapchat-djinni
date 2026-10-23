import DjinniSupportCxx
import Foundation

// Common interface for all Swift type marshallers
// The C++ type is always djinni.swift.AnyValue
public protocol Marshaller {
    associatedtype SwiftType
    static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType
    static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue
}
// Djinni generated enums are always backed by Int32
public enum EnumMarshaller<T: RawRepresentable>: Marshaller where T.RawValue == Int32 {
    public typealias SwiftType = T
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let raw = djinni.swift.I32.toCpp(v)
        guard let value = SwiftType(rawValue: raw) else {
            throw DjinniError("unknown \(SwiftType.self) value \(raw)")
        }
        return value
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return djinni.swift.I32.fromCpp(s.rawValue)
    }
}
// All integer types smaller than 32-bit are handled by this
public enum SmallIntMarshaller<T: BinaryInteger>: Marshaller {
    public typealias SwiftType = T
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let raw = djinni.swift.I32.toCpp(v)
        guard let value = SwiftType(exactly: raw) else {
            throw DjinniError("\(SwiftType.self) value out of range: \(raw)")
        }
        return value
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return djinni.swift.I32.fromCpp(Int32(s))
    }
}
// 64-bit integer
public enum I64Marshaller: Marshaller {
    public typealias SwiftType = Int64
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let raw = djinni.swift.I64.toCpp(v)
        guard let value = SwiftType(exactly: raw) else {
            throw DjinniError("\(SwiftType.self) value out of range: \(raw)")
        }
        return value
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return djinni.swift.I64.fromCpp(s)
    }
}
// Both float and double are marshalled to double values
public enum FloatMarshaller<T: BinaryFloatingPoint>: Marshaller {
    public typealias SwiftType = T
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return T(djinni.swift.F64.toCpp(v))
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return djinni.swift.F64.fromCpp(Double(s))
    }
}
// Bool is marshalled as Int32 (0 or 1)
public enum BoolMarshaller: Marshaller {
    public typealias SwiftType = Bool
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return djinni.swift.I32.toCpp(v) != 0
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return djinni.swift.I32.fromCpp(s ? 1 : 0)
    }
}
// Aliases for number types
public typealias I8Marshaller = SmallIntMarshaller<Int8>
public typealias I16Marshaller = SmallIntMarshaller<Int16>
public typealias I32Marshaller = SmallIntMarshaller<Int32>
public typealias F32Marshaller = FloatMarshaller<Float>
public typealias F64Marshaller = FloatMarshaller<Double>

public enum StringMarshaller: Marshaller {
    public typealias SwiftType = String
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let range = try binaryRange(v)
        if (range.size == 0) {
            return String()
        }
        guard let bytes = range.bytes else { throw DjinniError("a string value has no bytes") }
        let buffer = UnsafeBufferPointer(start: bytes.assumingMemoryBound(to: UInt8.self), count: range.size)
        // String(decoding:) replaces each invalid sequence with U+FFFD and keeps a leading BOM. The bytes of the result
        // equal the input only when the input is valid UTF-8.
        let string = String(decoding: buffer, as: UTF8.self)
        guard string.utf8.elementsEqual(buffer) else { throw DjinniError("a string value is not valid UTF-8") }
        return string
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        let bytes = s.utf8CString
        return bytes.withUnsafeBufferPointer { ptr in
            // utf8CString always has a buffer with the terminator
            guard let base = ptr.baseAddress else { return djinni.swift.makeStringValue(nil, 0) }
            return djinni.swift.makeStringValue(UnsafeMutableRawPointer(mutating: base),
                                                ptr.count - 1) // minus terminating \0
        }
    }
}

public enum BinaryMarshaller: Marshaller {
    public typealias SwiftType = Data
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let range = try binaryRange(v)
        if (range.size == 0) {
            return Data()
        }
        guard let bytes = range.bytes else { throw DjinniError("a binary value has no bytes") }
        return Data(bytes: bytes, count: range.size)
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        // withUnsafeBytes can give a nil baseAddress for an empty Data, and makeBinaryValue accepts nil
        return s.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
            return djinni.swift.makeBinaryValue(UnsafeMutableRawPointer(mutating: ptr.baseAddress),
                                                ptr.count)
        }
    }
}

public enum DateMarshaller: Marshaller {
    public typealias SwiftType = Date
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let millisecondsSinceEpoch = try I64Marshaller.fromCpp(v)
        return Date(timeIntervalSince1970: Double(millisecondsSinceEpoch) / 1000)
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        guard let ms = Int64(exactly: (s.timeIntervalSince1970 * 1000).rounded()) else {
            throw DjinniError("Date out of range for milliseconds since epoch: \(s.timeIntervalSince1970)")
        }
        return try I64Marshaller.toCpp(ms)
    }
}

public enum Void_Marshaller: Marshaller {
    public typealias SwiftType = Void
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return ()
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return djinni.swift.makeVoidValue()
    }
}

public enum OptionalMarshaller<T: Marshaller>: Marshaller {
    public typealias SwiftType = T.SwiftType?
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return try withUnsafePointer(to: v) { p in
            if (djinni.swift.isVoidValue(p)) {
                return nil
            }
            return try T.fromCpp(v)
        }
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        guard let s else {
            return djinni.swift.makeVoidValue()
        }
        return try T.toCpp(s)
    }
}

public enum ListMarshaller<T: Marshaller>: Marshaller {
    public typealias SwiftType = [T.SwiftType]
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        var array = SwiftType()
        try withUnsafePointer(to: v) { p in
            let size = try compositeSize(p)
            for i in 0..<size {
                array.append(try T.fromCpp(compositeMember(p, i)))
            }
        }
        return array
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        var composite = djinni.swift.makeCompositeValue()
        for item in s {
            djinni.swift.addMember(&composite, try T.toCpp(item))
        }
        return composite
    }
}

// Swift don't need to box primitive types in arrays so they are identical to list
public typealias ArrayMarshaller<T: Marshaller> = ListMarshaller<T>

public enum SetMarshaller<T: Marshaller>: Marshaller where T.SwiftType: Hashable {
    public typealias SwiftType = Set<T.SwiftType>
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        var s = SwiftType()
        try withUnsafePointer(to: v) { p in
            let size = try compositeSize(p)
            for i in 0..<size {
                s.insert(try T.fromCpp(compositeMember(p, i)))
            }
        }
        return s
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        var composite = djinni.swift.makeCompositeValue()
        for item in s {
            djinni.swift.addMember(&composite, try T.toCpp(item))
        }
        return composite
    }
}

public enum MapMarshaller<K: Marshaller, V: Marshaller>: Marshaller where K.SwiftType: Hashable {
    public typealias SwiftType = Dictionary<K.SwiftType, V.SwiftType>
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        var s = SwiftType()
        try withUnsafePointer(to: v) { p in
            let size = try compositeSize(p)
            guard size % 2 == 0 else { throw DjinniError("a map has an odd number of keys and values") }
            for i in stride(from: 0, to: size, by: 2) {
                try s.updateValue(V.fromCpp(compositeMember(p, i+1)),
                                  forKey: K.fromCpp(compositeMember(p, i)))
            }
        }
        return s
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        var composite = djinni.swift.makeCompositeValue()
        for (k, v) in s {
            djinni.swift.addMember(&composite, try K.toCpp(k))
            djinni.swift.addMember(&composite, try V.toCpp(v))
        }
        return composite
    }
}
