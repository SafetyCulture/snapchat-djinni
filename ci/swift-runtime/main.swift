import Dispatch
import Foundation

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func add(_ delta: Int) { lock.lock(); count += delta; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
}

enum State {
    static let liveListeners = Counter()
}

final class Doubler: RuntimeListener {
    init() { State.liveListeners.add(1) }
    deinit { State.liveListeners.add(-1) }
    func onValue(_ value: Int32) throws -> Int32 { value * 2 }
    func makeData() throws -> NSData { Data((0..<256).map { UInt8($0) }) as NSData }
}

func check(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

func runTests() throws {
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

    // The C++ object keeps a Swift object, and Swift gives that object to C++ again.
    let keptAgain = Doubler()
    try service.keepListener(keptAgain)
    check(try service.callListener(keptAgain, value: 4) == 8, "callListener with the kept listener")
    check(try service.callKeptListener(6) == 12, "callKeptListener with the same listener")

    // A DataRef argument keeps its retain count: C++ takes the reference that Swift gives and releases it.
    for payload in [NSData(data: Data(repeating: 7, count: 4096)), NSMutableData(data: Data(repeating: 7, count: 4096))] {
        let before = CFGetRetainCount(payload)
        for _ in 0..<10 {
            check(try service.dataSize(payload) == 4096, "dataSize")
        }
        check(CFGetRetainCount(payload) == before, "retain count of a DataRef argument: \(before) before, \(CFGetRetainCount(payload)) after")
    }

    // A Swift host returns a DataRef. C++ reads it while it is alive.
    for _ in 0..<10 {
        check(try service.listenerDataSum(Doubler()) == 32640, "listenerDataSum")
    }

    // Many threads create, pass and release host objects.
    DispatchQueue.concurrentPerform(iterations: 2000) { i in
        do {
            let proxy = try service.sameService()
            check(proxy === service, "proxy identity under concurrency")
            check(try proxy.callListener(Doubler(), value: Int32(i)) == Int32(i) * 2, "callListener under concurrency")
        } catch {
            check(false, "unexpected error \(error)")
        }
    }

    // A C++ singleton that lives forever. Swift gets its proxy and drops it on many threads, so proxies die and return.
    DispatchQueue.concurrentPerform(iterations: 200_000) { i in
        do {
            let proxy = try RuntimeService_statics.shared()
            if i % 64 == 0 {
                check(try proxy.add(1, b: 2) == 3, "add on the singleton")
            }
        } catch {
            check(false, "unexpected error \(error)")
        }
    }

    // One Swift object goes to C++ from many threads, and C++ does not keep it.
    do {
        let shared = Doubler()
        DispatchQueue.concurrentPerform(iterations: 20_000) { i in
            do {
                check(try service.callListener(shared, value: Int32(i % 1000)) == Int32(i % 1000) * 2, "shared listener")
            } catch {
                check(false, "unexpected error \(error)")
            }
        }
    }

    // Only the listener that C++ keeps is alive. C++ released every other host object.
    check(State.liveListeners.value == 1, "live listeners: \(State.liveListeners.value), expected 1")
    withExtendedLifetime(service) {}
}

// A deadlock fails the test.
DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
    print("FAIL: watchdog timeout, the runtime may be deadlocked")
    exit(3)
}

try runTests()
print("SWIFT RUNTIME OK")
