/**
  * Copyright 2021 Snap, Inc.
  *
  * Licensed under the Apache License, Version 2.0 (the "License");
  * you may not use this file except in compliance with the License.
  * You may obtain a copy of the License at
  *
  *    http://www.apache.org/licenses/LICENSE-2.0
  *
  * Unless required by applicable law or agreed to in writing, software
  * distributed under the License is distributed on an "AS IS" BASIS,
  * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  * See the License for the specific language governing permissions and
  * limitations under the License.
  */

#pragma once

#include "DJIMarshal+Private.h"
#import "DJFuture.h"
#import "../cpp/Future.hpp"

#include <optional>
#include <stdexcept>

namespace djinni {

namespace detail {

// Call only from a catch block. In Objective-C++, catch (...) also catches an NSException.
inline NSException* objcExceptionFromCurrent() {
    try {
        throw;
    } catch (NSException* e) {
        return e;
    } catch (const std::exception& e) {
        return [NSException exceptionWithName:@"" reason:String::fromCpp(e.what()) userInfo:nil];
    } catch (...) {
        return [NSException exceptionWithName:@"" reason:@"unknown C++ exception" userInfo:nil];
    }
}

// Call only from a catch block.
inline std::exception_ptr cppExceptionFromCurrent() {
    try {
        throw;
    } catch (NSException* e) {
        return std::make_exception_ptr(std::runtime_error(String::toCpp(e.reason)));
    } catch (...) {
        return std::current_exception();
    }
}

} // namespace detail

template <class RESULT>
class FutureAdaptor
{
    using CppResType = typename RESULT::CppType;

public:
    using CppType = Future<CppResType>;
    using ObjcType = DJFuture*;

    using Boxed = FutureAdaptor;

    static CppType toCpp(ObjcType o)
    {
        using NativePromiseType = Promise<CppResType>;

        __block auto p = std::make_unique<NativePromiseType>();
        auto f = p->getFuture();
        [o then: ^id(DJFuture* res) {
                std::exception_ptr error;
                std::optional<CppResType> value;
                try {
                    value.emplace(RESULT::Boxed::toCpp([res get]));
                } catch (...) {
                    error = detail::cppExceptionFromCurrent();
                }
                if (error) {
                    p->setException(error);
                } else {
                    p->setValue(std::move(*value));
                }
                return nil;
            }];
        return f;
    }

    static ObjcType fromCpp(CppType c)
    {
        DJPromise<typename RESULT::Boxed::ObjcType>* promise = [[DJPromise alloc] init];
        DJFuture<typename RESULT::Boxed::ObjcType>* future = [promise getFuture];

        c.then([promise] (Future<CppResType> res) {
                NSException* error = nil;
                typename RESULT::Boxed::ObjcType value = nil;
                try {
                    value = RESULT::Boxed::fromCpp(res.get());
                } catch (...) {
                    error = detail::objcExceptionFromCurrent();
                }
                if (error) {
                    [promise setException:error];
                } else {
                    [promise setValue:value];
                }
            });
        
        return future;
    }
};

template <>
class FutureAdaptor<Void>
{
public:
    using CppType = Future<void>;
    using ObjcType = DJFuture*;

    using Boxed = FutureAdaptor;

    static CppType toCpp(ObjcType o)
    {
        using NativePromiseType = Promise<void>;

        __block auto p = std::make_unique<NativePromiseType>();
        auto f = p->getFuture();
        [o then: ^id(DJFuture* res) {
                std::exception_ptr error;
                try {
                    [res get];
                } catch (...) {
                    error = detail::cppExceptionFromCurrent();
                }
                if (error) {
                    p->setException(error);
                } else {
                    p->setValue();
                }
                return nil;
            }];
        return f;
    }

    static ObjcType fromCpp(CppType c)
    {
        DJPromise<NSNull*>* promise = [[DJPromise alloc] init];
        DJFuture<NSNull*>* future = [promise getFuture];

        c.then([promise] (Future<void> res) {
                NSException* error = nil;
                try {
                    res.get();
                } catch (...) {
                    error = detail::objcExceptionFromCurrent();
                }
                if (error) {
                    [promise setException:error];
                } else {
                    [promise setValue:[NSNull null]];
                }
            });
        
        return future;
    }
};

} // namespace djinni
