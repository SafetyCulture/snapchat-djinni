import DjinniSupportCxx
import Foundation

// `outcome<T>` is marshalled as a composite value
// 1. A success is one element: the value at [0]
// 2. A failure is two elements: void at [0], the error at [1]
// The count decides the branch, because a success can encode as void
// (outcome<optional<T>, E> with nil).
public enum OutcomeMarshaller<Res: Marshaller, Err: Marshaller>: Marshaller
  where Err.SwiftType: Error {
    public typealias SwiftType = Result<Res.SwiftType, Err.SwiftType>
    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        try withUnsafePointer(to: v) { p in
            if (try compositeSize(p) == 1) {
                return .success(try Res.fromCpp(compositeMember(p, 0)))
            }
            return .failure(try Err.fromCpp(compositeMember(p, 1)))
        }
    }
    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        var comp = djinni.swift.makeCompositeValue()
        switch s {
        case .success(let r):
            try addMember(&comp, try Res.toCpp(r))
        case .failure(let e):
            try addMember(&comp, djinni.swift.makeVoidValue())
            try addMember(&comp, try Err.toCpp(e))
        }
        return comp
    }
}
