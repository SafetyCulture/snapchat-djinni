#include "kj_error.hpp"
#include "kj_blob.hpp"
#include "kj_both.hpp"
#include "kj_color.hpp"
#include "kj_future_source.hpp"
#include "kj_item.hpp"
#include "kj_listener.hpp"
#include "kj_message_box.hpp"
#include "kj_service.hpp"

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

std::atomic<int32_t> liveServices{0};
std::atomic<int32_t> pendingStarted{0};

djinni::expected<int32_t, kj::KjError> divideValues(int32_t a, int32_t b) {
    if (b == 0) {
        return djinni::make_unexpected(kj::KjError("division by zero", 7));
    }
    return a / b;
}

// Completes the future with the value on another thread after the delay.
template <typename T>
djinni::Future<T> later(T value, int32_t millis) {
    djinni::Promise<T> promise;
    auto future = promise.getFuture();
    std::thread([promise = std::move(promise), value = std::move(value), millis]() mutable {
        std::this_thread::sleep_for(std::chrono::milliseconds(millis));
        promise.setValue(std::move(value));
    }).detach();
    return future;
}

class KjServiceImpl : public kj::KjService {
public:
    KjServiceImpl() { ++liveServices; }
    ~KjServiceImpl() override { --liveServices; }

    int32_t add(int32_t a, int32_t b) override { return a + b; }

    kj::KjItem echo(const kj::KjItem& item) override { return item; }

    kj::KjBlob echo_blob(const kj::KjBlob& blob) override { return blob; }

    kotlin_extern::KotlinMessage echo_message(const kotlin_extern::KotlinMessage& message) override { return message; }

    kj::KjMessageBox echo_message_box(const kj::KjMessageBox& box) override { return box; }

    djinni::expected<int32_t, kj::KjError> divide(int32_t a, int32_t b) override { return divideValues(a, b); }

    int32_t call_listener(const std::shared_ptr<kj::KjListener>& listener, int32_t value) override {
        return listener->on_value(value);
    }

    std::string await_source(const std::shared_ptr<kj::KjFutureSource>& source) override {
        auto future = source->produce();
        try {
            return "value " + std::to_string(future.get());
        } catch (const std::exception& e) {
            return e.what();
        }
    }

    djinni::Future<int32_t> delayed(int32_t value, int32_t millis) override { return later(value, millis); }

    djinni::Future<djinni::expected<int32_t, kj::KjError>> divide_later(int32_t a, int32_t b, int32_t millis) override {
        return later(divideValues(a, b), millis);
    }

    // A second call before complete_pending replaces the promise of the first call. The first future breaks with
    // BrokenPromiseException instead of waiting for ever. The old promise is destroyed outside the lock, because its
    // handler runs when it is destroyed.
    djinni::Future<int32_t> pending() override {
        pendingStarted.fetch_add(1);
        std::unique_ptr<djinni::Promise<int32_t>> previous;
        std::lock_guard<std::mutex> lock(_mutex);
        previous = std::move(_pending);
        _pending = std::make_unique<djinni::Promise<int32_t>>();
        auto future = _pending->getFuture();
        return future;
    }

    int32_t pending_started() override { return pendingStarted.load(); }

    djinni::Future<int32_t> failing_future() override {
        return djinni::Promise<int32_t>::reject(std::make_exception_ptr(std::runtime_error("failed future")));
    }

    djinni::Future<void> done() override {
        djinni::Promise<void> promise;
        auto future = promise.getFuture();
        promise.setValue();
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

    int32_t fail() override { throw std::runtime_error("boom"); }

    int32_t fail_unknown() override { throw 42; }

    djinni::Future<int32_t> dropped() override {
        djinni::Promise<int32_t> promise;
        return promise.getFuture();
    }

    djinni::Future<int32_t> unknown_future() override {
        return djinni::Promise<int32_t>::reject(std::make_exception_ptr(42));
    }

    void busy(int32_t millis) override {
        const int32_t active = ++_active;
        int32_t seen = _maxActive.load();
        while (active > seen && !_maxActive.compare_exchange_weak(seen, active)) {}
        std::this_thread::sleep_for(std::chrono::milliseconds(millis));
        --_active;
    }

    int32_t max_concurrent() override { return _maxActive.load(); }

    kj::KjColor invert(kj::KjColor color) override {
        return static_cast<kj::KjColor>((static_cast<int>(color) + 1) % 3);
    }

    std::optional<kj::KjColor> invert_opt(std::optional<kj::KjColor> color) override {
        return color ? std::optional<kj::KjColor>(invert(*color)) : std::nullopt;
    }

    std::optional<kj::KjFlags> flags_opt(std::optional<kj::KjFlags> flags) override { return flags; }

    std::shared_ptr<kj::KjService> echo_service(const std::shared_ptr<kj::KjService>& service) override { return service; }

    int32_t call_both(const std::shared_ptr<kj::KjBoth>& both) override { return both->value(); }

    std::shared_ptr<kj::KjBoth> make_both() override;

private:
    std::atomic<int32_t> _active{0};
    std::atomic<int32_t> _maxActive{0};
    std::mutex _mutex;
    std::unique_ptr<djinni::Promise<int32_t>> _pending;
};

class KjBothImpl : public kj::KjBoth {
public:
    int32_t value() override { return 11; }
};

std::shared_ptr<kj::KjBoth> KjServiceImpl::make_both() { return std::make_shared<KjBothImpl>(); }

} // namespace

int32_t kj::KjService::live_count() {
    return liveServices.load();
}

int32_t kj::KjService::fail_static() {
    throw std::runtime_error("static boom");
}

djinni::expected<int32_t, kj::KjError> kj::KjService::divide_static(int32_t a, int32_t b) {
    return divideValues(a, b);
}

djinni::Future<int32_t> kj::KjService::delayed_static(int32_t value, int32_t millis) {
    return later(value, millis);
}

std::shared_ptr<kj::KjService> kj::KjService::create() {
    return std::make_shared<KjServiceImpl>();
}
