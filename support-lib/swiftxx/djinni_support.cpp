#include "djinni_support.hpp"

namespace djinni::swift {

AnyValue makeStringValue(const char* bytes, size_t size) {
    return StringValue(bytes, size);
}

AnyValue makeBinaryValue(const void* bytes, size_t size) {
    auto p = reinterpret_cast<const uint8_t*>(bytes);
    return BinaryValue{p, p + size};
}

AnyValue makeRangeValue(const void* bytes, size_t size) {
    return RangeValue{bytes, size};
}

BinaryRangeResult getBinaryRange(const AnyValue& v) noexcept {
    if (const auto* s = std::get_if<StringValue>(&v)) {
        return {s->data(), s->size(), true};
    } else if (const auto* b = std::get_if<BinaryValue>(&v)) {
        return {b->data(), b->size(), true};
    } else if (const auto* r = std::get_if<RangeValue>(&v)) {
        return {r->bytes, r->size, true};
    }
    return {nullptr, 0, false};
}

SizeResult getSize(const AnyValue* v) noexcept {
    if (v != nullptr) {
        if (const auto* composite = std::get_if<CompositeValuePtr>(v); composite != nullptr && *composite) {
            return {(*composite)->getSize(), true};
        }
    }
    return {0, false};
}

namespace {

AnyValue memberOf(const CompositeValue* composite, size_t i) noexcept {
    if (composite == nullptr) {
        return ErrorValue("the value is not a composite");
    }
    if (i >= composite->_elems.size()) {
        return ErrorValue("the composite has no member " + std::to_string(i) + ", it has " + std::to_string(composite->_elems.size()));
    }
    return composite->_elems[i];
}

} // namespace

AnyValue getMember(const AnyValue* v, size_t i) noexcept {
    const auto* composite = v != nullptr ? std::get_if<CompositeValuePtr>(v) : nullptr;
    return memberOf(composite != nullptr ? composite->get() : nullptr, i);
}

AnyValue getMember(const ParameterList* v, size_t i) noexcept {
    return memberOf(v, i);
}

bool addMember(AnyValue* c, const AnyValue& v) noexcept {
    auto* composite = c != nullptr ? std::get_if<CompositeValuePtr>(c) : nullptr;
    if (composite == nullptr || !*composite) {
        return false;
    }
    try {
        (*composite)->addValue(v);
        return true;
    } catch (...) {
        return false;
    }
}

void setReturnValue(AnyValue* ret, const AnyValue& v) {
    *ret = v;
}

void setErrorValue(AnyValue* ret, const ErrorValue& v) {
    *ret = v;
}

void setErrorMessage(AnyValue* ret, const std::string& s) {
    *ret = ErrorValue{s};
}

WeakSwiftProxy weakify(const AnyValue& v) noexcept {
    // Swift calls this function, so a value that is not an interface gives an empty weak proxy, not an exception
    const auto* i = std::get_if<InterfaceValue>(&v);
    if (i == nullptr) {
        return {};
    }
    return {i->ptr, i->sptr};
}

AnyValue strongify(const WeakSwiftProxy& v) noexcept {
    return {InterfaceValue{v.ptr.lock(), v.sptr.lock()}};
}

bool isExpired(const WeakSwiftProxy& v) noexcept {
    return v.sptr.expired();
}

InterfaceInfo getInterfaceInfo(const AnyValue* v) noexcept {
    const auto* i = v != nullptr ? std::get_if<InterfaceValue>(v) : nullptr;
    if (i == nullptr) {
        return {nullptr, nullptr, false};
    }
    return {i->ptr.get(), i->sptr ? i->sptr->ctx() : nullptr, true};
}

AnyValue makeVoidValue() {
    return VoidValue{};
}

bool isVoidValue(const AnyValue* c) {
    return std::holds_alternative<VoidValue>(*c);
}


AnyValue makeCompositeValue() {
    return { std::make_shared<CompositeValue>() }; 
}

bool isError(const AnyValue* ret) {
    return std::holds_alternative<ErrorValue>(*ret);
}

I32Result getI32Value(const AnyValue& v) noexcept {
    const auto* i = std::get_if<I32Value>(&v);
    return i != nullptr ? I32Result{*i, true} : I32Result{0, false};
}

I64Result getI64Value(const AnyValue& v) noexcept {
    const auto* i = std::get_if<I64Value>(&v);
    return i != nullptr ? I64Result{*i, true} : I64Result{0, false};
}

DoubleResult getDoubleValue(const AnyValue& v) noexcept {
    const auto* d = std::get_if<DoubleValue>(&v);
    return d != nullptr ? DoubleResult{*d, true} : DoubleResult{0, false};
}

ErrorValue getError(const AnyValue* ret) noexcept {
    const auto* e = ret != nullptr ? std::get_if<ErrorValue>(ret) : nullptr;
    return e != nullptr ? *e : ErrorValue("the value is not an error");
}

ProtocolWrapper::ProtocolWrapper(void* ctx, DispatchFunc dispatcher):
    _ctx(ctx), _dispatcher(dispatcher)
{}

ProtocolWrapper::~ProtocolWrapper() {
    _dispatcher(_ctx, -1, nullptr, nullptr);
}

AnyValue ProtocolWrapper::callProtocol(int idx, const ParameterList* params) const {
    AnyValue ret = VoidValue(); // output parameter
    _dispatcher(_ctx, idx, params, &ret);
    if (std::holds_alternative<ErrorValue>(ret)) {
        const auto& e = std::get<ErrorValue>(ret);
        if (e.cause) {
            // previously thrown c++ exception
            std::rethrow_exception(e.cause);
        } else {
            // swift error
            throw e;
        }
    }
    return ret;
}

}
