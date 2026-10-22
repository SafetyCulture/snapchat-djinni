#include "kj_error.hpp"
#include "kj_blob.hpp"
#include "kj_both.hpp"
#include "kj_color.hpp"
#include "kj_item.hpp"
#include "kj_listener.hpp"
#include "kj_service.hpp"

#include <atomic>
#include <chrono>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <thread>

namespace {

std::atomic<int32_t> liveServices{0};

class KjServiceImpl : public kj::KjService {
public:
    KjServiceImpl() { ++liveServices; }
    ~KjServiceImpl() override { --liveServices; }

    int32_t add(int32_t a, int32_t b) override { return a + b; }

    kj::KjItem echo(const kj::KjItem& item) override { return item; }

    kj::KjBlob echo_blob(const kj::KjBlob& blob) override { return blob; }

    djinni::expected<int32_t, kj::KjError> divide(int32_t a, int32_t b) override {
        if (b == 0) {
            return djinni::make_unexpected(kj::KjError("division by zero", 7));
        }
        return a / b;
    }

    int32_t call_listener(const std::shared_ptr<kj::KjListener>& listener, int32_t value) override {
        return listener->on_value(value);
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

    int32_t fail() override { throw std::runtime_error("boom"); }

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

std::shared_ptr<kj::KjService> kj::KjService::create() {
    return std::make_shared<KjServiceImpl>();
}
