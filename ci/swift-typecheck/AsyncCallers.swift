import DjinniSupport
import Foundation

// Callers of the async wrappers on the main actor. A value that is not Sendable comes back from a wrapper method.

@MainActor
func djinniMainActorCaller(_ service: SwiftAsyncService) async throws -> Int {
    let data = try await service.loadData()
    let item = try await service.load("id")
    try await service.send(data, tags: [item.id])
    return data.length
}

actor DjinniActorCaller {
    func call(_ service: SwiftAsyncService) async throws -> Int {
        let data = try await service.loadData()
        return data.length
    }
}
