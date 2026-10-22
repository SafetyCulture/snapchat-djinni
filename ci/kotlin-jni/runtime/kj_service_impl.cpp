#include "kj_error.hpp"
#include "kj_blob.hpp"
#include "kj_both.hpp"
#include "kj_color.hpp"
#include "kj_item.hpp"
#include "kj_listener.hpp"
#include "kj_service.hpp"

#include <chrono>
#include <memory>
#include <stdexcept>
#include <thread>

namespace {

class KjServiceImpl : public kj::KjService {
public:
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

    int32_t fail() override { throw std::runtime_error("boom"); }

    kj::KjColor invert(kj::KjColor color) override {
        return static_cast<kj::KjColor>((static_cast<int>(color) + 1) % 3);
    }

    std::shared_ptr<kj::KjService> echo_service(const std::shared_ptr<kj::KjService>& service) override { return service; }

    int32_t call_both(const std::shared_ptr<kj::KjBoth>& both) override { return both->value(); }

    std::shared_ptr<kj::KjBoth> make_both() override;
};

class KjBothImpl : public kj::KjBoth {
public:
    int32_t value() override { return 11; }
};

std::shared_ptr<kj::KjBoth> KjServiceImpl::make_both() { return std::make_shared<KjBothImpl>(); }

} // namespace

std::shared_ptr<kj::KjService> kj::KjService::create() {
    return std::make_shared<KjServiceImpl>();
}
