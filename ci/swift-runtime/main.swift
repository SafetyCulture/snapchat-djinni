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

func runAsyncTests() async throws {
    let service = try RuntimeAsync_statics.create()
    check(await service.add(2, b: 3) == 5, "async add")

    // An outcome is a typed error.
    check(try await service.divide(10, b: 2) == 5, "async divide")
    do throws(RuntimeError) {
        _ = try await service.divide(1, b: 0)
        check(false, "divide by zero must fail")
    } catch {
        check(error.code == 1 && error.message == "division by zero", "typed error of an outcome")
    }

    // One C++ object has one wrapper, and the wrapper serialises the calls to the object.
    let first = try RuntimeAsync_statics.shared()
    let second = try RuntimeAsync_statics.shared()
    check(first === second, "the same C++ object has one wrapper")
    check(await first.same() === first, "a C++ object that returns itself has one wrapper")
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<40 {
            group.addTask { await (i % 2 == 0 ? first : second).busy(5) }
        }
    }
    check(await first.maxConcurrent() == 1, "calls to one C++ object interleave: \(await first.maxConcurrent())")

    // A future maps to async.
    check(try await service.delayed(7, millis: 50) == 7, "async future")

    // Many tasks use one wrapper.
    let sum = try await withThrowingTaskGroup(of: Int32.self) { group in
        for i in 0..<500 {
            group.addTask { await service.add(Int32(i), b: 1) }
            group.addTask { try await service.delayed(Int32(i), millis: 1) }
        }
        var total: Int32 = 0
        for try await value in group { total += value }
        return total
    }
    check(sum == (0..<500).reduce(Int32(0)) { $0 + $1 + 1 + $1 }, "task group sum: \(sum)")

    // A cancelled task stops waiting for a future that does not complete.
    let waiting = Task { try await service.pending() }
    try await Task.sleep(nanoseconds: 100_000_000)
    waiting.cancel()
    do {
        _ = try await waiting.value
        check(false, "a cancelled task must throw")
    } catch is CancellationError {
    } catch {
        check(false, "a cancelled task must throw CancellationError, not \(error)")
    }
    await service.completePending(1)

    // A task that is cancelled before it waits throws at once.
    let early = Task {
        while !Task.isCancelled { await Task.yield() }
        return try await service.pending()
    }
    early.cancel()
    do {
        _ = try await early.value
        check(false, "an early cancelled task must throw")
    } catch is CancellationError {
    } catch {
        check(false, "an early cancelled task must throw CancellationError, not \(error)")
    }
    await service.completePending(2)

    // The future of a completed call still delivers its value after another task was cancelled.
    check(try await service.delayed(9, millis: 10) == 9, "future after cancellation")
}

// A deadlock fails the test.
DispatchQueue.global().asyncAfter(deadline: .now() + 180) {
    print("FAIL: watchdog timeout, the runtime may be deadlocked")
    exit(3)
}

try runTests()
Task {
    do {
        try await runAsyncTests()
    } catch {
        print("FAIL: async tests threw \(error)")
        exit(1)
    }
    print("SWIFT RUNTIME OK")
    exit(0)
}
dispatchMain()
