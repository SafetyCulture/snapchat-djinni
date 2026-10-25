import Dispatch
@testable import DjinniSupport
import DjinniSupportCxx
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

final class Doubler: RuntimeListener, @unchecked Sendable {
    private let lock = NSLock()
    // The label of the queue that ran the last onValue call.
    private var label = ""
    var queueLabel: String { lock.lock(); defer { lock.unlock() }; return label }
    init() { State.liveListeners.add(1) }
    deinit { State.liveListeners.add(-1) }
    func onValue(_ value: Int32) throws -> Int32 {
        lock.lock()
        label = String(cString: __dispatch_queue_get_label(nil))
        lock.unlock()
        return value * 2
    }
    func delayedFuture(_ value: Int32, millis: Int32) throws -> DJFuture<Int32> {
        return DJFuture<Int32> { promise in
            DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(Int(millis))) { promise(.success(value)) }
        }
    }
    func makeData() throws -> NSData { Data((0..<256).map { UInt8($0) }) as NSData }
    func onFail() throws -> Int32 { throw HostFailure.boom }
    func onMaybe(_ flag: Bool) throws -> Result<Int32?, RuntimeError> { .success(flag ? 42 : nil) }
}

enum HostFailure: Error {
    case boom
}

final class ErrorRecorder: ErrorListener, @unchecked Sendable {
    func onDone(_ value: Int32) throws -> Int32 { return value + 1 }
}

func check(_ condition: Bool, _ message: String) {
    if !condition {
        print("FAIL: \(message)")
        exit(1)
    }
}

func runTests() throws {
    let service = try RuntimeService_statics.create()
    try runSafetyCases(service)
    if onlyCase != nil { return }
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
    do {
        check(try service.listenerMaybe(Doubler(), flag: false) == -2, "listenerMaybe(false) is a nil success")
        check(try service.listenerMaybe(Doubler(), flag: true) == 42, "listenerMaybe(true) carries the value")
    } catch {
        check(false, "listenerMaybe threw: \(error)")
    }

    // A date keeps one millisecond across the boundary; 2 ms tells rounding from truncation
    let epochMs = Date(timeIntervalSince1970: 0.002)
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

// RT_CASE=<name> runs one runtime safety case and nothing else. Without it, every case runs.
let onlyCase = ProcessInfo.processInfo.environment["RT_CASE"]
func enabled(_ name: String) -> Bool { onlyCase == nil || onlyCase == name }

// Two protocols with one name, as in two Swift modules
enum FirstModule { protocol Listener: AnyObject {} }
enum SecondModule { protocol Listener: AnyObject {} }
final class BothListeners: FirstModule.Listener, SecondModule.Listener {}

// A cache entry whose release takes the cache lock, as every CppProxy does
final class DropProbe {
    private let key: UnsafeRawPointer
    init(_ key: UnsafeRawPointer) { self.key = key }
    deinit { CppProxyCache.shared.removeIfExpired(key) }
}

struct TimeoutError: Error {}

// Runs the body and gives its result, or throws TimeoutError when it does not finish. A wait on a future is cancellable.
func withTimeout<T: Sendable>(_ seconds: Double, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await body() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw TimeoutError() }
        return first
    }
}

// The thread limit of the global queues of libdispatch.
func constrainedThreadLimit() -> Int {
    var value: Int32 = 0
    var size = MemoryLayout<Int32>.size
    return sysctlbyname("kern.wq_max_constrained_threads", &value, &size, nil, 0) == 0 ? Int(value) : 64
}

// Waits for a task. A cancel of the caller reaches the task, so a timeout ends the wait.
func taskValue<T: Sendable>(of task: Task<T, Error>) async throws -> T {
    try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
}

