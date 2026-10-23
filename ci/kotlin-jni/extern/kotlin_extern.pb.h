#pragma once
#include <cstddef>
#include <cstring>
#include <string>

namespace kotlin_extern {

// Stands in for a generated protobuf message. The bytes are the content.
class KotlinMessage {
public:
    bool ParseFromArray(const void* data, int size) {
        bytes_.assign(static_cast<const char*>(data), static_cast<size_t>(size));
        return true;
    }
    size_t ByteSizeLong() const { return bytes_.size(); }
    bool SerializeToArray(void* data, int size) const {
        std::memcpy(data, bytes_.data(), static_cast<size_t>(size));
        return true;
    }
    // The translator of the Kotlin class uses the string form, the type name and the initialization state.
    bool SerializeToString(std::string* out) const {
        out->assign(bytes_);
        return true;
    }
    std::string GetTypeName() const { return "kotlin_extern.KotlinMessage"; }
    // The golden translator checks that the message is initialized before it serializes it.
    bool IsInitialized() const { return true; }
    std::string InitializationErrorString() const { return ""; }
    bool operator==(const KotlinMessage& other) const { return bytes_ == other.bytes_; }

private:
    std::string bytes_;
};

}  // namespace kotlin_extern
