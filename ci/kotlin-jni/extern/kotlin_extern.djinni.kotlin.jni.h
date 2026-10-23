// The JNI translator of the extern type extern_kotlin_message. It has the form of the translators of the Crux
// protobuf messages, with a check for a Java exception after each call.
#pragma once
#include "djinni_support.hpp"
#include "kotlin_extern.pb.h"
namespace djinni::kotlin::kotlin_extern::KotlinMessage {
struct JNIInfo {
  const GlobalRef<jclass> clazz { jniFindClass("com/dropbox/djinni/testextern/ExternKotlinMessage")  };
  const jmethodID method_toBytes { jniGetMethodID(clazz.get(), "toByteArray", "()[B") };
  const jmethodID method_byteSize { jniGetMethodID(clazz.get(), "getSerializedSize", "()I") };
  const jmethodID method_fromBytes { jniGetStaticMethodID(clazz.get(), "parseFrom", "([B)Lcom/dropbox/djinni/testextern/ExternKotlinMessage;") };
};

struct Translator {
  using CppType = ::kotlin_extern::KotlinMessage;
  using JniType = jobject;
  using Boxed = Translator;

  static CppType toCpp(JNIEnv* jniEnv, JniType j) {
    assert(j != nullptr);
    const auto& data = JniClass<JNIInfo>::get();
    assert(jniEnv->IsInstanceOf(j, data.clazz.get()));
    jbyteArray byteArray = static_cast<jbyteArray>(jniEnv->CallObjectMethod(j, data.method_toBytes));
    jniExceptionCheck(jniEnv);
    auto byte_len = jniEnv->CallIntMethod(j, data.method_byteSize);
    jniExceptionCheck(jniEnv);
    jbyte* byte = jniEnv->GetByteArrayElements(byteArray, NULL);
    CppType cpp_message;
    cpp_message.ParseFromArray(byte, byte_len);
    jniEnv->ReleaseByteArrayElements(byteArray, byte, JNI_ABORT);
    jniExceptionCheck(jniEnv);
    return cpp_message;
  }

  static LocalRef<JniType> fromCpp(JNIEnv* jniEnv, const CppType& message) {
    size_t size = message.ByteSizeLong();
    jbyte* temp = new jbyte[size];
    message.SerializeToArray(temp, static_cast<int>(size));
    jbyteArray bytes = jniEnv->NewByteArray(size);
    jniEnv->SetByteArrayRegion(bytes, 0, size, temp);
    delete[] temp;
    const auto& data = JniClass<JNIInfo>::get();
    auto j = LocalRef<JniType>{jniEnv->CallStaticObjectMethod(data.clazz.get(), data.method_fromBytes, bytes)};
    jniExceptionCheck(jniEnv);
    return j;
  }
};
}  //namespace djinni::kotlin::kotlin_extern::KotlinMessage
