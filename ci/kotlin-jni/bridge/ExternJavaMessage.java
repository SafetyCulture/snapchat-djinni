package com.dropbox.djinni.testextern;

import java.util.Arrays;

// The shape of a Java message class that the bridge of an extern type reads through toByteArray and parseFrom.
public final class ExternJavaMessage {
    private final byte[] bytes;

    public ExternJavaMessage(byte[] bytes) {
        this.bytes = bytes.clone();
    }

    public byte[] toByteArray() {
        return bytes.clone();
    }

    public static ExternJavaMessage parseFrom(byte[] bytes) {
        return new ExternJavaMessage(bytes);
    }

    @Override
    public boolean equals(Object other) {
        return other instanceof ExternJavaMessage && Arrays.equals(bytes, ((ExternJavaMessage) other).bytes);
    }

    @Override
    public int hashCode() {
        return Arrays.hashCode(bytes);
    }
}
