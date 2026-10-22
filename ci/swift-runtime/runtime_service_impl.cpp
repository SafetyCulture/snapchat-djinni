#include "runtime_listener.hpp"
#include "runtime_service.hpp"

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

private:
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
