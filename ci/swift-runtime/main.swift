import Dispatch
import DjinniSupport
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
    func onFail() throws -> Int32 { throw HostFailure.boom }
    func onMaybe(_ flag: Bool) throws -> Result<Int32?, RuntimeError> { .success(flag ? 42 : nil) }
}

enum HostFailure: Error {
    case boom
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

    // nil success of outcome<optional<i32>> decodes as success in both directions
    switch try service.maybe(false) {
    case .success(let value): check(value == nil, "maybe(false) is a nil success")
    case .failure(let error): check(false, "maybe(false) failed: \(error)")
    }
    switch try service.maybe(true) {
    case .success(let value): check(value == 42, "maybe(true) carries the value")
    case .failure(let error): check(false, "maybe(true) failed: \(error)")
    }

    // nil success from the Swift host reads as success on the C++ side
    check(try service.listenerMaybe(Doubler(), flag: false) == -2, "listenerMaybe(false) is a nil success")
    check(try service.listenerMaybe(Doubler(), flag: true) == 42, "listenerMaybe(true) carries the value")

    // A date keeps one millisecond across the boundary
    let epochMs = Date(timeIntervalSince1970: 1_700_000_000.001)
    check(try service.dateRoundtrip(epochMs) == epochMs, "date round trip keeps 1 ms")

    // A date outside the millisecond range throws instead of trapping
    do {
        _ = try service.dateRoundtrip(Date(timeIntervalSince1970: .infinity))
        check(false, "an out-of-range date must throw")
    } catch let error as DjinniError {
        check(error.errorMessage.contains("Date out of range"), "date range error: \(error.errorMessage)")
    }

    // An enum value that Swift does not know throws instead of trapping
    do {
        _ = try service.unknownColor()
        check(false, "unknown enum value must throw")
    } catch let error as DjinniError {
        check(error.errorMessage.contains("RuntimeColor"), "unknown enum error names the type: \(error.errorMessage)")
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

func expectCppException(_ name: String, _ call: () async throws -> Void) async {
    do {
        try await call()
        check(false, "\(name) must throw")
    } catch let error as DjinniError {
        check(error.errorMessage.contains("boom"), "DjinniError message of the \(name): \(error.errorMessage)")
    } catch {
        check(false, "\(name) must throw DjinniError, not \(error)")
    }
}

func runAsyncTests() async throws {
    let service = try RuntimeAsync_statics.create()
    check(try await service.add(2, b: 3) == 5, "async add")

    // An outcome error is thrown as its own type.
    check(try await service.divide(10, b: 2) == 5, "async divide")
    do {
        _ = try await service.divide(1, b: 0)
        check(false, "divide by zero must fail")
    } catch let error as RuntimeError {
        check(error.code == 1 && error.message == "division by zero", "error of an outcome")
    }

    // A C++ exception is an error of the call. It does not stop the process.
    await expectCppException("plain method") { _ = try await service.fail() }
    await expectCppException("void method") { try await service.failVoid() }
    await expectCppException("outcome method") { _ = try await service.failOutcome() }
    do {
        _ = try await service.failUnknown()
        check(false, "failUnknown must throw")
    } catch let error as DjinniError {
        check(error.errorMessage.contains("unknown C++ exception"), "DjinniError message of an unknown exception: \(error.errorMessage)")
    }
    check(try await service.add(1, b: 1) == 2, "the wrapper works after a C++ exception")

    // The error record of --swift-error-type conforms to Error without deriving(error).
    let errors = try ErrorService_statics.create()
    check(try await errors.divide(8, b: 2) == 4, "divide with the error type")
    do throws(CruxError) {
        _ = try await errors.divide(1, b: 0)
        check(false, "divide by zero must fail with CruxError")
    } catch {
        check(error.code == 7 && error.message == "division by zero", "CruxError from the wrapper")
    }

    // With --swift-error-type, a C++ exception is a CruxError of CppExceptionConvertible.
    do throws(CruxError) {
        _ = try await errors.fail()
        check(false, "fail must throw CruxError")
    } catch {
        check(error.code == -1 && error.message.contains("boom"), "CruxError of a C++ exception: \(error.message)")
    }
    check(try await errors.divide(9, b: 3) == 3, "the typed wrapper works after a C++ exception")

    // A Swift listener throws, C++ catches the exception and returns its message.
    let hostMessage = try await service.describeListenerFailure(Doubler())
    check(hostMessage.contains("boom"), "C++ message of a Swift error: \(hostMessage)")

    // A legacy record (--swift-legacy-records) crosses the C++ boundary in both directions.
    let legacy = try LegacyService_statics.create()
    var input = LegacyPoint(x: 3, y: -4)
    input.y = 5
    let point = try await legacy.echo(input)
    check(point.x == 3 && point.y == 5, "legacy record round trip")

    // One C++ object has one wrapper, and the wrapper serialises the calls to the object.
    let first = try RuntimeAsync_statics.shared()
    let second = try RuntimeAsync_statics.shared()
    check(first === second, "the same C++ object has one wrapper")
    check(try await first.same() === first, "a C++ object that returns itself has one wrapper")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<40 {
            group.addTask { try await (i % 2 == 0 ? first : second).busy(5) }
        }
        try await group.waitForAll()
    }
    let maxConcurrent = try await first.maxConcurrent()
    check(maxConcurrent == 1, "calls to one C++ object interleave: \(maxConcurrent)")

    // A C++ exception before a future exists is a DjinniError.
    do {
        _ = try await service.failFuture()
        check(false, "failFuture must throw")
    } catch let error as DjinniError {
        check(error.errorMessage.contains("boom"), "DjinniError message: \(error.errorMessage)")
    } catch {
        check(false, "failFuture must throw DjinniError, not \(error)")
    }

    // A future maps to async.
    check(try await service.delayed(7, millis: 50) == 7, "async future")

    // Many tasks use one wrapper.
    let sum = try await withThrowingTaskGroup(of: Int32.self) { group in
        for i in 0..<500 {
            group.addTask { try await service.add(Int32(i), b: 1) }
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
    try await service.completePending(1)

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
    try await service.completePending(2)

    // The future of a completed call still delivers its value after another task was cancelled.
    check(try await service.delayed(9, millis: 10) == 9, "future after cancellation")
}

// The error type of --swift-error-type holds the C++ exception as a message.
extension CruxError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }
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
