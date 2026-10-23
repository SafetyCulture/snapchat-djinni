#include "kjs_both.hpp"
#include "kjs_error.hpp"
#include "kjs_listener.hpp"
#include "kjs_service.hpp"

#include <memory>
#include <stdexcept>

namespace {

djinni::expected<int32_t, kj::KjsError> divideValues(int32_t a, int32_t b) {
    if (b == 0) {
        return djinni::make_unexpected(kj::KjsError("division by zero", 7));
    }
    return a / b;
}

class KjsBothImpl : public kj::KjsBoth {
public:
    djinni::expected<int32_t, kj::KjsError> divide(int32_t a, int32_t b) override { return divideValues(a, b); }
};

class KjsServiceImpl : public kj::KjsService {
public:
    int32_t add(int32_t a, int32_t b) override { return a + b; }

    void ping() override {}

    djinni::expected<int32_t, kj::KjsError> divide(int32_t a, int32_t b) override { return divideValues(a, b); }

    int32_t fail() override { throw std::runtime_error("boom"); }

    void fail_void() override { throw std::runtime_error("void boom"); }

    int32_t fail_unknown() override { throw 42; }

    int32_t call_listener(const std::shared_ptr<kj::KjsListener>& listener, int32_t value) override {
        return listener->on_value(value);
    }

    djinni::expected<int32_t, kj::KjsError> call_both(const std::shared_ptr<kj::KjsBoth>& both, int32_t a, int32_t b) override {
        return both->divide(a, b);
    }

    std::shared_ptr<kj::KjsBoth> make_both() override { return std::make_shared<KjsBothImpl>(); }
};

} // namespace

std::shared_ptr<kj::KjsService> kj::KjsService::create() {
    return std::make_shared<KjsServiceImpl>();
}

int32_t kj::KjsService::fail_static() {
    throw std::runtime_error("static boom");
}

djinni::expected<int32_t, kj::KjsError> kj::KjsService::divide_static(int32_t a, int32_t b) {
    return divideValues(a, b);
}
