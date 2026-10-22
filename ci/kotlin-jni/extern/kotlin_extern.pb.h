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
    bool operator==(const KotlinMessage& other) const { return bytes_ == other.bytes_; }

private:
    std::string bytes_;
};

}  // namespace kotlin_extern
