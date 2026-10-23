#pragma once

#include "djinni_support.hpp"
#include "../cpp/expected.hpp"

namespace djinni::swift {

template<typename RESULT, typename ERROR>
class OutcomeAdaptor {
    using ResultCppType = typename RESULT::CppType;
    using ErrorCppType = typename ERROR::CppType;
public:
    using CppType = expected<ResultCppType, ErrorCppType>;
    static CppType toCpp(const AnyValue& s) {
        auto comp = std::get<CompositeValuePtr>(s);
        // success is one element, failure is two; a void first element can be a
        // success value (outcome<optional<T>, E> with nil)
        if (comp->getSize() == 1) {
            return { RESULT::toCpp(comp->getValue(0)) };
        }
        return make_unexpected(ERROR::toCpp(comp->getValue(1)));
    }
    static AnyValue fromCpp(const CppType& c) {
        auto ret = std::make_shared<CompositeValue>();
        if (c.has_value()) {
            ret->addValue(RESULT::fromCpp(c.value()));
        } else {
            ret->addValue(makeVoidValue());
            ret->addValue(ERROR::fromCpp(c.error()));
        }
        return {ret};
    }
};

}
