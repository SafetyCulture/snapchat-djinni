package android.os;

import java.io.Serializable;
import java.util.List;
import java.util.Map;

// Only what the generated code and the Parcelize plugin call.
public final class Parcel {
    public String readString() { return null; }
    public byte[] createByteArray() { return null; }
    public long readLong() { return 0; }
    public int readInt() { return 0; }
    public byte readByte() { return 0; }
    public float readFloat() { return 0; }
    public double readDouble() { return 0; }
    public Object readValue(ClassLoader loader) { return null; }
    public Serializable readSerializable() { return null; }
    public <T extends Parcelable> T readParcelable(ClassLoader loader) { return null; }
    public void readList(List outVal, ClassLoader loader) {}
    public void readMap(Map outVal, ClassLoader loader) {}
    public int dataSize() { return 0; }
    public void writeString(String value) {}
    public void writeByteArray(byte[] value) {}
    public void writeLong(long value) {}
    public void writeInt(int value) {}
    public void writeByte(byte value) {}
    public void writeFloat(float value) {}
    public void writeDouble(double value) {}
    public void writeValue(Object value) {}
    public void writeSerializable(Serializable value) {}
    public void writeParcelable(Parcelable value, int flags) {}
    public void writeList(List value) {}
    public void writeMap(Map value) {}
}
