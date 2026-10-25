import DjinniSupportCore
import Models
import TestSuite

// A client of the generated module without C++ interoperability. It imports no C++ module and names no C++ type.

final class Listener: SwiftCxxFreeListener, @unchecked Sendable { // SAFETY: the test writes `seen` from one thread
    private(set) var seen: [String] = []

    func onItem(_ item: SwiftCxxFreeItem) throws -> Void {
        seen.append(item.id)
    }

    func next(_ value: Int32) throws -> Int32 {
        value + 1
    }
}

// The record with a future field names the support type of DjinniSupportCore.
func pending() -> SwiftCxxFreePending {
    let future = DJFuture<Int32> { promise in promise(.success(7)) }
    return SwiftCxxFreePending(value: future, label: "client")
}

// No default case: the enum is @frozen, so the switch stays exhaustive across the module boundary.
func colorName(_ color: SwiftCxxFreeColor) -> String {
    switch color {
    case .red: return "red"
    case .green: return "green"
    case .blue: return "blue"
    }
}

// The async wrapper method throws the error type of --swift-error-type.
func fetch(_ service: SwiftCxxFreeService) async throws(SwiftCxxFreeFailure) -> SwiftCxxFreeItem {
    return try await service.fetch("client")
}

// The class of the static methods is public.
func makeService() throws(SwiftCxxFreeFailure) -> SwiftCxxFreeService {
    return try SwiftCxxFreeService_statics.create()
}

// The async wrapper of a future<outcome<T, E>> returns the outcome of the extern module.
func ext(_ lookup: SwiftCxxFreeLookup) async throws -> Result<Int32, Models.CruxError> {
    return try await lookup.ext()
}

// The error type of the extern module comes through the class of the static methods.
func makeErrorService() throws(Models.CruxError) -> SwiftCxxFreeErrorService {
    return try SwiftCxxFreeErrorService_statics.create()
}

// The class of the static methods of the plain case, whose methods do not name the error record.
func plainCount() throws(Models.CruxError) -> Int32 {
    return try SwiftCxxFreePlainStatic_statics.count()
}

// The error type reaches the client through CppExceptionConvertible.
func asConvertible<E: CppExceptionConvertible>(_ type: E.Type) -> E {
    return E(cppException: DjinniError("client"))
}

func useTheApi() throws {
    let item = SwiftCxxFreeItem(id: "item", color: .red, options: [.loud])
    _ = colorName(item.color)
    let listener = Listener()
    _ = try listener.next(1)
    _ = asConvertible(SwiftCxxFreeFailure.self).code
    _ = pending().label
    _ = SwiftCxxFreeOptions.loud
}
