#pragma once

#include "djinni_support.hpp"
#include "../cpp/Future.hpp"

#include <atomic>
#include <optional>

namespace djinni::swift {

// Swift function prototypes called by C++
typedef void (*FutureCb)(void* ctx, AnyValue* result);
typedef void (*CleanupCb)(void* subscription);

// C++ function declarations called by Swift
void setFutureCb(const AnyValue* futureValue, FutureCb cb, void* ctx);
AnyValue makeFutureValue(CleanupCb cleanup);
void setFutureResult(const AnyValue* futureValue, const AnyValue* futureResult);
void storeSubscription(const AnyValue* futureValue, void* subscription);

// Common interface for a Swift accessible C++ future
struct AbstractCppFutureHolder: OpaqueValue {
    virtual ~AbstractCppFutureHolder() = default;
    virtual void setFutureCb(FutureCb cb, void* ctx) = 0;
};

// Holds a C++ future that returns a RESULT type
template<typename RESULT>
struct CppFutureHolder: AbstractCppFutureHolder {
    using CppResType = typename RESULT::CppType;
    djinni::Future<CppResType> future;
    explicit CppFutureHolder(djinni::Future<CppResType> f) : future(std::move(f)) {}

    template<typename T>
    static AnyValue getFutureResult(Future<T>& f) {
        if constexpr (std::is_void_v<T>) {
            f.get();
            return makeVoidValue();
        } else {
            return RESULT::fromCpp(f.get());
        }
    }

    void setFutureCb(FutureCb cb, void* ctx) override {
        // Only one callback can take the future. A second call gets an error, so Swift releases its context.
        if (!future.isValid()) {
            AnyValue invalid = ErrorValue("the C++ future was already taken");
            cb(ctx, &invalid);
            return;
        }
        future.then([cb, ctx] (Future<CppResType> f) {
            AnyValue result = makeVoidValue();
            try {
                result = getFutureResult(f);
            } catch (const ErrorValue& e) {
                result = e;
            } catch (const std::exception& e) {
                result = ErrorValue{e.what(), std::current_exception()};
            } catch (...) {
                result = ErrorValue{"unknown C++ exception", std::current_exception()};
            }
            cb(ctx, &result);
        });
    }
};

// Maintains the link from a Swift future to a C++ accessible future
struct SwiftFutureHolder: OpaqueValue {
    djinni::Promise<AnyValue> promise;
    std::shared_ptr<djinni::Future<AnyValue>> future;
    void* subscription = nullptr;
    CleanupCb cleanup;
    std::atomic<bool> completed{false};
    SwiftFutureHolder(CleanupCb cleanup) {
        this->cleanup = cleanup;
        this->future = std::make_shared<djinni::Future<AnyValue>>(promise.getFuture());
    }
    ~SwiftFutureHolder() override {
        cleanup(subscription);
    }
    // A promise completes once. A second result is dropped.
    void setValue(const AnyValue* futureValue) {
        if (completed.exchange(true)) {
            return;
        }
        promise.setValue(*futureValue);
    }
};

template <class RESULT>
class FutureAdaptor
{
    using CppResType = typename RESULT::CppType;
    // The result of the Swift future becomes the result of the C++ promise. The conversion runs inside the try
    // block, and the promise completes once, outside it.
    static void complete(Promise<CppResType>& p, Future<AnyValue>& f) {
        std::exception_ptr error;
        [[maybe_unused]] std::optional<typename detail::ValueHolder<CppResType>::type> value;
        try {
            auto res = f.get();
            if (std::holds_alternative<ErrorValue>(res)) {
                const auto& e = std::get<ErrorValue>(res);
                error = e.cause ? e.cause : std::make_exception_ptr(e);
            } else if constexpr (std::is_void_v<CppResType>) {
                value = true;
            } else {
                value.emplace(RESULT::toCpp(res));
            }
        } catch (...) {
            error = std::current_exception();
        }
        if (error) {
            p.setException(error);
        } else if constexpr (std::is_void_v<CppResType>) {
            p.setValue();
        } else {
            p.setValue(std::move(*value));
        }
    }
public:
    using CppType = Future<CppResType>;

    static CppType toCpp(const AnyValue& o) {
        auto opaque = std::get<OpaqueValuePtr>(o);
        // If already a C++ future (can this happen?), just return the wrapped future
        auto holder = std::dynamic_pointer_cast<CppFutureHolder<RESULT>>(opaque);
        if (holder) {
            return std::move(holder->future);
        }
        // Acquire the holder for Swift future
        auto swiftHolder = std::dynamic_pointer_cast<SwiftFutureHolder>(opaque);
        if (!swiftHolder) {
            throw ErrorValue("the value is not a future");
        }
        Promise<CppResType> p;
        auto f = p.getFuture();
        // And return a C++ future connected to it
        swiftHolder->future->then([p = std::move(p)] (Future<AnyValue> f) mutable {
            complete(p, f);
        });
        return f;
    }
    static AnyValue fromCpp(CppType c) {
        OpaqueValuePtr holder = std::make_shared<CppFutureHolder<RESULT>>(std::move(c));
        return {holder};
    }
};

}
