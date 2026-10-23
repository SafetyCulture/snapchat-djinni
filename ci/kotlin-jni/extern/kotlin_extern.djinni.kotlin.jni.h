// The JNI translator of the extern type extern_kotlin_message, in the form of the translators
// that the s12-proto Go plugin writes: LocalRef handles, a checked ParseFromArray, a RAII
// release of the array elements, and a jniExceptionCheck after each call.
#pragma once
#include "djinni_support.hpp"
#include "kotlin_extern.pb.h"
#include <limits>
#include <memory>
#include <stdexcept>
#include <string>
namespace djinni::kotlin::kotlin_extern::KotlinMessage {
struct JNIInfo {
  const ::djinni::GlobalRef<jclass> clazz { ::djinni::jniFindClass("com/dropbox/djinni/testextern/ExternKotlinMessage")  };
  const jmethodID method_toBytes { ::djinni::jniGetMethodID(clazz.get(), "toByteArray", "()[B") };
  const jmethodID method_fromBytes { ::djinni::jniGetStaticMethodID(clazz.get(), "parseFrom", "([B)Lcom/dropbox/djinni/testextern/ExternKotlinMessage;") };
};

struct Translator {
  using CppType = ::kotlin_extern::KotlinMessage;
  using JniType = jobject;
  using Boxed = Translator;

  static CppType toCpp(JNIEnv* jniEnv, JniType j) {
    assert(j != nullptr);
    const auto& data = ::djinni::JniClass<JNIInfo>::get();
    assert(jniEnv->IsInstanceOf(j, data.clazz.get()));
    ::djinni::LocalRef<jbyteArray> byteArray { static_cast<jbyteArray>(jniEnv->CallObjectMethod(j, data.method_toBytes)) };
    ::djinni::jniExceptionCheck(jniEnv);
    const jsize byte_len = jniEnv->GetArrayLength(byteArray.get());
    auto release = [&](jbyte* elements) { jniEnv->ReleaseByteArrayElements(byteArray.get(), elements, JNI_ABORT); };
    const std::unique_ptr<jbyte, decltype(release)> byte { jniEnv->GetByteArrayElements(byteArray.get(), nullptr), release };
    ::djinni::jniExceptionCheck(jniEnv);
    CppType cpp_message;
    if (byte == nullptr || !cpp_message.ParseFromArray(byte.get(), byte_len)) {
      throw std::runtime_error(std::string("failed to parse protobuf type ") + std::string(cpp_message.GetTypeName()));
    }
    return cpp_message;
  }

  static ::djinni::LocalRef<JniType> fromCpp(JNIEnv* jniEnv, const CppType& message) {
    std::string buffer;
    if (!message.SerializeToString(&buffer) || buffer.size() > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
      throw std::runtime_error(std::string("failed to serialize protobuf type ") + std::string(message.GetTypeName()));
    }
    const auto size = static_cast<jsize>(buffer.size());
    ::djinni::LocalRef<jbyteArray> bytes { jniEnv->NewByteArray(size) };
    ::djinni::jniExceptionCheck(jniEnv);
    jniEnv->SetByteArrayRegion(bytes.get(), 0, size, reinterpret_cast<const jbyte*>(buffer.data()));
    ::djinni::jniExceptionCheck(jniEnv);
    const auto& data = ::djinni::JniClass<JNIInfo>::get();
    ::djinni::LocalRef<JniType> j { jniEnv->CallStaticObjectMethod(data.clazz.get(), data.method_fromBytes, bytes.get()) };
    ::djinni::jniExceptionCheck(jniEnv);
    return j;
  }
};
}  //namespace djinni::kotlin::kotlin_extern::KotlinMessage
