// The stub of the extern module that holds the Swift marshaller of swift_models_error.yaml. Only the generated private
// files import it.
import DjinniSupport
import DjinniSupportCxx
import Models

public enum CruxErrorMarshaller: DjinniSupport.Marshaller {
    public typealias SwiftType = Models.CruxError

    public static func fromCpp(_ v: djinni.swift.AnyValue) throws -> SwiftType {
        return SwiftType(message: try DjinniSupport.StringMarshaller.fromCpp(v), code: 0)
    }

    public static func toCpp(_ s: SwiftType) throws -> djinni.swift.AnyValue {
        return try DjinniSupport.StringMarshaller.toCpp(s.message)
    }
}