func waitForPendingCalls(_ service: RuntimeAsync, _ count: Int32) async throws {
    try await withTimeout(10) {
        while try await service.pendingStarted() < count {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

func runSafetyCases(_ service: RuntimeService) throws {
    // A null C++ interface for an interface that is not optional throws instead of trapping
    if enabled("null_service") {
        do {
            _ = try RuntimeService_statics.nullService()
            check(false, "a null C++ interface must throw")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("non-optional interface"), "null interface error: \(error.errorMessage)")
        }
        // The Swift guards, without the C++ check: a null interface value goes straight to each marshaller
        let nullInterface = djinni.swift.strongify(djinni.swift.WeakSwiftProxy())
        do {
            _ = try RuntimeServiceMarshaller.fromCpp(nullInterface)
            check(false, "a null interface must throw in cppInterfaceToSwift")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("non-optional interface"), "null interface error: \(error.errorMessage)")
        }
        do {
            _ = try RuntimeAsyncMarshaller.fromCpp(nullInterface)
            check(false, "a null interface must throw in cppWrapperToSwift")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("non-optional interface"), "null interface error: \(error.errorMessage)")
        }
    }

    // A string that is not valid UTF-8 throws, and a leading byte order mark stays
    if enabled("utf8") {
        do {
            let value = try service.invalidString()
            check(false, "invalid UTF-8 must throw, got \(value)")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("UTF-8"), "invalid UTF-8 error: \(error.errorMessage)")
        }
        let bom = try service.bomString()
        check(bom.utf8.count == 6 && bom.unicodeScalars.first == "\u{FEFF}", "the byte order mark stays: \(Array(bom.utf8))")
    }

    // A conversion that throws does not leak the reference of a DataRef, in both directions
    if enabled("data_ref_leak") {
        let before = try service.keptDataRetainCount()
        for _ in 0..<10 {
            do {
                _ = try service.badBlob()
                check(false, "badBlob must throw")
            } catch is DjinniError {}
        }
        let after = try service.keptDataRetainCount()
        check(after == before, "C++ to Swift: a failed conversion leaked \(after - before) references of a DataRef")

        for payload in [NSData(data: Data(repeating: 3, count: 64)), NSMutableData(data: Data(repeating: 3, count: 64))] {
            let retained = CFGetRetainCount(payload)
            for _ in 0..<10 {
                // The value is dropped without C++ that converts it, as when a later conversion of the call throws
                _ = try DataRefMarshaller.toCpp(payload)
            }
            let now = CFGetRetainCount(payload)
            check(now == retained, "Swift to C++: a dropped value leaked \(now - retained) references of a DataRef")
        }
    }

    // C++ values of the wrong kind, or with too few members, throw DjinniError in every helper that Swift calls
    if enabled("boundary") {
        var composite = djinni.swift.makeCompositeValue()
        djinni.swift.addMember(&composite, djinni.swift.I32.fromCpp(7))
        try withUnsafePointer(to: composite) { p in
            check(try compositeSize(p) == 1, "size of a composite")
            check(djinni.swift.I32.toCpp(try compositeMember(p, 0)) == 7, "member of a composite")
            do {
                _ = try compositeMember(p, 5)
                check(false, "a member out of range must throw")
            } catch let error as DjinniError {
                check(error.errorMessage.contains("member 5"), "member out of range: \(error.errorMessage)")
            }
        }
        let scalar = djinni.swift.I32.fromCpp(1)
        withUnsafePointer(to: scalar) { p in
            do { _ = try compositeSize(p); check(false, "the size of a scalar must throw") } catch is DjinniError {} catch { check(false, "\(error)") }
            do { _ = try compositeMember(p, 0); check(false, "a member of a scalar must throw") } catch is DjinniError {} catch { check(false, "\(error)") }
            do { _ = try interfaceInfo(p); check(false, "the interface info of a scalar must throw") } catch is DjinniError {} catch { check(false, "\(error)") }
            check(String(djinni.swift.getError(p).msg).contains("not an error"), "the error of a value that is not an error")
        }
        do { _ = try binaryRange(scalar); check(false, "the range of a scalar must throw") } catch is DjinniError {} catch { check(false, "\(error)") }
        // A member cannot be added to a value that is not a composite
        var notComposite = djinni.swift.I32.fromCpp(1)
        do { try addMember(&notComposite, djinni.swift.makeVoidValue()); check(false, "addMember on a scalar must throw") } catch is DjinniError {} catch { check(false, "\(error)") }
        // A scalar of the wrong kind is malformed too. Swift used to abort the process in std::get.
        let text = djinni.swift.makeStringValue("x", 1)
        do { _ = try I32Marshaller.fromCpp(text); check(false, "a string is not an i32") } catch is DjinniError {} catch { check(false, "\(error)") }
        do { _ = try I64Marshaller.fromCpp(scalar); check(false, "an i32 value is not an i64") } catch is DjinniError {} catch { check(false, "\(error)") }
        do { _ = try F64Marshaller.fromCpp(text); check(false, "a string is not a double") } catch is DjinniError {} catch { check(false, "\(error)") }
        do { _ = try BoolMarshaller.fromCpp(text); check(false, "a string is not a bool") } catch is DjinniError {} catch { check(false, "\(error)") }
        do { _ = try EnumMarshaller<RuntimeColor>.fromCpp(text); check(false, "a string is not an enum") } catch is DjinniError {} catch { check(false, "\(error)") }
        // An outcome with no members is malformed. Swift used to abort the process here.
        do {
            _ = try OutcomeMarshaller<I32Marshaller, RuntimeErrorMarshaller>.fromCpp(djinni.swift.makeCompositeValue())
            check(false, "a malformed outcome must throw")
        } catch is DjinniError {}
        // A map with an odd number of members is malformed
        do {
            _ = try MapMarshaller<I32Marshaller, I32Marshaller>.fromCpp(composite)
            check(false, "a map with an odd number of members must throw")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("odd number"), "odd map error: \(error.errorMessage)")
        }
    }

    // Two protocols with the same name do not share a proxy
    if enabled("interface_key") {
        let both = BothListeners()
        check(String(describing: (any FirstModule.Listener).self) == String(describing: (any SecondModule.Listener).self),
              "the two protocols have the same name")
        let first = ProtocolWrapperContext<any FirstModule.Listener>(inst: both, vtbl: [])
        let second = ProtocolWrapperContext<any SecondModule.Listener>(inst: both, vtbl: [])
        check(first.interface != second.interface, "the proxy cache key tells two protocols with one name apart")
        let firstProxy = try swiftInterfaceToCpp(both as any FirstModule.Listener) { try RuntimeListenerMarshaller.toCpp(Doubler()) }
        let secondProxy = try swiftInterfaceToCpp(both as any SecondModule.Listener) { try RuntimeListenerMarshaller.toCpp(Doubler()) }
        withUnsafePointer(to: firstProxy) { p in
            withUnsafePointer(to: secondProxy) { q in
                check(djinni.swift.getInterfaceInfo(p).cppPointer != djinni.swift.getInterfaceInfo(q).cppPointer,
                      "one object, two protocols with one name: each protocol gets its own proxy")
            }
        }
    }

    // A create function that throws after it built a proxy does not deadlock on the cache lock
    if enabled("cache_lock") {
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: 1)
        defer { storage.deallocate() }
        let key = UncheckedSendable(UnsafeRawPointer(storage))
        let finished = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            do {
                _ = try CppProxyCache.shared.getOrCreate(key.value) {
                    let probe = DropProbe(key.value)
                    _ = probe
                    throw HostFailure.boom
                }
            } catch {}
            finished.signal()
        }
        check(finished.wait(timeout: .now() + 10) == .success, "getOrCreate deadlocks when create throws after it built a proxy")
    }

    // The message of the C++ exception shows in logs and in localizedDescription
    if enabled("error_description") {
        let error = DjinniError("boom detail")
        check("\(error)".contains("boom detail"), "description of a DjinniError: \(error)")
        check(error.localizedDescription == "boom detail", "localizedDescription of a DjinniError: \(error.localizedDescription)")
    }
}

