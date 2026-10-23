#pragma once

#include "djinni_support.hpp"
#include "../cpp/DataView.hpp"
#include "../cpp/DataRef.hpp"

namespace djinni::swift {

class DataViewAdaptor
{
public:
    using CppType = DataView;
    static CppType toCpp(const AnyValue& s);
    static AnyValue fromCpp(CppType c);
};

class DataRefAdaptor
{
public:
    using CppType = DataRef;
    static CppType toCpp(const AnyValue& s);
    static AnyValue fromCpp(const CppType& c);
};

// A DataRef value owns one reference to its CFData until the value is destroyed. A conversion that throws before it
// consumes the value therefore does not leak the reference, in both directions.
struct DataRefHolder: OpaqueValue {
    CFDataRef data;
    bool isMutable;
    // Takes a new reference
    DataRefHolder(CFDataRef data, bool isMutable);
    ~DataRefHolder() override;
    DataRefHolder(const DataRefHolder&) = delete;
    DataRefHolder& operator=(const DataRefHolder&) = delete;
};

// Swift callable functions. Neither function throws.
// The value takes its own reference to the CFData, so the caller keeps ownership of the object it passes.
AnyValue makeDataRefValue(const void* cfData, bool isMutable) noexcept;
// The CFData of a DataRef value, or null when the value is not a DataRef value. The value owns the reference, so the
// pointer is valid as long as the value lives. Swift takes its own reference with takeUnretainedValue.
const void* getDataRefObject(const AnyValue* v) noexcept;

}
