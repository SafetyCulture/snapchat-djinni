// A negative case for ci/swift-typecheck.sh. In Swift 6 strict mode this file must NOT compile to SIL.
//
// The NSData of a future<DataRef> is not Sendable. One task can take it from another, but two tasks must not use it at
// the same time. Swift 6 checks this with region-based isolation, which runs on SIL after the type checker, so
// `swiftc -typecheck` accepts this file. If the SIL check accepts it, the gate does not run the data-race checks.
import Foundation

func shareData(_ service: SwiftAsyncService) async throws {
    let data = try await service.loadData()
    Task.detached { _ = data.length }
    _ = data.length
}
