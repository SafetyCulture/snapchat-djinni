public import Dispatch

// The queue of --swift-async-queue in the Crux check. The application supplies this type.
public enum CruxAsyncQueue {
    public static let shared = DispatchQueue(label: "crux.async", qos: .userInitiated)
}
