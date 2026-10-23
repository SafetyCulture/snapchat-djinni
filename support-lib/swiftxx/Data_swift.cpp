#include "Data_swift.hpp"
#include <cassert>

// The DataRef constructors for Apple platforms come from objc/DataRef_objc.cpp, which is plain C++ over CFData.

namespace djinni::swift {

DataRefHolder::DataRefHolder(CFDataRef data, bool isMutable) : data(data), isMutable(isMutable) {
    CFRetain(data);
}

DataRefHolder::~DataRefHolder() {
    CFRelease(data);
}

DataView DataViewAdaptor::toCpp(const AnyValue& s) {
    auto range = std::get<RangeValue>(s);
    return DataView(reinterpret_cast<const uint8_t*>(range.bytes), range.size);
}

AnyValue DataViewAdaptor::fromCpp(DataView c) {
    return RangeValue{c.buf(), c.len()};
}

DataRef DataRefAdaptor::toCpp(const AnyValue& s) {
    const auto& opaque = std::get<OpaqueValuePtr>(s);
    const auto* holder = dynamic_cast<const DataRefHolder*>(opaque.get());
    if (holder == nullptr) {
        throw ErrorValue("the value is not a DataRef value");
    }
    // The DataRef retains its own reference, and the value keeps the one that it owns until it is destroyed.
    return holder->isMutable ? DataRef(const_cast<CFMutableDataRef>(holder->data)) : DataRef(holder->data);
}

AnyValue DataRefAdaptor::fromCpp(const DataRef& c) {
    // Every Apple backend keeps its bytes in a CFData, so the platform object works for all of them.
    auto cfdata = static_cast<CFDataRef>(c.platformObj());
    if (cfdata != nullptr) {
        return OpaqueValuePtr(std::make_shared<DataRefHolder>(cfdata, false));
    }
    struct Created {
        CFDataRef data;
        ~Created() { if (data != nullptr) CFRelease(data); }
    } created{CFDataCreate(kCFAllocatorDefault, nullptr, 0)};
    if (created.data == nullptr) {
        throw ErrorValue("failed to allocate a DataRef value");
    }
    return OpaqueValuePtr(std::make_shared<DataRefHolder>(created.data, false));
}

AnyValue makeDataRefValue(const void* cfData, bool isMutable) noexcept {
    if (cfData == nullptr) {
        return ErrorValue("a DataRef value has no data");
    }
    try {
        return OpaqueValuePtr(std::make_shared<DataRefHolder>(static_cast<CFDataRef>(cfData), isMutable));
    } catch (...) {
        return ErrorValue("failed to allocate a DataRef value");
    }
}

const void* getDataRefObject(const AnyValue* v) noexcept {
    const auto* opaque = v != nullptr ? std::get_if<OpaqueValuePtr>(v) : nullptr;
    const auto* holder = opaque != nullptr ? dynamic_cast<const DataRefHolder*>(opaque->get()) : nullptr;
    return holder != nullptr ? holder->data : nullptr;
}

}
