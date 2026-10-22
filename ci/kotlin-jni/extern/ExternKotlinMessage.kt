package com.dropbox.djinni.testextern

// The shape of a pure Kotlin message class that the JNI translator of an extern type with Kotlin keys binds.
class ExternKotlinMessage(val bytes: ByteArray) {
    fun toByteArray(): ByteArray = bytes

    fun getSerializedSize(): Int = bytes.size

    override fun equals(other: Any?): Boolean = other is ExternKotlinMessage && bytes.contentEquals(other.bytes)

    override fun hashCode(): Int = bytes.contentHashCode()

    companion object {
        @JvmStatic
        fun parseFrom(bytes: ByteArray): ExternKotlinMessage = ExternKotlinMessage(bytes)
    }
}
