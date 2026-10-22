#include "runtime_async.hpp"
#include "runtime_error.hpp"

#include <chrono>
#include <memory>
#include <mutex>
#include <thread>

namespace {

class RuntimeAsyncImpl : public rt::RuntimeAsync {
public:
    int32_t add(int32_t a, int32_t b) override { return a + b; }

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

    djinni::Future<int32_t> pending() override {
        std::lock_guard<std::mutex> lock(_mutex);
        _pending = std::make_unique<djinni::Promise<int32_t>>();
        return _pending->getFuture();
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

private:
    std::mutex _mutex;
    std::unique_ptr<djinni::Promise<int32_t>> _pending;
};

} // namespace

std::shared_ptr<rt::RuntimeAsync> rt::RuntimeAsync::create() {
    return std::make_shared<RuntimeAsyncImpl>();
}
