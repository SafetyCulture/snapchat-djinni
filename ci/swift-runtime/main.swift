import Dispatch
import Foundation

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add(_ delta: Int) { lock.lock(); count += delta; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}
let liveListeners = Counter()

final class Doubler: RuntimeListener {
    init() { liveListeners.add(1) }
    deinit { liveListeners.add(-1) }
    func onValue(_ value: Int32) throws -> Int32 { value * 2 }
}

func check(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

let service = try RuntimeService_statics.create()
check(try service.add(2, b: 3) == 5, "add")

// A Swift object that C++ calls back.
check(try service.callListener(Doubler(), value: 21) == 42, "callListener")

// The C++ object keeps a Swift object, and the Swift object stays alive.
do {
    let kept = Doubler()
    try service.keepListener(kept)
}
check(try service.callKeptListener(5) == 10, "callKeptListener")

// A C++ object that comes back from C++ is the same Swift proxy.
let again = try service.sameService()
check(again === service, "same proxy for the same C++ object")

// Many threads create, pass and release host objects and get the proxy of one C++ object.
DispatchQueue.concurrentPerform(iterations: 2000) { i in
    do {
        let proxy = try service.sameService()
        check(proxy === service, "proxy identity under concurrency")
        check(try proxy.callListener(Doubler(), value: Int32(i)) == Int32(i) * 2, "callListener under concurrency")
    } catch {
        check(false, "unexpected error \(error)")
    }
}
// Only the listener that C++ keeps is alive. C++ released every other host object.
check(liveListeners.value == 1, "live listeners: \(liveListeners.value), expected 1")
print("SWIFT RUNTIME OK")
