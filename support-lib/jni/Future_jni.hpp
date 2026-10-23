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

#include "djinni_support.hpp"
#include "Marshal.hpp"
#include "../cpp/Future.hpp"

#include <optional>
#include <stdexcept>

namespace djinni {

struct PromiseJniInfo {
    const GlobalRef<jclass> clazz { jniFindClass("com/snapchat/djinni/Promise") };
    const jmethodID constructor { jniGetMethodID(clazz.get(), "<init>", "()V") };
    const jmethodID method_get_future { jniGetMethodID(clazz.get(), "getFuture", "()Lcom/snapchat/djinni/Future;") };
    const jmethodID method_set_value { jniGetMethodID(clazz.get(), "setValue", "(Ljava/lang/Object;)V") };
    const jmethodID method_set_exception { jniGetMethodID(clazz.get(), "setException", "(Ljava/lang/Throwable;)V") };
};

struct FutureJniInfo {
    const GlobalRef<jclass> clazz { jniFindClass("com/snapchat/djinni/Future") };
    const jmethodID method_then { jniGetMethodID(clazz.get(), "then", "(Lcom/snapchat/djinni/Future$FutureHandler;)Lcom/snapchat/djinni/Future;") };
};

struct NativeFutureHandlerJniInfo {
    const GlobalRef<jclass> clazz { jniFindClass("com/snapchat/djinni/NativeFutureHandler") };
    const jmethodID constructor { jniGetMethodID(clazz.get(), "<init>", "(JJ)V") };
};

// DjinniCppException, or RuntimeException when the app does not have that class, as in jniSetPendingFromCurrent.
struct CppExceptionJniInfo {
    const GlobalRef<jclass> clazz { findClass() };
    const jmethodID constructor { jniGetMethodID(clazz.get(), "<init>", "(Ljava/lang/String;)V") };
private:
    static GlobalRef<jclass> findClass() {
        try {
            return jniFindClass("com/snapchat/djinni/DjinniCppException");
        } catch (const std::exception&) {
            return jniFindClass("java/lang/RuntimeException");
        }
    }
};

struct ThrowableJniInfo {
    const GlobalRef<jclass> clazz { jniFindClass("java/lang/Throwable") };
    const jmethodID method_get_message { jniGetMethodID(clazz.get(), "getMessage", "()Ljava/lang/String;") };
    const jmethodID method_to_string { jniGetMethodID(clazz.get(), "toString", "()Ljava/lang/String;") };
};

using NativeFutureHandlerFunc = void (*)(JNIEnv* jniEnv, jlong nativePromise, jobject jres, jthrowable jex);

template<typename T>
struct SetResult {
    static void setCppResult(JNIEnv* jniEnv, Promise<typename T::CppType>& promise, jobject jres) {
        // The conversion runs before the promise is used, so a failure becomes the error of the future. A promise that is
        // dropped without a value would give BrokenPromiseException instead of the cause.
        std::optional<typename T::CppType> value;
        try {
            value.emplace(T::Boxed::toCpp(jniEnv, static_cast<typename T::Boxed::JniType>(jres)));
        } catch (...) {
            promise.setException(std::current_exception());
            return;
        }
        promise.setValue(std::move(*value));
    }
    static void setJavaResult(JNIEnv* jniEnv, const PromiseJniInfo& promiseJniInfo, jobject promise, Future<typename T::CppType>& cppFuture) {
        jniEnv->CallVoidMethod(promise, promiseJniInfo.method_set_value, T::Boxed::fromCpp(jniEnv, cppFuture.get()).get());
    }
};

template<>
struct SetResult<Void> {
    static void setCppResult(JNIEnv* jniEnv, Promise<void>& promise, jobject jres) {
        promise.setValue();
    }
    static void setJavaResult(JNIEnv* jniEnv, const PromiseJniInfo& promiseJniInfo, jobject promise, Future<void>& cppFuture) {
        jniEnv->CallVoidMethod(promise, promiseJniInfo.method_set_value, nullptr);
    }
};

inline LocalRef<jobject> makeJavaException(JNIEnv* jniEnv, const std::string& what) {
    const auto& exceptionJniInfo = JniClass<CppExceptionJniInfo>::get();
    LocalRef<jstring> message;
    try {
        message = String::fromCpp(jniEnv, what);
    } catch (const std::range_error&) {
        // A message that is not valid UTF-8 cannot become a Java string, but the future must still fail.
        message = String::fromCpp(jniEnv, "C++ exception with a message that is not valid UTF-8");
    }
    return LocalRef<jobject>(jniEnv, jniEnv->NewObject(exceptionJniInfo.clazz.get(), exceptionJniInfo.constructor, message.get()));
}

// The promise must fail in every case, or the coroutine that waits for it never resumes. If the JVM cannot make the
// exception, for example with no memory, the promise fails with the exception of the JVM.
inline void setJavaException(JNIEnv* jniEnv, const PromiseJniInfo& promiseJniInfo, jobject promise, const std::string& what) {
    try {
        LocalRef<jobject> jex = makeJavaException(jniEnv, what);
        // If NewObject fails, it gives null and leaves its exception pending.
        jniExceptionCheck(jniEnv);
        jniEnv->CallVoidMethod(promise, promiseJniInfo.method_set_exception, jex.get());
    } catch (const jni_exception& e) {
        jniEnv->CallVoidMethod(promise, promiseJniInfo.method_set_exception, e.java_exception());
    }
}

template <class RESULT>
class FutureAdaptor
{
    using CppResType = typename RESULT::CppType;