func runAsyncSafetyCases(_ service: RuntimeAsync) async throws {
    // The future of a promise that C++ drops fails. The await does not wait for ever.
    if enabled("dropped_promise") {
        do {
            _ = try await withTimeout(10) { try await service.dropped() }
            check(false, "a dropped promise must fail the future")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("broken promise"), "dropped promise error: \(error.errorMessage)")
        } catch is TimeoutError {
            check(false, "the await of a dropped promise does not return")
        }
    }

    // A second call before complete_pending replaces the promise of the first call. The first call fails, and the second works.
    if enabled("pending_overwrite") {
        // C++ counts the calls of pending(), so the order of the two calls does not depend on a sleep
        let calls = try await service.pendingStarted()
        let firstCall = Task { try await service.pending() }
        try await waitForPendingCalls(service, calls + 1)
        let secondCall = Task { try await service.pending() }
        try await waitForPendingCalls(service, calls + 2)
        do {
            _ = try await withTimeout(10) { try await taskValue(of: firstCall) }
            check(false, "the first call must fail when a second call replaces its promise")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("broken promise"), "replaced promise error: \(error.errorMessage)")
        } catch is TimeoutError {
            check(false, "the first call waits for ever when a second call replaces its promise")
        }
        try await service.completePending(7)
        let value = try await withTimeout(10) { try await taskValue(of: secondCall) }
        check(value == 7, "the second call completes: \(value)")
    }

    // A handler on the future of a Swift host throws an exception outside std::exception. The caller gets it.
    if enabled("future_chain") {
        let message = try await withTimeout(10) { try await service.describeFutureFailure(Doubler()) }
        check(message == "int 42", "C++ catches the exception of the handler: \(message)")
    }

    // A promise that is called twice keeps its first result and does not stop the process
    // The value of a C++ future that Swift cannot convert fails the future with a DjinniError that names the type
    if enabled("future_value") {
        do {
            _ = try await withTimeout(10) { try await service.badColorFuture() }
            check(false, "an unknown enum value in a future must fail the future")
        } catch let error as DjinniError {
            check(error.errorMessage.contains("RuntimeColor"), "future value error names the type: \(error.errorMessage)")
        } catch is TimeoutError {
            check(false, "the future of a value that cannot be converted never completes")
        }
    }

    if enabled("double_fulfil") {
        let twice = DJFuture<Int32> { promise in
            promise(.success(1))
            promise(.success(2))
        }
        let value = try await twice.value
        check(value == 1, "the first result of a future stays: \(value)")
    }
}

