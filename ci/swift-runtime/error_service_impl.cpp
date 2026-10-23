#include "error_service.hpp"
#include "crux_error.hpp"
#include "sync_error.hpp"
#include "sync_error_service.hpp"

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>

namespace {

djinni::Future<int32_t> later(int32_t value, int32_t millis) {
    djinni::Promise<int32_t> promise;
    auto future = promise.getFuture();
    std::thread([promise = std::move(promise), value, millis]() mutable {
        std::this_thread::sleep_for(std::chrono::milliseconds(millis));
        promise.setValue(value);
    }).detach();
    return future;
}

class ErrorServiceImpl : public rt::ErrorService {
public:
    djinni::expected<int32_t, rt::CruxError> divide(int32_t a, int32_t b) override {
        if (b == 0) {
            return djinni::make_unexpected(rt::CruxError("division by zero", 7));
        }
        return a / b;
    }

    djinni::expected<int32_t, rt::CruxError> fail() override { throw std::runtime_error("boom"); }

    int32_t add(int32_t a, int32_t b) override { return a + b; }

    int32_t fail_plain() override { throw std::runtime_error("boom"); }

    void fail_void() override { throw std::runtime_error("boom"); }

    djinni::Future<int32_t> delayed(int32_t value, int32_t millis) override { return later(value, millis); }

    djinni::Future<djinni::expected<int32_t, rt::CruxError>> divide_later(int32_t a, int32_t b) override {
        djinni::Promise<djinni::expected<int32_t, rt::CruxError>> promise;
        auto future = promise.getFuture();
        std::thread([promise = std::move(promise), value = divide(a, b)]() mutable {
            std::this_thread::sleep_for(std::chrono::milliseconds(20));
            promise.setValue(std::move(value));
        }).detach();
        return future;
    }

    djinni::Future<int32_t> fail_future() override {
        return djinni::Promise<int32_t>::reject(std::make_exception_ptr(std::runtime_error("failed future")));
    }

    djinni::Future<int32_t> throw_future() override { throw std::runtime_error("boom"); }

    djinni::Future<int32_t> dropped() override {
        djinni::Promise<int32_t> promise;
        return promise.getFuture();
    }

    djinni::Future<int32_t> pending() override {
        // The old promise is destroyed outside the lock, because its handler runs when it is destroyed.
        std::unique_ptr<djinni::Promise<int32_t>> previous;
        std::lock_guard<std::mutex> lock(_mutex);
        previous = std::move(_pending);
        _pending = std::make_unique<djinni::Promise<int32_t>>();
        auto future = _pending->getFuture();
        // A test waits for this count to know that the future exists.
        _pendingStarted.fetch_add(1);
        return future;
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

    int32_t pending_started() override { return _pendingStarted.load(); }

    int32_t touch() override { return ++_touched; }

    int32_t touch_count() override { return _touched.load(); }

private:
    std::atomic<int32_t> _pendingStarted{0};
    std::atomic<int32_t> _touched{0};
    std::mutex _mutex;
    std::unique_ptr<djinni::Promise<int32_t>> _pending;
};

class SyncErrorServiceImpl : public rt::SyncErrorService {
public:
    djinni::expected<int32_t, rt::SyncError> divide(int32_t a, int32_t b) override {
        if (b == 0) {
            return djinni::make_unexpected(rt::SyncError("division by zero", 7));
        }
        return a / b;
    }

    int32_t add(int32_t a, int32_t b) override { return a + b; }

    int32_t fail() override { throw std::runtime_error("boom"); }

    void fail_void() override { throw std::runtime_error("boom"); }
};

} // namespace

std::shared_ptr<rt::ErrorService> rt::ErrorService::create() {
    return std::make_shared<ErrorServiceImpl>();
}

int32_t rt::ErrorService::fail_static() { throw std::runtime_error("boom"); }

djinni::Future<int32_t> rt::ErrorService::delayed_static(int32_t value) { return later(value, 10); }

std::shared_ptr<rt::SyncErrorService> rt::SyncErrorService::create() {
    return std::make_shared<SyncErrorServiceImpl>();
}

djinni::expected<int32_t, rt::SyncError> rt::SyncErrorService::fail_static() { throw std::runtime_error("boom"); }
