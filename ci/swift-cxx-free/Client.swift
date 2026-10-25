import DjinniSupportCore
import TestSuite

// A client of the generated module without C++ interop. It imports no C++ module and names no C++ type.

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
