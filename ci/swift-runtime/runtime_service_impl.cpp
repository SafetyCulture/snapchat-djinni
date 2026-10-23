#include "runtime_error.hpp"
#include "runtime_blob.hpp"
#include "runtime_listener.hpp"
#include "runtime_error.hpp"
#include "runtime_service.hpp"

#include <CoreFoundation/CoreFoundation.h>

#include <memory>

namespace {

class RuntimeServiceImpl : public rt::RuntimeService, public std::enable_shared_from_this<RuntimeServiceImpl> {
public:
    int32_t add(int32_t a, int32_t b) override { return a + b; }
    int32_t call_listener(const std::shared_ptr<rt::RuntimeListener>& listener, int32_t value) override {
        return listener->on_value(value);
    }
    void keep_listener(const std::shared_ptr<rt::RuntimeListener>& listener) override { _kept = listener; }
    int32_t call_kept_listener(int32_t value) override { return _kept ? _kept->on_value(value) : -1; }
    std::shared_ptr<rt::RuntimeService> same_service() override { return shared_from_this(); }
    int32_t data_size(const djinni::DataRef& data) override { return static_cast<int32_t>(data.len()); }
    int32_t listener_data_sum(const std::shared_ptr<rt::RuntimeListener>& listener) override {
        // The DataRef that the Swift host returns must stay valid while C++ reads it.
        djinni::DataRef data = listener->make_data();
        int32_t sum = 0;
        for (size_t i = 0; i < data.len(); i++) {
            sum += data.buf()[i];
        }
        return sum;
    }
    djinni::expected<std::optional<int32_t>, rt::RuntimeError> maybe(bool flag) override {
        if (flag) {
            return std::optional<int32_t>(42);
        }
        return djinni::expected<std::optional<int32_t>, rt::RuntimeError>(std::optional<int32_t>());
    }
    // The Swift host answers with a nil success; C++ must read it as a success, not an error
    int32_t listener_maybe(const std::shared_ptr<rt::RuntimeListener>& listener, bool flag) override {
        auto result = listener->on_maybe(flag);
        if (!result) {
            return -1;
        }
        return result->value_or(-2);
    }
    std::chrono::system_clock::time_point date_roundtrip(const std::chrono::system_clock::time_point& d) override { return d; }
    rt::RuntimeColor unknown_color() override { return static_cast<rt::RuntimeColor>(99); }
    // "\xC0\xAF" is an overlong encoding of "/", which is not valid UTF-8
    std::string invalid_string() override { return std::string("ab\xC0\xAF"); }
    // The byte order mark U+FEFF and "abc"
    std::string bom_string() override { return std::string("\xEF\xBB\xBF" "abc"); }
    rt::RuntimeBlob bad_blob() override { return rt::RuntimeBlob(static_cast<rt::RuntimeColor>(42), keptData()); }
    int32_t kept_data_retain_count() override {
        return static_cast<int32_t>(CFGetRetainCount(static_cast<CFTypeRef>(keptData().platformObj())));
    }

private:
    // One CFData that every call shares, so that the test counts its references
    static const djinni::DataRef& keptData() {
        static const djinni::DataRef data(std::vector<uint8_t>(16, 1));
        return data;
    }
    std::shared_ptr<rt::RuntimeListener> _kept;
};

} // namespace

std::shared_ptr<rt::RuntimeService> rt::RuntimeService::create() {
    return std::make_shared<RuntimeServiceImpl>();
}

std::shared_ptr<rt::RuntimeService> rt::RuntimeService::shared() {
    static const std::shared_ptr<RuntimeServiceImpl> instance = std::make_shared<RuntimeServiceImpl>();
    return instance;
}

std::shared_ptr<rt::RuntimeService> rt::RuntimeService::null_service() {
    return nullptr;
}
