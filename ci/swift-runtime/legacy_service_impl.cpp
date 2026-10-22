#include "legacy_service.hpp"
#include "legacy_point.hpp"

#include <memory>

namespace {

class LegacyServiceImpl : public rt::LegacyService {
public:
    rt::LegacyPoint echo(const rt::LegacyPoint& point) override { return point; }
};

} // namespace

std::shared_ptr<rt::LegacyService> rt::LegacyService::create() {
    return std::make_shared<LegacyServiceImpl>();
}
