import DjinniSupportCxx
import DjinniSupportCore
import SwiftProtobuf
import Foundation

public enum ProtobufMarshaller<T: SwiftProtobuf.Message>: Marshaller {
    public typealias SwiftType = T
    static public func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        let range = try binaryRange(v)
        if (range.size > 0) {
            guard let bytes = range.bytes else { throw DjinniError("a protobuf value has no bytes") }
            let bin = Data(bytesNoCopy:UnsafeMutableRawPointer(mutating: bytes), count:range.size, deallocator:.none)
            do {
                return try T(serializedBytes: bin)
            } catch {
                throw DjinniError("\(T.self): \(error)")
            }
        } else {
            return T()
        }
    }
    static public func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        let bin: Data
        do {
            bin = try s.serializedBytes()
        } catch {
            throw DjinniError("\(T.self): \(error)")
        }
        return try BinaryMarshaller.toCpp(bin)
    }
}
