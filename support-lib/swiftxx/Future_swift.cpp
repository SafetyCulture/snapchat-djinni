#include "Future_swift.hpp"

namespace djinni::swift {

namespace {

// Swift calls these functions. A C++ exception must not reach a Swift frame, so each function checks its input
// and catches everything.
template <typename Holder>
std::shared_ptr<Holder> holderOf(const AnyValue* value) noexcept {
    if (value == nullptr) {
        return nullptr;
    }
    const auto* opaque = std::get_if<OpaqueValuePtr>(value);
    return opaque ? std::dynamic_pointer_cast<Holder>(*opaque) : nullptr;
}

} // namespace

void setFutureCb(const AnyValue* futureValue, FutureCb cb, void* ctx) {
    try {
        auto holder = holderOf<AbstractCppFutureHolder>(futureValue);
        if (holder) {
            holder->setFutureCb(cb, ctx);
            return;
        }
    } catch (...) {
        // The callback takes the error below
    }
    // The callback releases its context. Without this call the context of Swift leaks and the future never completes.
    AnyValue invalid = ErrorValue("the value is not a C++ future");
    cb(ctx, &invalid);
}

AnyValue makeFutureValue(CleanupCb cleanup) {
    try {
        OpaqueValuePtr holder = std::make_shared<SwiftFutureHolder>(cleanup);
        return {holder};
    } catch (...) {
        return ErrorValue("failed to allocate a future");
    }
}

void setFutureResult(const AnyValue* futureValue, const AnyValue* futureResult) {
    try {
        auto holder = holderOf<SwiftFutureHolder>(futureValue);
        if (holder && futureResult != nullptr) {
            holder->setValue(futureResult);
        }
    } catch (...) {
        // The promise is complete when its handlers throw, and no one can receive the exception
    }
}

void storeSubscription(const AnyValue* futureValue, void* subscription) {
    auto holder = holderOf<SwiftFutureHolder>(futureValue);
    if (holder) {
        holder->subscription = subscription;
    }
}

}