func runAsyncTests() async throws {
    let service = try RuntimeAsync_statics.create()
    try await runAsyncSafetyCases(service)
    if onlyCase != nil { return }
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

    try await runTypedErrorTests()
    try runSyncTypedErrorTests()

    // A Swift listener throws, C++ catches the exception and returns its message.
    let hostMessage = try await service.describeListenerFailure(Doubler())
    check(hostMessage.contains("boom"), "C++ message of a Swift error: \(hostMessage)")

    // A legacy record (--swift-legacy-records) crosses the C++ boundary in both directions.
    let legacy = try LegacyService_statics.create()
    var input = LegacyPoint(x: 3, y: -4)
    input.y = 5
    let point = try await legacy.echo(input)
    check(point.x == 3 && point.y == 5, "legacy record round trip")

    // One C++ object has one wrapper. Calls to the object run at the same time on the queue of the wrappers.
    let first = try RuntimeAsync_statics.shared()
    let second = try RuntimeAsync_statics.shared()
    check(first === second, "the same C++ object has one wrapper")
    check(try await first.same() === first, "a C++ object that returns itself has one wrapper")
    try await withThrowingTaskGroup(of: Void.self) { group in
        for i in 0..<40 {
            group.addTask { try await (i % 2 == 0 ? first : second).busy(20) }
        }
        try await group.waitForAll()
    }
    let maxConcurrent = try await first.maxConcurrent()
    check(maxConcurrent > 1, "calls to one C++ object run one at a time: \(maxConcurrent)")
    let listener = Doubler()
    check(try await first.callListener(listener, value: 4) == 8, "callListener through the wrapper")
    let expectedLabel = ProcessInfo.processInfo.environment["RT_QUEUE_LABEL"] ?? "djinni.runtime.blocking"
    check(listener.queueLabel == expectedLabel, "the C++ call runs on \(listener.queueLabel), not on \(expectedLabel)")

    // --swift-sync-method: the synchronous form registers the listener and runs the C++ call on the caller's thread.
    let callerThread = Int64(pthread_mach_thread_np(pthread_self()))
    let registeredListener = Doubler()
    check(try first.registerListenerNow(registeredListener) == 1, "the synchronous registration returns the count")
    let registrationThread = try await first.registrationThread()
    check(registrationThread == callerThread, "the synchronous registration ran on thread \(registrationThread), not on \(callerThread)")
    check(try await first.callRegisteredListener(21) == 42, "the synchronous registration stored the listener")
    // A future method with a +sw parameter that is not listed keeps the async form.
    check(try await first.observe(Doubler()) == 2, "observe runs through the async form")

    // A call to an object does not wait for a blocking call on the same object, as cancel() must not.
    let blocking = Task { try await first.busy(3000) }
    try await Task.sleep(nanoseconds: 200_000_000)
    let start = DispatchTime.now().uptimeNanoseconds
    check(try await first.add(1, b: 1) == 2, "add while the object is busy")
    let elapsedMs = (DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    check(elapsedMs < 1500, "a call waits for a blocking call on the same object: \(elapsedMs) ms")
    try await blocking.value

    // Each C++ call waits for a Swift future that DispatchQueue.global() completes. More calls than the global queues
    // have threads must not stop those queues.
    if ProcessInfo.processInfo.environment["RT_DEFAULT_QUEUE"] == "1" {
        let calls = constrainedThreadLimit() + 8
        let finished = Counter()
        for _ in 0..<calls {
            Task {
                if (try? await service.describeFutureFailure(Doubler())) == "int 42" { finished.add(1) }
            }
        }
        let deadline = DispatchTime.now().uptimeNanoseconds + 60_000_000_000
        while finished.value < calls && DispatchTime.now().uptimeNanoseconds < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        check(finished.value == calls, "blocking calls stop the global queues: \(finished.value) of \(calls) calls ended in 60 s")
    }

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

    // A task that is cancelled before the call throws at once and does not call C++.
    let startedBefore = try await service.pendingStarted()
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
    let startedAfter = try await service.pendingStarted()
    check(startedAfter == startedBefore, "a task that is cancelled before the call calls C++: \(startedBefore) -> \(startedAfter)")

    // The future of a completed call still delivers its value after another task was cancelled.
    check(try await service.delayed(9, millis: 10) == 9, "future after cancellation")
}

// Checks that a call throws CruxError with the code, and with the text in the message.
func expectCruxError(_ name: String, code: Int32, message: String? = nil, _ call: () async throws(CruxError) -> Void) async {
    do throws(CruxError) {
        try await call()
        check(false, "\(name) must throw CruxError")
    } catch {
        check(error.code == code, "\(name): code \(error.code), expected \(code) (\(error.message))")
        if let message {
            check(error.message.contains(message), "\(name): message \(error.message)")
        }
    }
}

// The value of a task that throws only CruxError.
func typedValue<T>(_ task: Task<T, any Error>) async throws(CruxError) -> T {
    do {
        return try await task.value
    } catch let error as CruxError {
        throw error
    } catch {
        check(false, "the task threw \(error), not CruxError")
        exit(1)
    }
}

// The methods of an interface with +c throw CruxError of --swift-error-type, also the static methods.
func runTypedErrorTests() async throws {
    let errors = try ErrorService_statics.create()

    // Success
    check(try await errors.add(2, b: 3) == 5, "plain method with the error type")
    check(try await errors.divide(8, b: 2) == 4, "outcome method with the error type")
    check(try await errors.delayed(7, millis: 10) == 7, "future method with the error type")
    check(try await errors.divideLater(8, b: 2) == 4, "future of an outcome with the error type")
    check(try await ErrorService_statics.delayedStatic(6) == 6, "static future with the error type")

    // The error of an outcome is thrown as it is, also from a future.
    await expectCruxError("outcome error", code: 7, message: "division by zero") { () async throws(CruxError) in _ = try await errors.divide(1, b: 0) }
    await expectCruxError("outcome error of a future", code: 7, message: "division by zero") { () async throws(CruxError) in _ = try await errors.divideLater(1, b: 0) }

    // --swift-sync-method with --swift-error-type: the form throws CruxError, and the C++ call runs on the caller's thread.
    let callerThread = Int64(pthread_mach_thread_np(pthread_self()))
    let registeredListener = ErrorRecorder()
    check(try errors.registerListenerNow(registeredListener) == 1, "the synchronous registration with the error type returns the count")
    let registrationThread = try await errors.registrationThread()
    check(registrationThread == callerThread, "the synchronous registration with the error type ran on another thread")
    check(try await errors.callRegisteredListener(41) == 42, "the synchronous registration with the error type stored the listener")
    do throws(CruxError) {
        _ = try errors.registerListenerFailingNow(registeredListener)
        check(false, "registerListenerFailingNow must throw CruxError")
    } catch {
        check(error.code == -1 && error.message.contains("boom"), "C++ exception of the synchronous form: code \(error.code), message \(error.message)")
    }

    // A C++ exception becomes init(cppException:).
    await expectCruxError("C++ exception of an outcome method", code: -1, message: "boom") { () async throws(CruxError) in _ = try await errors.fail() }
    await expectCruxError("C++ exception of a plain method", code: -1, message: "boom") { () async throws(CruxError) in _ = try await errors.failPlain() }
    await expectCruxError("C++ exception of a void method", code: -1, message: "boom") { () async throws(CruxError) in try await errors.failVoid() }
    await expectCruxError("C++ exception before the future", code: -1, message: "boom") { () async throws(CruxError) in _ = try await errors.throwFuture() }
    await expectCruxError("rejected future", code: -1, message: "failed future") { () async throws(CruxError) in _ = try await errors.failFuture() }
    await expectCruxError("C++ exception of a static method", code: -1, message: "boom") { () async throws(CruxError) in _ = try ErrorService_statics.failStatic() }

    // A promise that C++ drops becomes init(cppException:).
    await expectCruxError("dropped promise", code: -1, message: "broken promise") { () async throws(CruxError) in _ = try await errors.dropped() }

    // A task that is cancelled before the call throws init(cancellation:) and does not call C++.
    let startedBefore = try await errors.pendingStarted()
    let early = Task { () async throws(CruxError) -> Int32 in
        while !Task.isCancelled { await Task.yield() }
        return try await errors.pending()
    }
    early.cancel()
    await expectCruxError("cancellation before the call", code: -2) { () async throws(CruxError) in _ = try await typedValue(early) }
    let startedAfter = try await errors.pendingStarted()
    check(startedAfter == startedBefore, "a cancelled task called C++: \(startedBefore) -> \(startedAfter)")

    // A method without a future that is cancelled before the call throws init(cancellation:) and does not call C++.
    let touchedBefore = try await errors.touchCount()
    let earlyPlain = Task { () async throws(CruxError) -> Int32 in
        while !Task.isCancelled { await Task.yield() }
        return try await errors.touch()
    }
    earlyPlain.cancel()
    await expectCruxError("cancellation before the call of a plain method", code: -2) { () async throws(CruxError) in _ = try await typedValue(earlyPlain) }
    let touchedAfter = try await errors.touchCount()
    check(touchedAfter == touchedBefore, "a cancelled task called C++ through a plain method: \(touchedBefore) -> \(touchedAfter)")

    // A task that is cancelled while it waits for a future throws init(cancellation:) once. The late value is dropped.
    let waiting = Task { () async throws(CruxError) -> Int32 in try await errors.pending() }
    while try await errors.pendingStarted() == startedAfter { await Task.yield() }
    // The pause lets the task reach the wait for the future before the cancel.
    try await Task.sleep(nanoseconds: 100_000_000)
    waiting.cancel()
    await expectCruxError("cancellation while waiting", code: -2) { () async throws(CruxError) in _ = try await typedValue(waiting) }
    try await errors.completePending(1)
    check(try await errors.divide(9, b: 3) == 3, "the typed wrapper works after a cancellation")
}

// Without --swift-async-wrap the protocol and static methods throw SyncError synchronously.
func runSyncTypedErrorTests() throws {
    let errors = try SyncErrorService_statics.create()
    check(try errors.add(1, b: 2) == 3, "plain method of the protocol with the error type")
    check(try errors.divide(6, b: 3) == 2, "outcome method of the protocol with the error type")
    let calls: [(String, Int32, () throws(SyncError) -> Void)] = [
        ("outcome error", 7, { () throws(SyncError) in _ = try errors.divide(1, b: 0) }),
        ("C++ exception of a plain method", -1, { () throws(SyncError) in _ = try errors.fail() }),
        ("C++ exception of a void method", -1, { () throws(SyncError) in try errors.failVoid() }),
        ("C++ exception of a static method", -1, { () throws(SyncError) in _ = try SyncErrorService_statics.failStatic() }),
    ]
    for (name, code, call) in calls {
        do throws(SyncError) {
            try call()
            check(false, "\(name) must throw SyncError")
        } catch {
            check(error.code == code, "\(name): code \(error.code), expected \(code) (\(error.message))")
        }
    }
}

// The error types of --swift-error-type hold the C++ exception as a message, and a cancellation as code -2.
extension CruxError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }
    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}

extension SyncError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }
    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}

// The queue of --swift-async-queue in the run of runtime.djinni.
enum RuntimeQueues {
    static let blocking = DispatchQueue(label: "djinni.runtime.blocking", attributes: .concurrent)
}

// A deadlock fails the test. The watchdog has its own thread, so it does not need a free worker of libdispatch.
Thread.detachNewThread {
    Thread.sleep(forTimeInterval: 180)
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
