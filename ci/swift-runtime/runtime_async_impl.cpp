#include "runtime_async.hpp"
#include "runtime_color.hpp"
#include "runtime_error.hpp"
#include "runtime_listener.hpp"

#include <atomic>
#include <chrono>
#include <memory>
#include <stdexcept>
#include <mutex>
#include <thread>

namespace {

class RuntimeAsyncImpl : public rt::RuntimeAsync, public std::enable_shared_from_this<RuntimeAsyncImpl> {
public:
    int32_t add(int32_t a, int32_t b) override { return a + b; }

    std::string describe_listener_failure(const std::shared_ptr<rt::RuntimeListener>& listener) override {
        try {
            listener->on_fail();
        } catch (const std::exception& e) {
            return e.what();
        }
        return "";
    }

    djinni::expected<int32_t, rt::RuntimeError> divide(int32_t a, int32_t b) override {
        if (b == 0) {
            return djinni::make_unexpected(rt::RuntimeError("division by zero", 1));
        }
        return a / b;
    }

    djinni::Future<int32_t> delayed(int32_t value, int32_t millis) override {
        djinni::Promise<int32_t> promise;
        auto future = promise.getFuture();
        std::thread([promise = std::move(promise), value, millis]() mutable {
            std::this_thread::sleep_for(std::chrono::milliseconds(millis));
            promise.setValue(value);
        }).detach();
        return future;
    }

    djinni::Future<int32_t> fail_future() override {
        throw std::runtime_error("boom");
    }

    int32_t fail() override { throw std::runtime_error("boom"); }

    void fail_void() override { throw std::runtime_error("boom"); }

    djinni::expected<int32_t, rt::RuntimeError> fail_outcome() override { throw std::runtime_error("boom"); }

    int32_t fail_unknown() override { throw 42; }

    // A second call before complete_pending replaces the promise of the first call. The first future breaks with
    // BrokenPromiseException instead of waiting for ever. The old promise is destroyed outside the lock, because
    // its handler runs when it is destroyed.
    djinni::Future<int32_t> pending() override {
        std::unique_ptr<djinni::Promise<int32_t>> previous;
        std::lock_guard<std::mutex> lock(_mutex);
        previous = std::move(_pending);
        _pending = std::make_unique<djinni::Promise<int32_t>>();
        auto future = _pending->getFuture();
        // The count moves after the new promise is stored, so a test that waits for the count knows that this call
        // replaced the promise of the call before
        _pendingStarted.fetch_add(1);
        return future;
    }

    djinni::Future<rt::RuntimeColor> bad_color_future() override {
        return djinni::Promise<rt::RuntimeColor>::resolve(static_cast<rt::RuntimeColor>(99));
    }

    djinni::Future<int32_t> dropped() override {
        djinni::Promise<int32_t> promise;
        return promise.getFuture();
    }

    std::string describe_future_failure(const std::shared_ptr<rt::RuntimeListener>& listener) override {
        // The handler is chained before the Swift host completes its future, so it runs inside the completion.
        // It throws an exception that does not derive from std::exception.
        auto next = listener->delayed_future(1, 50).then([](djinni::Future<int32_t> f) -> int32_t {
            f.get();
            throw 42;
        });
        try {
            next.get();
        } catch (int value) {
            return "int " + std::to_string(value);
        } catch (const std::exception& e) {
            return e.what();
        }
        return "no error";
    }

    void complete_pending(int32_t value) override {
        std::unique_ptr<djinni::Promise<int32_t>> promise;
        {
            std::lock_guard<std::mutex> lock(_mutex);
            promise = std::move(_pending);
        }
        if (promise) {
            promise->setValue(value);
        }
    }

    void busy(int32_t millis) override {
        const int32_t active = ++_active;
        int32_t seen = _maxActive.load();
        while (active > seen && !_maxActive.compare_exchange_weak(seen, active)) {}
        std::this_thread::sleep_for(std::chrono::milliseconds(millis));
        --_active;
    }

    int32_t max_concurrent() override { return _maxActive.load(); }

    int32_t pending_started() override { return _pendingStarted.load(); }

    int32_t call_listener(const std::shared_ptr<rt::RuntimeListener>& listener, int32_t value) override {
        return listener->on_value(value);
    }

    std::shared_ptr<rt::RuntimeAsync> same() override { return shared_from_this(); }

private:
    std::atomic<int32_t> _active{0};
    std::atomic<int32_t> _maxActive{0};
    std::atomic<int32_t> _pendingStarted{0};
    std::mutex _mutex;
    std::unique_ptr<djinni::Promise<int32_t>> _pending;
};

} // namespace

std::shared_ptr<rt::RuntimeAsync> rt::RuntimeAsync::create() {
    return std::make_shared<RuntimeAsyncImpl>();
}

std::shared_ptr<rt::RuntimeAsync> rt::RuntimeAsync::shared() {
    static const std::shared_ptr<RuntimeAsyncImpl> instance = std::make_shared<RuntimeAsyncImpl>();
    return instance;
}
