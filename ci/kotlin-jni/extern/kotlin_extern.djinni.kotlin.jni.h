// The JNI translator of the extern type extern_kotlin_message, in the form of the translators that the
// s12-proto Go plugin writes (golden file protoc-gen-cruxclient-go/testdata/routeguide/kotlin/message.djinni.kotlin.jni.h
// at s12-proto a711bbe): a null check and a type check that throw, LocalRef handles, a checked ParseFromArray, a RAII
// release of the array elements, a SAFETY comment for the byte copy, and a jniExceptionCheck after each call.
#pragma once
#include "djinni_support.hpp"
#include "kotlin_extern.pb.h"
#include <cstddef>
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>

namespace djinni::kotlin::kotlin_extern::KotlinMessage {
struct JNIInfo {
  const ::djinni::GlobalRef<jclass> clazz { ::djinni::jniFindClass("com/dropbox/djinni/testextern/ExternKotlinMessage") };
  const jmethodID method_toBytes { ::djinni::jniGetMethodID(clazz.get(), "toByteArray", "()[B") };
  const jmethodID method_fromBytes { ::djinni::jniGetStaticMethodID(clazz.get(), "parseFrom", "([B)Lcom/dropbox/djinni/testextern/ExternKotlinMessage;") };
};

struct Translator {
  using CppType = ::kotlin_extern::KotlinMessage;
  using JniType = jobject;
  using Boxed = Translator;

  static CppType toCpp(JNIEnv* jniEnv, JniType j) {
    if (j == nullptr) {
      throw ::std::runtime_error("expected a non-null Kotlin protobuf message");
    }
    const auto& data = ::djinni::JniClass<JNIInfo>::get();
    const auto isInstance = jniEnv->IsInstanceOf(j, data.clazz.get());
    ::djinni::jniExceptionCheck(jniEnv);
    if (!isInstance) {
      throw ::std::runtime_error("expected a Kotlin protobuf message");
    }
    ::djinni::LocalRef<jbyteArray> byteArray { static_cast<jbyteArray>(jniEnv->CallObjectMethod(j, data.method_toBytes)) };
    ::djinni::jniExceptionCheck(jniEnv);
    const jsize byte_len = jniEnv->GetArrayLength(byteArray.get());
    auto release = [&](jbyte* elements) { jniEnv->ReleaseByteArrayElements(byteArray.get(), elements, JNI_ABORT); };
    const ::std::unique_ptr<jbyte, decltype(release)> byte { jniEnv->GetByteArrayElements(byteArray.get(), nullptr), release };
    ::djinni::jniExceptionCheck(jniEnv);
    CppType cpp_message;
    if (byte == nullptr || !cpp_message.ParseFromArray(byte.get(), byte_len)) {
      throw ::std::runtime_error(::std::string("failed to parse protobuf type ") + ::std::string(cpp_message.GetTypeName()));
    }
    return cpp_message;
  }

  static ::djinni::LocalRef<JniType> fromCpp(JNIEnv* jniEnv, const CppType& message) {
    if (!message.IsInitialized()) {
      throw ::std::runtime_error(::std::string("failed to serialize protobuf type ") +
          ::std::string(message.GetTypeName()) + ": " + message.InitializationErrorString());
    }
    ::std::string buffer;
    if (!message.SerializeToString(&buffer)) {
      throw ::std::runtime_error(::std::string("failed to serialize protobuf type ") + ::std::string(message.GetTypeName()));
    }
    const ::std::size_t size = buffer.size();
    if (size > static_cast<::std::size_t>(::std::numeric_limits<jsize>::max())) {
      throw ::std::runtime_error(::std::string("failed to serialize protobuf type ") + ::std::string(message.GetTypeName()));
    }
    const auto jsizeValue = static_cast<jsize>(size);
    ::djinni::LocalRef<jbyteArray> bytes { jniEnv->NewByteArray(jsizeValue) };
    ::djinni::jniExceptionCheck(jniEnv);
    // SAFETY: jbyte may alias char for this byte copy.
    jniEnv->SetByteArrayRegion(bytes.get(), 0, jsizeValue, reinterpret_cast<const jbyte*>(buffer.data()));
    ::djinni::jniExceptionCheck(jniEnv);
    const auto& data = ::djinni::JniClass<JNIInfo>::get();
    ::djinni::LocalRef<JniType> j { jniEnv->CallStaticObjectMethod(data.clazz.get(), data.method_fromBytes, bytes.get()) };
    ::djinni::jniExceptionCheck(jniEnv);
    return j;
  }
};
}  //namespace djinni::kotlin::kotlin_extern::KotlinMessage
