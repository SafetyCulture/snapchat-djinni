// A negative case for ci/swift-typecheck.sh. In Swift 6 strict mode this file must NOT typecheck.
//
// `Future.getResult` can run its closure on a global queue, so the closure must be `@Sendable`. This closure writes
// main-actor state. If a Swift 6 typecheck accepts the file, the closure is not `@Sendable`, and a caller can write
// main-actor state from a global queue with no diagnostic.
import DjinniSupport

@MainActor var counter = 0

@MainActor
func subscribe(_ future: DJFuture<Int32>) -> Cancellable {
    return future.getResult { _ in counter += 1 }
}