    struct PromiseHolder {
        GlobalRef<jobject> promise;

        void set(JNIEnv * env, jobject localRef) {
            promise = GlobalRef<jobject>(env, localRef);
        }
        auto get() const { return promise.get(); }
    };
public:
    using CppType = Future<CppResType>;
    using JniType = jobject;

    using Boxed = FutureAdaptor;

    static CppType toCpp(JNIEnv* jniEnv, JniType j)
    {
        using NativePromiseType = Promise<CppResType>;
            
        auto p = std::make_unique<NativePromiseType>();
        auto f = p->getFuture();

        NativeFutureHandlerFunc FutureHandler = [] (JNIEnv* jniEnv, jlong nativePromise, jobject jres, jthrowable jex) {
            std::unique_ptr<NativePromiseType> promise {
                reinterpret_cast<NativePromiseType*>(nativePromise)
            };
            if (jex == nullptr) {
                SetResult<RESULT>::setCppResult(jniEnv, *promise, static_cast<typename RESULT::Boxed::JniType>(jres));
            } else {
                std::string msg;
                try {
                    const auto& throwableJniInfo = JniClass<ThrowableJniInfo>::get();
                    LocalRef<jstring> jmsg(jniEnv, static_cast<jstring>(jniEnv->CallObjectMethod(jex,
                                                                                                 throwableJniInfo.method_get_message,
                                                                                                 jex)));
                    jniExceptionCheck(jniEnv);
                    if (jmsg.get() == nullptr) {
                        // An exception without a message still says what it is, for example java.lang.NullPointerException
                        jmsg = LocalRef<jstring>(jniEnv, static_cast<jstring>(jniEnv->CallObjectMethod(jex, throwableJniInfo.method_to_string)));
                        jniExceptionCheck(jniEnv);
                    }
                    msg = jniUTF8FromString(jniEnv, jmsg.get());
                } catch (...) {
                    msg = "the Java future failed";
                }
                promise->setException(std::runtime_error(msg));
            }
        };

        const auto& nativeFutureHandlerJniInfo = JniClass<NativeFutureHandlerJniInfo>::get();
        auto handler = LocalRef<jobject>(jniEnv, jniEnv->NewObject(nativeFutureHandlerJniInfo.clazz.get(),
                                                                   nativeFutureHandlerJniInfo.constructor,
                                                                   reinterpret_cast<jlong>(FutureHandler),
                                                                   reinterpret_cast<jlong>(p.release())));
        jniExceptionCheck(jniEnv);
        const auto& futureJniInfo = JniClass<FutureJniInfo>::get();
        jniEnv->CallObjectMethod(j, futureJniInfo.method_then, handler.get());
        jniExceptionCheck(jniEnv);
        return f;
    }

    static LocalRef<JniType> fromCpp(JNIEnv* jniEnv, CppType c)
    {
        const auto& promiseJniInfo = JniClass<PromiseJniInfo>::get();
        // The thread of the call has the class loader of the app. Resolve the exception class here.
        JniClass<CppExceptionJniInfo>::get();

        auto promise = std::make_shared<PromiseHolder>();
        promise->set(jniEnv, jniEnv->NewObject(promiseJniInfo.clazz.get(), promiseJniInfo.constructor));
        auto future = LocalRef<jobject>(jniEnv, jniEnv->CallObjectMethod(promise->get(), promiseJniInfo.method_get_future));
        jniExceptionCheck(jniEnv);

        c.then([promise, &promiseJniInfo] (Future<CppResType> cppFuture) {
            JNIEnv* jniEnv = jniGetThreadEnv();
            try {
                // auto res = cppFuture.get();
                // jniEnv->CallVoidMethod(promise->get(), promiseJniInfo.method_set_value, RESULT::Boxed::fromCpp(jniEnv, res).get());
                SetResult<RESULT>::setJavaResult(jniEnv, promiseJniInfo, promise->get(), cppFuture);
            } catch (const std::exception& e) {
                setJavaException(jniEnv, promiseJniInfo, promise->get(), e.what());
            } catch (...) {
                // An exception that does not derive from std::exception must reach the coroutine too. If it does not,
                // the coroutine waits for ever.
                setJavaException(jniEnv, promiseJniInfo, promise->get(), "unknown C++ exception");
            }
            jniExceptionCheck(jniEnv);
        });
            
        return future;
    }
};

} // namespace djinni
