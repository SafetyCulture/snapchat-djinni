#include "error_service.hpp"
#include "crux_error.hpp"

#include <memory>
#include <stdexcept>

namespace {

class ErrorServiceImpl : public rt::ErrorService {
public:
    djinni::expected<int32_t, rt::CruxError> divide(int32_t a, int32_t b) override {
        if (b == 0) {
            return djinni::make_unexpected(rt::CruxError("division by zero", 7));
        }
        return a / b;
    }

    djinni::expected<int32_t, rt::CruxError> fail() override { throw std::runtime_error("boom"); }
};

} // namespace

std::shared_ptr<rt::ErrorService> rt::ErrorService::create() {
    return std::make_shared<ErrorServiceImpl>();
}
