// Checks djinni::Future and djinni::Promise: a dropped promise, a promise that moves, a replaced handler, and handlers
// that throw exceptions which do not derive from std::exception. Build and run with ci/cpp-future-test.sh.
#include "Future.hpp"

#include <atomic>
#include <chrono>
#include <memory>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>

namespace {

int failures = 0;

void check(bool condition, const std::string& message) {
    if (!condition) {
        std::printf("FAIL: %s\n", message.c_str());
        failures++;
    }
}

// Waits for a future for at most 10 s. A regression that leaves a future without a result fails here, and does not hang.
template <typename F>
void waitReady(F& future, const std::string& what) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (!future.isReady()) {
        if (std::chrono::steady_clock::now() > deadline) {
            std::printf("FAIL: %s: the future has no result after 10 s\n", what.c_str());
            std::exit(EXIT_FAILURE);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
}

// Runs `scenario` on its own thread. A deadlock fails the test after 10 s, and does not hang it.
template <typename F>
void runWithin(F scenario, const std::string& what) {
    auto done = std::make_shared<std::atomic<bool>>(false);
    std::thread([scenario, done]() mutable {
        scenario();
        done->store(true);
    }).detach();
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (!done->load()) {
        if (std::chrono::steady_clock::now() > deadline) {
            std::printf("FAIL: %s: no end after 10 s, it may be deadlocked\n", what.c_str());
            std::exit(EXIT_FAILURE);
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }
}

} // namespace

int main() {
    // A promise that is destroyed without a value breaks its future.
    {
        djinni::Future<int> future = [] {
            djinni::Promise<int> promise;
            return promise.getFuture();
        }();
        bool broken = false;
        waitReady(future, "a dropped promise");
        try {
            future.get();
        } catch (const djinni::BrokenPromiseException&) {
            broken = true;
        }
        check(broken, "a dropped promise breaks its future");
    }

    // The handler of a future runs when its promise is dropped, and the next future breaks too.
    {
        djinni::Promise<int> promise;
        auto next = promise.getFuture().then([](djinni::Future<int> f) {
            f.get();
            return 1;
        });
        { auto dropped = std::move(promise); }
        bool broken = false;
        waitReady(next, "the next future of a dropped promise");
        try {
            next.get();
        } catch (const djinni::BrokenPromiseException&) {
            broken = true;
        }
        check(broken, "a dropped promise runs the handler, and the next future breaks");
    }

    // A promise that moved completes once, and the moved-from promise does not break the future.
    {
        djinni::Promise<int> promise;
        auto future = promise.getFuture();
        auto moved = std::move(promise);
        moved.setValue(5);
        waitReady(future, "a moved promise");
        check(future.get() == 5, "a moved promise completes the future");
    }

    // A void promise breaks too.
    {
        djinni::Future<void> future = [] {
            djinni::Promise<void> promise;
            return promise.getFuture();
        }();
        bool broken = false;
        waitReady(future, "a dropped void promise");
        try {
            future.get();
        } catch (const djinni::BrokenPromiseException&) {
            broken = true;
        }
        check(broken, "a dropped void promise breaks its future");
    }

    // A handler that throws an exception outside std::exception. The next future gets it, and the completion of the
    // first promise does not throw or complete a promise twice.
    {
        djinni::Promise<int> promise;
        auto next = promise.getFuture().then([](djinni::Future<int> f) -> int {
            f.get();
            throw 42;
        });
        promise.setValue(1);
        int caught = 0;
        waitReady(next, "a handler that throws an int");
        try {
            next.get();
        } catch (int value) {
            caught = value;
        }
        check(caught == 42, "a handler that throws an int gives the int to the next future");
    }

    // A then() that replaces the handler of another future of the same promise destroys the old handler after the
    // unlock. The old handler breaks its next promise, and the handler of that next future can use the shared state.
    runWithin([] {
        djinni::Promise<int> promise;
        auto first = promise.getFuture();
        auto second = promise.getFuture();
        auto probe = promise.getFuture();
        bool ran = false;
        auto chained = first.then([](djinni::Future<int> f) { return f.get(); }).then([&probe, &ran](djinni::Future<int>) {
            ran = true;
            return probe.isReady();
        });
        second.then([](djinni::Future<int> f) { return f.get(); });
        check(ran, "the replaced handler breaks its next promise, and the handler of the next future runs");
        promise.setValue(1);
    }, "a then() that replaces a handler");

    if (failures == 0) {
        std::printf("CPP FUTURE OK\n");
    }
    return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
