#include "Data_swift.hpp"
#include <cassert>

// The DataRef constructors for Apple platforms come from objc/DataRef_objc.cpp, which is plain C++ over CFData.

namespace djinni::swift {

DataView DataViewAdaptor::toCpp(const AnyValue& s) {
    auto range = std::get<RangeValue>(s);
    return DataView(reinterpret_cast<const uint8_t*>(range.bytes), range.size);
}

AnyValue DataViewAdaptor::fromCpp(DataView c) {
    return RangeValue{c.buf(), c.len()};
}

DataRef DataRefAdaptor::toCpp(const AnyValue& s) {
    auto range = std::get<RangeValue>(s);
    auto cfdata = reinterpret_cast<CFDataRef>(range.bytes);
    // The Swift side gives one retained reference. The DataRef retains its own, so release the given one.
    auto result = range.size > 0 ? DataRef(const_cast<CFMutableDataRef>(cfdata)) : DataRef(cfdata);
    CFRelease(cfdata);
    return result;
}

AnyValue DataRefAdaptor::fromCpp(const DataRef& c) {
    // Every Apple backend keeps its bytes in a CFData, so the platform object works for all of them.
    auto cfdata = static_cast<CFDataRef>(c.platformObj());
    if (cfdata == nullptr) {
        cfdata = CFDataCreate(kCFAllocatorDefault, nullptr, 0);
    } else {
        CFRetain(cfdata);
    }
    return RangeValue{reinterpret_cast<const uint8_t*>(cfdata), 0};
}

}
