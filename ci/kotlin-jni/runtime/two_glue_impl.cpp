#include "two_glue_color.hpp"
#include "two_glue_listener.hpp"
#include "two_glue_record.hpp"
#include "two_glue_service.hpp"

#include "djinni_support.hpp"

#include <atomic>
#include <memory>
#include <mutex>
#include <string>

namespace {

std::atomic<int32_t> releasedServices{0};
std::mutex singletonMutex;
std::weak_ptr<tg::TwoGlueService> singleton;

class TwoGlueServiceImpl final : public tg::TwoGlueService,
                                 public std::enable_shared_from_this<TwoGlueServiceImpl> {
public:
    ~TwoGlueServiceImpl() override { releasedServices.fetch_add(1); }

    std::shared_ptr<tg::TwoGlueService> self() override { return shared_from_this(); }

    int32_t value() override { return 41; }

    tg::TwoGlueRecord echo(const tg::TwoGlueRecord &item) override { return item; }

    tg::TwoGlueColor invert(tg::TwoGlueColor color) override {
        switch (color) {
            case tg::TwoGlueColor::RED: return tg::TwoGlueColor::GREEN;
            case tg::TwoGlueColor::GREEN: return tg::TwoGlueColor::BLUE;
            case tg::TwoGlueColor::BLUE: return tg::TwoGlueColor::RED;
        }
        return tg::TwoGlueColor::RED;
    }

    int32_t call_listener(const std::shared_ptr<tg::TwoGlueListener> &listener, int32_t value) override {
        return listener->on_value(value);
    }
};

int32_t countServiceEntries(const char *glue) {
    int32_t count = 0;
    for (const auto &entry : djinni::JniCppProxyCache::stats()) {
        const std::string name(entry.first);
        if (name.find(glue) != std::string::npos && name.find("NativeTwoGlueService") != std::string::npos) {
            count += static_cast<int32_t>(entry.second);
        }
    }
    return count;
}

} // namespace

namespace tg {

// The weak pointer keeps one object per process without keeping it alive, so the collector can release it.
std::shared_ptr<TwoGlueService> TwoGlueService::get() {
    std::lock_guard<std::mutex> lock(singletonMutex);
    auto existing = singleton.lock();
    if (existing) {
        return existing;
    }
    auto created = std::make_shared<TwoGlueServiceImpl>();
    singleton = created;
    return created;
}

int32_t TwoGlueService::released() { return releasedServices.load(); }

int32_t TwoGlueService::cached_a() { return countServiceEntries("glue_a"); }

int32_t TwoGlueService::cached_b() { return countServiceEntries("glue_b"); }

} // namespace tg
