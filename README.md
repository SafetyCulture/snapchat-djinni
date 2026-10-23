# Djinni

Djinni is a project originally created by Dropbox that generates bridging code
between C++ and other programming languages. While Dropbox has stopped
maintaining the open source Djinni repository on Github, we at Snapchat have
developed our internal fork since then. After contacting Dropbox, we are now
officially taking over the maintenance of Djinni from Dropbox and will keep
developing it here.

This file only covers the parts that have been changed.  Please see the
[original dropbox readme](README.dropbox.md) for the full Djinni documentation.

## Releases (SafetyCulture fork)

Consumers (crux and mitti-mobile) do not build the generator with Bazel; they download a
prebuilt one. Tagging a commit (`X.Y.Z`) runs the release lane of the repo's
`snapchat-djinni` Buildkite pipeline, which builds the self-contained generator (a
shell stub over a deploy jar, so one file runs on macOS and Linux with just a JVM),
packages it with `support-lib/` as `djinni-generator.tar.gz`, and publishes it to
`s3://sc-mobile-packages/mitti/djinni-generator/v1/<tag>.tar.gz` with a `.sha256`
sidecar. Consumers pin the tag (`deps/snapchat-djinni.pin` in crux) and fetch that key.
To backfill a tag whose push predates tag builds, create a Buildkite build on its commit
with `RELEASE_TAG=<tag>` in the environment.

## Building

![Bazel Build](https://github.com/Snapchat/djinni/workflows/Build%20and%20Test/badge.svg)

Both the Djinni code generator and test suite are built with Bazel. You can use
either plain Bazel or [Bazelisk](https://github.com/bazelbuild/bazelisk).

### Building and running the test suite

`./ci/generate.sh` generates the examples sources.

Use `bazel test //test-suite:djinni-objc-tests //test-suite:djinni-java-tests`
to build and run Objective-C and Java tests.

### Building and running the mobile example apps

The Android example app can be build with bazel: `bazel build
//examples:android-app`, and then install to a device with `adb install
bazel-bin/examples/android-app.apk`

The iOS example app are built with Xcode. Simply open the project in Xcode and
it should work.

### Working on the Djinni code generator

You can load the project via Bazel

- Intellij with the Bazel and Scala plugin is required
- Configure the bazel binary. If you use Bazelisk, set it as the binary in the IDEA bazel settings.
- In Intellij, import a new Bazel project.
    - Workspace directory: `/Users/$HOME/path-to-djinni-directory`
    - Import project view file: `WORKSPACE/bzl/ide/djinni.bazelproject`
- Similarly you can also use CLion if you wish to edit the C++ code
    - You can set up any of the cc_* targets after importing the workspace.

You can also use `bazel build //src:djinni` and `bazel run //src:djinni` to
verify the build and binary from the command line.

## Modifications

 - Replaced sbt and gyp with Bazel
 - Added move assigment operator to GlobalRef in all djinni_support.hpp files
 - Made JniClassInitializer constructor public to allow arbitrary additional initialization in JNI_OnLoad()
 - Speed up string passing between Java and C++ (about 5-10x faster depending on string size)
 - Eliminate CppProxy finalizers (better stability)
 - Injecting code with `DJINNI_FUNCTION_PROLOGUE`
 - Option to generate ObjC protocols
 - Option to generate function prologue
 - Option to omit objc helper methods
 - Option to disable exception translation in ObjC
 - array<> type support
 - outcome<> type support
 - Protobuf type support
 - Local flags with `@flag` directive
 - DataView for copy free data passing
 - DateRef for copy free data passing with ownership
 - Generating string names for C++ enums
 - Bug fixes

## Using new features

### Injecting code to Djinni calls

Two new switches are introduced:

```
--jni-function-prologue-file "path/to/header_file.h"
--objcpp-function-prologue-file "path/to/header_file.h"
```

If they are specified at the command line, then all generated Djinni calls will
contain a macro at the beginning of the bridge function:

```
DJINNI_FUNCTION_PROLOGUE("DjinniInterfaceName.methodName");
```

You should then `#define` the `DJINNI_FUNCTION_PROLOGUE` macro in the specified
header file to inject whatever code you need there.

For example you could make it log the method name. Or you could instantiate a
scoped object to trace the duration of the call.

### Generate all interfaces as ObjC protocols

By default, Djinni only generates interfaces as ObjC `@protocol` when these
interfaces are tagged with `+o`.  Otherwise they become `@interface` in ObjC.

A new switch is introduced to override the default:

`--objc-gen-protocol true`

Enabling this will make all Djinni interfaces `@protocol` in ObjC. This means
you can build your code without linking with the native code implementations,
for example, when you want to mock the interfaces in pure ObjC for testing.

### Prohibit some ObjC helper methods to minimize binary size

You can use `--objc-disable-class-ctor true` to remove the static constructors
from Djinni generated classes.

You can also remove the `description` method in Djinni generated classes by
defining the `DJINNI_DISABLE_DESCRIPTION_METHODS` preprocessor symbol.

These help reducing the binary size of the app slightly.

### Disable C++ exception translation in ObjC

You can use `--objcpp-disable-exception-translation true` to disable the
translation of C++ exceptions to ObjC.  This means ObjC code will see C++
exceptions directly.

This is sometimes preferrable compared to the default behaviour which converts
C++ exceptions to ObjC NSException, because the original exception stack is
preserved.

### outcome<> builtin type

The `outcome<>` type provides a standard way to explicitly define error
conditions in Djinni IDL.  We believe this is a superior approach than throwing
exceptions across language boundaries.

An outcome is defined by combining a "result" type and an "error" type:
```
outcome<RESULT, ERROR>
```
Where RESULT and ERROR can be any Djinni types (primitives or records).


In C++, the `outcome<>` type maps to the template class `djinni::expected<>`.
In Java, it maps to the generic class `com.snapchat.djinni.Outcome<>`. In ObjC,
it maps to the generic class `DJOutcome<>`.

Example:

Use `@extern` directive to include support of `outcome` type to your `idl` file.

```
@extern "../djinni/support-lib/outcome.yaml"

my_interface = interface +c {
    query(): outcome<string, i32>;
}
```

### Use Protobuf types in Djinni

We support using Protobuf types directly in Djinni IDL. In order to use Protobuf
types, you first need to declare them in a yaml manifest file, in which we specify

- How to find the header file and namespace/class/prefix
- List the Protobuf messages you want to use in Djinni

```
cpp:
    header: '"proto/cpp/test.pb.h"'
    namespace: 'djinni::test'
java:
    class: 'djinni.test.Test'
objc:
    header: '"proto/objc/test.pbobjc.h"'
    prefix: 'DJTest'
 
messages:
    - Person
    - AddressBook
```

After that you can reference it in Djinni IDL and use the types as if they are
regular Djinni types:

```
@protobuf "my_proto.yaml"
...
MyRecordWithProto = record {
    // Yay! proto!
    person: Person;
}

MyInterface = interface +c {
   // Yay! proto!
    static foo(x: AddressBook);
}
```

### Optimize primitive array with array<>

The new array<> type is similar to list<>, but optimized for Java primitive
arrays. It is mapped to regular Java arrays (T[]) instead of ArrayList. Since it
doesn't have to box elements as objects, it's order of magnitude faster than
list<> when the element type is primitive.

array<> is identical to list<> in Objective-C because there is no managed
primitive array in Objective-C.

### Local flags with `@flag` directive

In addition to supplying switches on the Djinni command line, it's also possible
to specify them in the idl file with the `@flag` directive.

For example, adding the line

```
@flag "--objc-gen-protocol true"
```

to the djinni idl file will enable generation of objc protocols for
interfaces. This is equivalent to adding the same switches to the djinni command
line.

- Multiple `@flag` lines can appear in the same file.
- `@flag` lines must appear at the top of the djinni idl file before anything
  else.
- `@import`ed files can include `@flag` lines too, and they will apply to the
  parent file. (this means you can put common flags in a file and `@import` it)

### Exposing data across language boundary with DataView

The builtin `binary` type always copies data across language boundary. It is
simple to use but can be expensive when the size of the data is large or when
the same data is passed back and force many times.

The `DataView` type is a viewport into a buffer owned by the other language. It
maps to the custom `DataView` class in C++. In Java it is mapped to
`java.nio.ByteBuffer` (direct buffer). And in Objective-C, it is mapped to
`NSData`.

It is important to keep in mind that `DataView` does not carry ownership. If the
underlying data is destroyed by the owner, then it will point to an invalid
memory location. It is your responsibility to make sure the buffer remains valid
while you use it.

A `DataView` is valid only during the call that gives it to you. This holds
also when the `DataView` is a field of a record or the value of a `future<>`:
the generator accepts such a type, and the buffer behind it is still owned by
the other side. Copy the bytes when you must keep them. In Swift, a record that
has a `DataView` field has no `Sendable` conformance.

### Use DataRef to pass data across language boundary with ownership

`DataRef` is a buffer in Java or Objective-C heap but accessible from C++. It is
also mapped to `java.nio.ByteBuffer` and `NSData`. But unlike `DataView`, it
owns the buffer so destroying the object on one side of the language boundary
does not destroy the underlying buffer as long as the other side still holds it.

Since the underlying data object is in Java or Object-C, it is more expensive to
create than `DataView`. But the ownership allows you to hold on to the object
without worrying about memory safety.

DataRef has a special optimization to take over the data from
`std::vector<uint8_t>` and `std::string`. If you construct a `DataRef` with an
R-value reference of these types, then `DataRef` can steal the buffer from them
without copying the bytes.

### String names for C++ enums

Djinni now generates a `to_string()` function that you can use to convert C++
enums to their string names. This makes printing enums in debugging traces a lot
more convenient. This function is `constexpr` so if you call it with an enum
value known to the compiler at compile time, then there is no runtime
overhead. You may also call it with a dynamic value, in that case it's a fast
array indexing operation.

## WASM support

Djinni can generate code that bridges C++ (that compiles to Web Assembly) and
Javascript/TypeScript in web browsers.

For WASM, Djinni generates:
- C++ code, which should be compiled into the WASM bindary
- TypeScript code, provides optional TypeScript interface definitions

The generated code can be used with both plain Javascript and TypeScript.

New command line switches:

- `--wasm-out`: wasm bridge code output folder
- `--wasm-include-prefix`: path prefix to be added to include lines for WASM
  bridge class header files
- `--wasm-include-cpp-prefix`: path prefix to be added to include lines for main
  C++ class header files
- `--wasm-base-lib-include-prefix`: path prefix to be added to djinni support
  library inlcude lines in generated files
- `--ts-out`: typescript output folder
- `--ts-module`: typescript module(file) name

Almost all Djinni features are supported, including importing external types via
yaml and zero-copy buffer passing.

Notable differences when comparing to the Java/ObjC support:

- deriving(ord, eq) is not applicable to Javascript because JS doesn't support
  overloading standard comparison methods.
- Extended records generate the same code as regular records. Because JS can
  easily add extension methods (by add functions to prototype) without having to
  derive from a base class.

The command to run Wasm/TypeScript unit tests is `bazel run
//test-suite:server-ts`. You will need the `tsc` compiler and the `browserify`
tool to run these tests.

## Swift support

Djinni generates Swift that calls C++ directly, without Objective-C. The Swift
code uses the C++ interoperability mode of the Swift compiler.

For Swift, Djinni generates:
- Swift protocols, structs and enums (`--swift-out`)
- Swift files named `<Type>+Private.swift` with the marshalling code
- C++ glue code that the Swift code calls (`--swiftxx-out`)

The runtime is in `support-lib/swift` (module `DjinniSupport`) and
`support-lib/swiftxx` (C++ module `DjinniSupportCxx`). `support-lib/apple` is a
separate Bazel module that supplies SwiftProtobuf.

Command line switches:

- `--swift-out`: Swift output folder
- `--swift-module`: Swift module name (default: `Module`)
- `--swift-private-in-same-module`: omit `import <module>` in the `+Private`
  files, for use when all generated Swift files are in one module
- `--swift-legacy-records`: generate record fields as `var`. The default is `let`.
- `--swift-async-wrap <label-prefix>`: wrap the interfaces that C++ implements in
  Swift classes with `async` methods. The generator ignores the value.
- `--swift-async-queue <expression>`: the `DispatchQueue` of the blocking C++
  calls of the async wrappers. Each generated file evaluates it once. See below.
- `--swift-error-type <name>`: the Swift name of the error record. See
  [Errors](#errors).
- `--swiftxx-out`: output folder for the C++ glue code
- `--swiftxx-namespace`: C++ namespace of the glue code (default: `djinni_generated_swift`). The generator stops when `--objcpp-out` and `--swiftxx-out` are both on and the two namespaces are equal, because both glue sets would define the same record helpers.
- `--swiftxx-include-prefix`: path prefix for includes of glue headers
- `--swiftxx-include-cpp-prefix`: path prefix for includes of the main C++ headers
- `--swiftxx-base-lib-module`: Swift module that exposes the support library to
  C++ (default: `DjinniSupportCxx`)
- `--swiftxx-base-lib-include-prefix`: path prefix for includes of the support library
- `--ident-swiftxx-class`, `--ident-swiftxx-file`: identifier styles of the glue code

Swift 6 defaults:

- A record is a `public struct` with `public let` fields and a public memberwise
  `init`.
- A record is `Sendable` when it has no `DataRef` and no `DataView` field. Swift
  checks the conformance when every field is `Sendable`: primitives, `String`,
  `Data`, `Date`, enums, records, interfaces, protobuf types, `DJFuture`, and
  `Result` with `Sendable` arguments. The conformance is `@unchecked Sendable`
  when a field is an extern type without a known `Sendable` mapping. This also
  applies inside `optional<>`, `list<>`, `set<>` and `map<>`. A `DataRef` is
  shared, mutable memory, and a `DataView` is memory that C++ owns. A record
  that holds one of them, also inside a container, a `Result`, or another
  record, has no `Sendable` conformance at all. The generated async wrappers
  pass such a value across queues through an unchecked box.
- Known limit: the generator sees the fields of the records of its own IDL only.
  A record of another Djinni module (an extern record of a yaml file) is an
  extern type. So a record that holds it is `@unchecked Sendable`, also when the
  extern record holds a `DataRef` or a `DataView`. Do not put such a record in a
  record of another module.
- Enums and flags are `Sendable`. An interface protocol is `AnyObject, Sendable`.
  Every generated proxy class and the shared classes of `DjinniSupport` are `@unchecked Sendable`.
- A host class that implements a `+sw` interface must be `Sendable`. Make it a
  `final` class with immutable state, or mark it `@unchecked Sendable`.
- `deriving(sendable)` adds no Swift conformance. The resolver still requires it
  on field records.
- A record with `deriving(eq)` is `Equatable` and `Hashable` in Swift, so each
  extern field type must be `Hashable` in Swift. SwiftProtobuf messages are.

Async wrappers (`--swift-async-wrap`):

- An interface with `+c` and without `+sw` becomes a `public final class`. It has
  the name of the interface, so there is no protocol for it. An interface that
  has `+sw` stays a protocol, because the host implements it.
- Every instance method runs its blocking C++ call on a queue of its own: a new
  serial `DispatchQueue` for each call (`DjinniSupport.djinniCallQueue()`, QoS
  `.userInitiated`). libdispatch runs a serial queue on its overcommit threads.
  So a blocked call does not use one of the limited threads of
  `DispatchQueue.global()`, and those threads stay free for the delivery of Swift
  futures. Each blocked call holds one thread. The method is `async throws`, and
  it returns when C++ returns.
- `--swift-async-queue <expression>` sets another `DispatchQueue`, for example a
  queue of the application. The flag needs `--swift-async-wrap`. Write the
  expression on one line, without `/*` or `*/`. Each generated file evaluates the
  expression once, into a private constant. Thus `DispatchQueue(label: "cpp")`
  gives one serial queue for the instance methods of the wrapper of an interface.
  It gives one more serial queue for the static methods of the interface.
- A global queue or a concurrent queue uses the limited threads of libdispatch.
  When C++ blocks on all of these threads, the global queues stop. The delivery
  of Swift futures stops too, so a C++ call that waits for a Swift future does
  not return. The generator does not use the label prefix of
  `--swift-async-wrap`.
- Each wrapper method is `@concurrent`. So it runs on the global concurrent
  executor also when the module uses `NonisolatedNonsendingByDefault`, and not
  on the actor of the caller. The attribute needs Swift 6.2 (Xcode 26) or later.
- A C++ exception is never fatal. Without `--swift-error-type`, the generated
  proxy throws `DjinniError`, and the wrapper method gives it to the caller.
  `DjinniError.errorMessage` is the message of the exception. The shim catches
  `std::exception` and every other exception type (the message of the latter is
  `unknown C++ exception`). With `--swift-error-type`, see [Errors](#errors).
- Without `--swift-error-type`, a method that returns `outcome<T, E>` is
  `async throws -> T`. It throws `E` when C++ returns an error, and
  `DjinniError` when C++ throws.
- A method that returns `future<T>` is `async throws -> T`. It awaits
  `DJFuture.value`. A cancelled task stops waiting and throws `CancellationError`.
  The C++ future is not cancelled. Without `--swift-error-type`, a C++ exception
  that is thrown before the future exists, a promise that C++ rejects later, and
  a promise that C++ drops without a value throw `DjinniError`.
- Any other method is `async throws -> T`, or `async throws` for a method with no
  return value. Without `--swift-error-type`, it throws `DjinniError` when C++
  throws.
- A C++ object has one wrapper. Two values from C++ that name the same object
  are the same Swift object.
- The calls to one C++ object are not serialized. Two calls to the same object
  can run at the same time, so a `cancel()` call does not wait for the blocking
  call that it stops. With `--swift-async-queue`, it waits when the queue has no
  free thread. The C++ object must be thread-safe, as it is for the calls of the
  other languages. An adapter that needs one call at a time must serialize the
  calls itself. Another option is `--swift-async-queue` with a serial queue. That
  queue serializes the calls to all objects of the interface.
- A task that is already cancelled when the method starts throws
  `CancellationError` (with `--swift-error-type`, the `cancellation` value of the
  error type) and does not call C++. A cancel that comes later does not stop the
  C++ call, also when the call still waits on the queue. A method without a
  future waits for the call and returns its result. A future method then throws
  the cancellation, because its wait for the future sees it.
- The caller continues on its own executor when the method returns.
- Static methods stay in `<Interface>_statics` and are synchronous. With
  `--swift-error-type`, a static method that returns a future is `async` (see
  [Errors](#errors)).
- The wrapper needs `--swift-private-in-same-module`. The generator stops with an
  error without it.
- A host object that implements a generated protocol must be `Sendable` (the
  protocols are `AnyObject, Sendable`). C++ calls a host method on a thread of
  C++, and the method is synchronous. Nothing in the generated code moves the
  call to an actor. A host object that lives on the main actor has `@MainActor`
  on the class and `nonisolated` on the protocol methods:
  - A method that returns a value computes it without the main actor, for
    example from state that a lock protects.
  - Do not block on the main actor. `DispatchQueue.main.sync` deadlocks when C++
    calls on the main thread, and `MainActor.assumeIsolated` traps on a thread
    of C++.
  - A method with no return value can start `Task { @MainActor in … }` and
    return.

Error type (`--swift-error-type <name>`): see [Errors](#errors).

IDL changes:

- `+sw` marks a type or a method as implemented in Swift. An interface with no
  language marks has all languages, `+sw` included. An interface can have
  `+o +j +sw`. Then the host implements it in Objective-C, Java and Swift, and
  the generator makes the three host proxies.
- If an interface has `+o` but not `+sw`, the generator prints one warning for
  it with `--swift-out`: `Warning: interface X has +o but not +sw. The generator
  makes no Swift proxy for it.`
- `deriving(hashable, codable, error)` adds the matching Swift conformances.
- A Swift identifier that is a Swift keyword gets backticks, for example
  `` `internal` ``. These names get a trailing `_` because Swift cannot escape
  them in member position: `Type`, `Protocol`, `self`, `Self`, `init`, `deinit`,
  `subscript`. The list is `SwiftIdent` in `SwiftMarshal.scala`.

Runtime safety (Swift):

- No Swift runtime function traps on a C++ value. A C++ value of the wrong kind,
  a composite with too few members and a string that is not valid UTF-8 throw
  `DjinniError`. The C++ helpers that Swift calls do not throw C++ exceptions.
- A C++ method that returns a null pointer for an interface that is not
  optional throws `DjinniError("null value for a non-optional interface")`.
  An optional interface is `nil`.
- A string that is not valid UTF-8 throws. A leading byte order mark stays in
  the string.
- A C++ future whose promise C++ drops (see `BrokenPromiseException`) throws
  `DjinniError`. A C++ exception of any type in a continuation becomes a
  `DjinniError`, and the promise is completed once.
- A `DataRef` value owns its reference to the data until it is destroyed. A
  conversion that throws does not leak it, in both directions.
- `DjinniError` has a `description` and conforms to `LocalizedError`. Both show
  the message of the C++ exception.
- The proxy cache key of a Swift object is its object address and the
  `ObjectIdentifier` of the protocol. Two protocols with the same name in two
  modules do not share a proxy.
- The closure of `Future.getResult` is `@Sendable`, because it runs on a global
  queue when the result comes later. When the future already has its result,
  the closure runs on the thread of the caller, before `getResult` returns. So
  the closure must not take a lock that the caller holds. A promise that is
  called twice keeps its first result.
- Known limit: Swift compares strings by canonical equivalence. A `Set` or a
  `Dictionary` with a string key merges two keys that Swift treats as equal,
  such as `"é"` (U+00E9) and `"e\u{301}"`, although C++ treats the byte
  sequences as two keys. The generated types do not change for this.

Extern yaml files have two new blocks. A type without them cannot be used in Swift.

```yaml
swift:
  typename: 'S12ASSETSAsset'
  module: 'S12Protos'
  generic: false
  translator: 'ProtobufMarshaller<S12ASSETSAsset>'
  translator.module: 'DjinniSupport'
swiftxx:
  translator: 'djinni::swift::s12::assets::v1::Asset::Translator'
  header: '"s12/assets/v1/asset.djinni.swiftxx.h"'
```

Extra keys in the `swift:` block, such as `prefix`, are ignored.

An extern yaml without the `swift:` and `swiftxx:` blocks stops the generator
before it writes a file when `--swift-out` or `--swiftxx-out` is set. The
error names the extern type.

A Protobuf manifest also needs a `swift` block (`module` and `prefix`) when the IDL
uses one of its messages with `--swift-out` or `--swiftxx-out`. If the block is
missing, the generator checks this before it writes a file, prints an error and
exits with 1.

The built-in types `future<>`, `outcome<>`, `DataRef` and `DataView` map to
`DJFuture`, `Result`, and `NSData` (both data types).

Three scripts check the Swift support. They read the Crux IDL from
`MITTI_MOBILE_ROOT`, except for the runtime test.

- `ci/swift-typecheck.sh` generates Swift for the Crux assets IDL. It compiles
  the generated Swift to SIL (`swiftc -emit-sil`) in three modes: Swift 5,
  Swift 6 with strict concurrency checking, and Swift 6 with
  `NonisolatedNonsendingByDefault`. Then it compiles the C++ glue with
  `-fsyntax-only`. `swiftc -typecheck` is not enough: the region-based isolation
  checks of Swift 6 ("sending … risks causing data races") run on SIL. A
  negative case proves that the check runs: two tasks that share the `NSData` of
  a wrapper method must fail. The script does the same for the Swift cases of the
  test suite (`test-suite/djinni/swift_*.djinni`).
  It also compiles the Java, the JNI C++ and the Objective-C++ output of the `+sw`
  host case (`javac`, `clang++ -fsyntax-only`), so the other languages still
  compile next to the Swift files.
  - The `NonisolatedNonsendingByDefault` pass builds `DjinniSupport` without the
    feature, because `DjinniSupport` is a package with its own settings and only
    the modules that use the generated code turn the feature on. The pass proves
    that the generated code and its callers compile in this mode: the test-suite
    files include callers of the async wrappers on the main actor and on an
    actor (`ci/swift-typecheck/AsyncCallers.swift`). It does not prove that
    `@concurrent` is necessary.
  - One more pass generates the whole Crux IDL (`main.djinni`) with
    `--swift-error-type CruxError` and `--swift-async-wrap`, with a `crux_error`
    record that the fixture adds, and typechecks it with a conformance stub.
- `ci/swift-runtime-test.sh` builds a Swift program with a C++ implementation
  of generated interfaces. It runs the program in Swift 5 mode, in Swift 6 mode,
  and in Swift 6 mode with the optimizer. It also runs the program once with
  ThreadSanitizer. The program checks
  calls in both directions, the identity of proxies and the release of host
  objects. It also checks the async wrappers, typed errors, C++ exceptions of
  wrapped methods, Swift errors that C++ catches, task cancellation, the queue of
  `--swift-async-queue`, calls to one object that run at the same time, and many
  threads. A watchdog fails the run when it deadlocks.
  - The program runs twice: with `--swift-async-queue` and with the default
    queue. Each run checks the label of the queue that runs the C++ calls. The
    run with the default queue also starts more blocking calls than the global
    queues of libdispatch have threads (`kern.wq_max_constrained_threads`). Each
    of these calls waits for a Swift future.
  - The typed errors come from two IDL files: `runtime_error.djinni` with
    `--swift-error-type CruxError` and the async wrappers, and
    `runtime_error_sync.djinni` with `--swift-error-type SyncError` and without
    them, so the synchronous protocol and static methods throw the error type
    too.
- `ci/check-byte-identity.sh` proves that a change does not alter the output of
  the other generators.

## Kotlin classes for JNI

`--kotlin-jni-out <dir>` writes Kotlin classes instead of the Java classes. The
JNI code that `--jni-out` writes binds to them without a change. This is
different from `--kotlin-out`, which writes Kotlin Multiplatform code.

- `--kotlin-jni-package <package>` sets the package. The default is the value
  of `--java-package`. It must equal `--java-package` when the JNI code binds the
  classes, because the JNI code has the names of the Java classes.
- The classes have the names of the Java classes, with the nested class
  `CppProxy`. The JVM signatures of the native methods, the constructors and the
  fields are the same as in Java. The JNI code uses only these.
- An interface is an `abstract class` (an `interface` when `--java-gen-interface`
  applies). A native method is `external fun`. A static method is
  `@JvmStatic external fun` in a `companion object`. Kotlin compiles it to a
  static native method in the class, so the JNI function name is the one of
  Java.
- The garbage collector releases the C++ object of a `CppProxy`.
  `NativeObjectManager` registers each proxy and calls `nativeDestroy` after the
  proxy is collected. The class has no `destroy()` or `close()`, the same as the
  Java output. A parameter can have any name, also `destroyed`.
- A record is a `data class` with `val` properties. A record without fields is a
  `class`. A record with `+j` is an `open class`. A record with a `binary` or an
  `array<>` field compares the content of the arrays, as Java does with
  `deriving(eq)`.
- **The name of a property is the name of the Java field.** The JNI code reads
  the fields by the name that `--ident-java-field` makes. With
  `--ident-java-field mFooBar`, the property is `mFooBar`, and Kotlin and Java
  callers use `getMFooBar()`. To get `fooBar` in Kotlin, use
  `--ident-java-field fooBar` for Java, JNI and Kotlin together.
- `--java-implement-android-os-parcelable` becomes `@Parcelize` and `Parcelable`.
  The class has no `Parcel` constructor. The consumer module needs the
  `kotlin-parcelize` plugin.
- A type that is optional is nullable. An interface is nullable, as in Java,
  because the JNI code passes null for it. It is non-null only when
  `--cpp-nn-type` is set. All other types are non-null. `--java-cpp-exception`
  becomes `@Throws`.
- `--java-out` is not changed. You can use both flags, unless an extern type has
  Kotlin keys (see below).

### Two JNI glue sets in one library

One process can carry two JNI glue sets of the same C++ API. The app uses one
leg, and a shared module uses the other. The generator makes the second set with
a second run:

```
java -jar djinni.jar \
  --kotlin-jni-out out/kotlin --java-package com.example.cruxkt.domain \
  --jni-out out/jni/kt --jni-namespace djinni_generated_kt \
  --jni-include-prefix kt/ --idl main.djinni
```

- The second run has no `--java-out` and no `--cpp-out`. It writes only the
  Kotlin JNI classes and the JNI code. The first run writes the Java classes,
  the C++ headers and the JNI code in the default namespace.
- The two namespaces differ, so each glue set has its own C++ classes over the
  same C++ API. The JNI exports differ because the Java packages differ. The
  library exports one set of `Java_*` symbols for each run, and no symbol is
  defined twice.
- `--jni-include-prefix kt/` writes the includes of the second JNI headers for a
  `kt` folder. The JNI output folder is `out/jni/kt`, so compile the second JNI
  code with `out/jni` as the include folder.

The C++ proxy cache keys each entry by the glue class, not by the C++ type. Two
glue sets of one C++ type thus get one Java proxy each. A handle records the tag
that its `get()` used, so the release removes the same entry. With one glue set
the new key maps one to one to the old key, so the behaviour does not change.

Check the library of the two sets:

```
nm -D --defined-only libcrux.so | awk '/ Java_/{print $3}' | sort | uniq -d   # prints nothing
nm -C libcrux.so | grep 'vtable for djinni_generated\|vtable for djinni_generated_kt'  # one vtable for each +j JavaProxy class in each set
```

On macOS, use `nm -gU` in place of `nm -D --defined-only`.

`ci/kotlin-jni-runtime-test.sh` builds one library from two glue sets of
`ci/kotlin-jni/runtime/two_glue.djinni` and checks the two proxies, the cache,
the release and a `+j` object of each leg.

### Extern types with Kotlin keys

An extern record normally has a Java class, and the Kotlin classes use it. An
extern record can also have a pure Kotlin class. Add these optional keys to its
yaml:

```yaml
jni:
  # translator, header and typeSignature stay as they are
  kotlinTranslator: 'djinni::kotlin::s12::assets::v1::Asset::Translator'
  kotlinHeader: '"s12/assets/v1/asset.djinni.kotlin.jni.h"'
  kotlinTypeSignature: 'Lcom/safetyculture/s12kt/assets/v1/Asset;'
kotlin:
  # typename and isProtobufMessage stay as they are
  jniTypename: 'com.safetyculture.s12kt.assets.v1.Asset'
```

- With `--kotlin-jni-out`, the Kotlin classes use `kotlin.jniTypename` for the
  type. A type without the key keeps its Java class. The key does not change
  `kotlin.typename`, which the Kotlin Multiplatform generators read.
- With `--kotlin-jni-out` and `--jni-out`, the JNI code uses `jni.kotlinTranslator`,
  `jni.kotlinHeader` and `jni.kotlinTypeSignature` instead of `jni.translator`,
  `jni.header` and `jni.typeSignature`. The translator binds the Kotlin class, so
  the type signatures of the fields, the constructors and the methods name it.
- The four keys go together. With `--jni-out`, the generator reports an extern
  type that has only some of them, and names the missing keys. With
  `--kotlin-jni-out` alone, no JNI code is written, so it does not check them.
- `jni.kotlinTypeSignature` must name the class of `kotlin.jniTypename`, with
  `/` and `$` read as `.`. The JNI code looks the class up by the signature, and
  the Kotlin classes use the type name, so a mismatch binds two classes. With
  `--jni-out`, the generator reports it before it writes a file.
- The JNI code binds one class for each extern type. A `--jni-out` run binds the
  Kotlin class only when the same run has `--kotlin-jni-out`. Otherwise it binds
  the Java class. So the generator refuses `--java-out`, `--kotlin-jni-out` and
  `--jni-out` together when an extern type has the Kotlin keys. Run it twice:
  `--java-out` with `--jni-out`, and `--kotlin-jni-out` with `--jni-out`.
  The exit code is 1.
- With `--java-implement-android-os-parcelable`, Parcelize cannot write the Kotlin
  class. For a parcelable record with a field of such a type (also in an
  `optional<>`, a `list<>` or a `map<>`), the generator writes the object
  `<Class>Parceler` and the annotation `@TypeParceler<Class, <Class>Parceler>()`
  on the record. The Parceler writes `toByteArray()` and reads
  `parseFrom(ByteArray)`, the same methods as the JNI translator. A `Parcel`
  without a byte array throws `android.os.BadParcelableException`. Two classes
  with the same simple name need different Parceler names. The generator
  reports them before it writes a file. The Java output does not change.
- The generator rejects `deriving(ord)` on a record with such a field, because a
  message has no order and its Kotlin class is not `Comparable`. It exits with
  code 1 before it writes a file. (For the other fields, the resolver already
  rejects `deriving(ord)` over an `optional<>` or a collection.)
- A yaml without the keys gives the same output as before.

### Java and Kotlin JNI converters

An adapter on the legacy leg converts the Java records of the first run to the
Kotlin JNI records of the second run, and back. The generator writes the
converters when two flags are on:

```
java -jar djinni.jar \
  --kotlin-jni-out out/kotlin --java-package com.example.cruxkt.domain \
  --kotlin-jni-java-bridge-out out/bridge \
  --kotlin-jni-java-bridge-package com.example.crux.domain \
  --idl main.djinni
```

- `--kotlin-jni-java-bridge-out <dir>` writes the converters. It needs
  `--kotlin-jni-out`.
- `--kotlin-jni-java-bridge-package <package>` is the value of `--java-package`
  of the other run, whose Java classes the converters use. Each flag needs the
  other. The generator exits 1 and names the missing flag.
- The converters are in the package `<kotlin-jni-package>.javabridge`. Both runs
  must use the same `--ident-java-type`, `--ident-java-method`,
  `--ident-java-enum` and `--java-gen-interface`. The bridge calls the Java
  getters, which follow `--ident-java-method`. `--ident-java-field` names the
  Kotlin properties.
- The files hold extension functions: `fun <java>.R.toKotlinJni(): <kotlin>.R`
  and `fun <kotlin>.R.toJava(): <java>.R`. The converters read the Java fields
  through their getters, and they pass the fields to the constructor in order.
- The field kinds are primitives, `string`, `binary`, `date`, `optional<>`,
  `list<>`, `set<>`, `map<>` (also nested), enums, flags (`EnumSet`) and records.
- An enum converts by option name in an exhaustive `when`.
- An extern type with the same class in the two runs passes through. An extern
  type with two classes must have `kotlin.isProtobufMessage: true`. The
  converter reads `<Target>.parseFrom(value.toByteArray())`. When the yaml has
  neither, the generator exits 1 and names the type.
- A `+j` interface gets `class <J>JavaBridge(private val impl: <kotlin>.J) :
  <java>.J()`, and the reverse `class <J>KotlinBridge`. Each method converts its
  arguments and its return. A `future<>` or an `outcome<>` passes through when no
  inner conversion is needed. Otherwise the bridge converts with `Future.then`
  and `Outcome.match`.
- The bridge keeps one wrapper for each object in a weak identity map. A wrapper
  returns its original object when it crosses back, so a call that adds a
  listener and a call that removes it use the same object. The map removes an
  entry when the source object is collected and the next conversion drains the
  queue. A source that is collected before that leaves one entry until then.
- A `+c` interface without `+j` is not converted; the adapter owns it. A `+c +j`
  interface has wrappers in both directions, like a `+j` interface. A C++ object
  of the Kotlin leg crosses to the Java leg as a wrapper. C++ then sees a
  JavaProxy, not its own object. One launch of the app uses one leg, so the
  adapter never makes this crossing. A record with a field
  of a `+c` interface (also `+c +j`), also inside `optional<>`, `list<>`,
  `set<>` or `map<>`, gets no converter. The same holds for a record that contains such a record.
  The generator prints one line for each skipped record:
  `bridge: skipped <record>: field <f> is a +c interface`. When a record holds a
  skipped record, the line says `bridge: skipped <record>: field <f> holds
  <other>, which is skipped`.
- The generator exits 1 and names the field when the two legs have no common
  form: a `+j` method that takes a record without a converter; a flags type
  inside a container, which is one option in Java and an `EnumSet` in Kotlin; an
  extern type with two classes and no Protobuf marker.
- The generator exits 1 for a `+j` record, an interface with type parameters, and
  a bridge package that equals the Kotlin JNI package. The resolver rejects a
  record with type parameters before the bridge runs.
- `--kotlin-suspend-wrap` is supported. The bridge flags do not change the
  Kotlin JNI output, also with that flag.
- Without the two flags the output does not change. The bridge is a new folder
  only.

### Kotlin coroutines

`--kotlin-suspend-wrap` makes the instance methods of an interface `suspend`
functions. It needs `--kotlin-jni-out` and kotlinx-coroutines 1.9.0 or later in
the consumer module. The classes are tested with kotlinx-coroutines 1.10; the
check scripts select the newest cached jar, and CI pins 1.10.2
(`ci/kotlin-ci.sh`).

- It applies to an interface with `+c` and without `+j`. The JNI code calls only
  the native methods of such an interface. It calls the methods of an interface
  that Kotlin implements (`+j`) by their JVM signature, and a `suspend` function
  has another signature. So an interface with `+j` keeps its normal methods.
- The generated class `CppProxy` runs the blocking native call in
  `withContext(<dispatcher>)`. The dispatcher is `Dispatchers.IO`.
  `--kotlin-suspend-dispatcher <expression>` sets another dispatcher, for
  example the pool of the application. Write the expression on one line, with
  qualified names, and without `/*` or `*/`. The generator adds no import for
  it. Each generated file evaluates the expression once, into a private
  property. Thus `kotlinx.coroutines.Dispatchers.IO.limitedParallelism(1)` runs
  one call at a time for all objects of the interface. The flag needs
  `--kotlin-suspend-wrap`.
- The calls to one C++ object are not serialized. Two calls to the same object
  can run at the same time, so a `cancel()` call does not wait for the blocking
  call that it stops. The C++ object must be thread-safe, as it is for the
  calls of the Java classes. An adapter that needs one call at a time must
  serialize the calls itself.
- Each C++ call that blocks uses one thread of the dispatcher. `Dispatchers.IO`
  runs at most 64 blocking tasks at a time (the system property
  `kotlinx.coroutines.io.parallelism`, or the number of cores when it is
  larger). When 64 calls block, the next call waits for a free thread. A
  `cancel()` call waits too. A `--kotlin-suspend-dispatcher` with an executor
  that has no limit removes the limit. An example is
  `java.util.concurrent.Executors.newCachedThreadPool().asCoroutineDispatcher()`,
  which gives one pool for each generated file. The runtime test uses a
  dispatcher of the application.
- A method that returns `future<T>` is `suspend fun m(): T`. It uses
  `suspendCancellableCoroutine` over `com.snapchat.djinni.Future.then`.
- A cancelled coroutine stops waiting and throws `CancellationException`. A
  result that comes later is dropped. The frame of a cancelled coroutine is
  released before the C++ future completes. **The C++ future is not cancelled.** The Java
  `Future` and the C++ `Future` have no cancel path.
- A cancelled coroutine does not call C++ when the cancel happens before the
  `withContext` block starts. A cancel that comes later cannot stop the native
  call.
- Without `--kotlin-error-type`, a method that returns `outcome<T, E>` is not
  unwrapped. It returns `com.snapchat.djinni.Outcome<T, E>`. With the flag, see
  [Errors](#errors).
- `JNI_TRANSLATE_EXCEPTIONS_RETURN` catches every C++ exception and sets a
  `com.snapchat.djinni.DjinniCppException`. It is a subclass of
  `RuntimeException`, so existing `catch (e: RuntimeException)` blocks still
  work. The message is `what()` of a `std::exception`, or `unknown C++
  exception` for any other type. Before this change a `std::exception` gave a
  `RuntimeException`, and any other type stopped the JVM. Without
  `DjinniCppException` on the class path the JNI code sets a `RuntimeException`.
- A failed future throws `DjinniCppException`, also when C++ rejects it with
  an exception that does not derive from `std::exception`, and when the C++
  promise is dropped without a value (`BrokenPromiseException`). The class of
  a failed future is resolved when the future is converted, on the thread of the
  call. When `DjinniCppException` is not on the class path, a failed future
  throws a `RuntimeException`, as the pending exception does.
  `--java-cpp-exception` only adds `@Throws`.
- Without `--kotlin-error-type`, a static method stays a normal method. With the
  flag, see [Errors](#errors).
- A suspend function cannot override `toString()` or `hashCode()` of `Any`. The
  generator stops with an error for an instance method `to_string()` or
  `hash_code()` without parameters of such an interface. Without the flag, a
  method `to_string(): string` or `hash_code(): i32` overrides the member of
  `Any`, as in Java. With or without the flag, the generator stops with an
  error for such a method that returns another type, and for a static method
  with these names: the Kotlin method cannot override the member of `Any`.

`ci/kotlin-jni-check.sh` generates Java, JNI and Kotlin for the Crux assets IDL
and for the test-suite IDL. It compiles both on the JVM, with `javac` and
`kotlinc` and its Parcelize plugin. Then `ci/kotlin_jni_compare.py` compares
the classes with `javap -p -s`. The script checks these items:

- the classes and the native methods
- the JNI function names
- every class, field and method that the JNI code looks up (also the lookups of
  `support-lib/jni`)
- the `JNINativeMethod` tables with `--jni-use-on-load-initializer`
- the instance fields of the records

The script has a third pass for the suspend functions of
`--kotlin-suspend-wrap`. It compiles the generated Kotlin with
kotlinx-coroutines and runs the same checks. It prints the coroutines jar that
it selects. Two more passes check `--kotlin-error-type`: the test-suite cases
`kotlin_error_sync` and `kotlin_error_async`, and the whole Crux IDL (`main.djinni`)
with `--kotlin-suspend-wrap` and a synthetic `crux_error` record. The natives
keep their JVM names, so the checks are the same. `KOTLIN_JNI_CHECK_CRUX=0`
skips the two Crux passes. The Crux passes remove the Kotlin keys from the copy
of the extern yaml files, because one run with `--java-out` and
`--kotlin-jni-out` binds one class for each extern type.

A fourth pass checks an extern record with the Kotlin keys (`kotlin_extern`).
The script generates Java and the Kotlin classes apart. It compares the Java
classes with the Kotlin classes, with the Kotlin class of the extern type in
place of its Java class. The lookups of the translator of the extern type,
`parseFrom` and `toByteArray`, must bind to the stub class
`ci/kotlin-jni/extern/ExternKotlinMessage.kt`. The pass also compiles parcelable
records with the extern type, alone, in a list, as an optional and in a map,
with the Parcelize plugin.

`ci/kotlin-jni-runtime-test.sh` runs the classes. It builds the generated JNI
C++ and a C++ implementation into a library, and runs Kotlin against it on the
JVM with `-Xcheck:jni`. The script fails when `-Xcheck:jni` prints a warning.
The first program checks these items:

- calls from Kotlin to C++ and from C++ to a Kotlin object, and a Kotlin future
  that C++ waits for, with a value and with a failure that has no message
- records, enums, outcomes, futures and C++ exceptions, including a promise that C++
  drops and an exception that does not derive from `std::exception`
- records with float fields: `equals` and `compareTo` agree with Java (IEEE 754:
  `-0.0` equals `0.0`, and `NaN` equals nothing), `hashCode` gives equal values
  one hash code, and an optional float field compares with `equals`, as in Java
- the proxy of a C++ object that goes back to C++
- an extern type with the Kotlin keys that goes between its Kotlin class and
  C++, alone, in a list and as an optional field
- an interface that C++ and Kotlin implement
- the release of collected proxies
- many threads

The second program uses the suspend functions of `--kotlin-suspend-wrap`. It
runs twice: with the default dispatcher and with `--kotlin-suspend-dispatcher`.
It checks these items:

- a `future<>` that completes, fails or has the type `void`
- cancellation while a future waits, and a coroutine that is cancelled before
  the call
- the release of a cancelled coroutine before the future completes
- a late result and a timeout
- the thread of the dispatcher that runs the C++ call
- calls to one object that run at the same time, and a call that does not wait
  for a blocking call on the same object
- 1000 concurrent coroutines

Two more programs check `--kotlin-error-type`: one with blocking functions
(`runtime_sync.djinni`, which has no future) and one with suspend functions.
They check a value, the error of an outcome, a C++ exception, a failed future, a
promise that C++ drops, static methods, cancellation before the call and while
a future waits (`CancellationException`, not the error type), an interface with
`+c` and `+j` that keeps the raw form, and a Kotlin exception that goes through
C++ and stays as it is.

The script skips with exit code 77 and a message when one of these parts is
missing:

- `javac`, `java`, `kotlinc` or `clang++`
- `jni.h`, `kotlin-stdlib.jar` or `kotlinx-coroutines-core-jvm.jar`
- a supported system (macOS or Linux)

With `CI` or `KOTLIN_JNI_RUNTIME_REQUIRED` set, a missing part is an error.

## Errors

This section tells how a C++ exception, the error of an `outcome<T, E>` and a
cancellation reach Swift and Kotlin, in the synchronous and in the asynchronous
form.

Without an error type:

- Swift: a C++ exception never stops the process. The generated proxy throws
  `DjinniError`, and `DjinniError.errorMessage` is the message of the exception.
  A method that returns `outcome<T, E>` returns `Result<T, E>`. The async
  wrapper method returns `T` and throws `E`. A cancellation throws
  `CancellationError`.
- Kotlin: the JNI code sets `DjinniCppException`, a subclass of
  `RuntimeException`. A method that returns `outcome<T, E>` returns
  `com.snapchat.djinni.Outcome<T, E>`. A cancellation throws
  `CancellationException`.

With an error type, every method that the language calls into C++ throws one
error type:

- `--swift-error-type <name>`: `<name>` is the Swift name of the error record.
  For the IDL record `crux_error`, the name is `CruxError`. The record conforms
  to `Error`; it does not need `deriving(error)`. An extern record with the
  Swift name `<name>` is accepted; it must conform to `Error` itself. The check
  runs only with `--swift-out`. A record that conforms to `Error` cannot hold a
  `DataRef` or a `DataView`. This applies to this record and to a record with
  `deriving(error)`: `Error` is `Sendable` in Swift, and those types are not.
  The generator stops with an error that names the field.
- `--kotlin-error-type <qualified class>`: the class `X` is an `Exception`
  subclass with two constructors, `(error: E)` and
  `(cause: DjinniCppException)`. The flag needs `--kotlin-jni-out`.

The flags apply to these methods:

- Swift: the instance methods of an interface with `+c` and without `+sw`, and
  the static methods of an interface with `+c`. The host implements the
  protocol of an interface with `+c +sw`, so its instance methods keep the form
  without the error type. The Crux IDL has no interface with `+c +sw`.
- Kotlin: the instance methods of an interface with `+c` and without `+j`, and
  the static methods. The JNI code calls the Kotlin methods of an interface with
  `+c +j` by their JVM signature, so they keep the raw form. In the Crux IDL
  that is `sync_engine_observer`, a callback that the application implements.
- The methods of a host interface without `+c` are exempt.

| IDL return type | Swift with `--swift-error-type E` | Kotlin with `--kotlin-error-type X` |
|---|---|---|
| `T` or none | `throws(E) -> T`, or `async throws(E) -> T` in the async wrapper. A C++ exception becomes `E(cppException:)`. | `fun m(): T` (`suspend` with `--kotlin-suspend-wrap`). A C++ exception throws `X(cause: DjinniCppException)`. |
| `outcome<T, E>` | `throws(E) -> T`, or `async throws(E) -> T`. The error of the outcome is thrown as it is. A C++ exception becomes `E(cppException:)`. | `fun m(): T`. The error throws `X(error: E)`. A C++ exception throws `X(cause)`. |
| `future<T>` | `async throws(E) -> T`. It needs `--swift-async-wrap`. A C++ exception, a rejected future and a dropped promise become `E(cppException:)`. | `suspend fun m(): T`. It needs `--kotlin-suspend-wrap`. A C++ exception, a failed future and a dropped promise throw `X(cause)`. |
| `future<outcome<T, E>>` | `async throws(E) -> T`. It needs `--swift-async-wrap`. The error of the outcome is thrown as it is. | `suspend fun m(): T`. It needs `--kotlin-suspend-wrap`. The error throws `X(error: E)`. |

Cancellation:

- Swift: the cancellation becomes `E(cancellation:)`. A task that is already
  cancelled when the method starts does not call C++. A task that is cancelled
  while it waits for a C++ future resumes once with `E(cancellation:)`. The C++
  future is not cancelled, and its late result is dropped.
- Kotlin: the cancellation stays `CancellationException`, and the generated code
  never wraps it. A coroutine that is cancelled before the call does not call
  C++. A cancel while a future waits resumes the coroutine with
  `CancellationException`.

The application declares how its Swift error type holds each failure. The
generator cannot know a value for every field:

```swift
import DjinniSupport

extension CruxError: CppExceptionConvertible {
    public init(cppException error: DjinniError) {
        self.init(message: error.errorMessage, code: -1)
    }
    public init(cancellation: CancellationError) {
        self.init(message: "cancelled", code: -2)
    }
}
```

- Declare the conformance in the module that declares the error type. For an
  IDL record, that is the module of `--swift-module`. For an extern record from
  another module, declare it in that module. If you cannot change that module,
  declare it in the module of `--swift-module` as
  `extension CruxError: @retroactive CppExceptionConvertible`.
- If the conformance is missing, `swiftc` stops in the generated code with a
  message that `<name>` must conform to `CppExceptionConvertible`.
- In Swift, a static method keeps its place in `<Interface>_statics`. A static
  method that returns a future is `async` and runs its C++ call on the queue of
  the async wrappers.
- In Kotlin, a static method is `@JvmStatic fun m(): T` (`suspend` for a
  future). Its native method keeps its JVM name through `@JvmStatic
  @JvmName("m") private external fun native_m`, so the JNI binding does not
  change. The public function has the JVM name `djinni_m`, which only Java
  callers see. Each affected method gets `@Throws(X::class)` (with
  `--java-cpp-exception`, both classes).
- In Kotlin, an exception of Kotlin code that goes through C++ comes back as
  itself, for example an `IllegalStateException` of a listener. A JVM `Error` is
  not wrapped either.

The generator stops before it writes a file, names the interface and the
method, and exits with code 1, in these cases:

- Swift: no record has the Swift name `<name>`, or the record is not a record;
  an `outcome<T, E>` or a `future<outcome<T, E>>` with another `E`; a
  `future<>` method without `--swift-async-wrap`.
- Kotlin: the flag without `--kotlin-jni-out`; a `future<>` method without
  `--kotlin-suspend-wrap`; outcomes with more than one error type, because `X`
  has one `(error: E)` constructor; an affected static or `suspend` function
  named `to_string(): string` or `hash_code(): i32`, because it cannot override
  the method of `Any`. A blocking method with one of these names gets
  `override`.

## Tests for the Swift and Kotlin flags

Each flag has a case in `test-suite/djinni/` and checked-in output.
`./ci/generate.sh` runs the generator over all cases and fails when the output
changes.

| Flag | Case | Output |
|---|---|---|
| `--swift-out`, `--swift-module`, `--swift-private-in-same-module`, `+sw` | `swift_host`, `swift_idents`, `swift_types`, `swift_sendable`, `swift_future_field` | `swift-features/` |
| `--swift-out` without `--swift-private-in-same-module` | `swift_types` | `swift-features/separate-module` |
| `--swift-legacy-records` | `swift_legacy` | `swift-features/legacy` |
| `--swift-async-wrap` | `swift_async` | `swift-features/async` |
| `--swift-error-type` | `swift_error`, `swift_error_enum`, `swift_error_extern`, `swift_error_negative` | `swift-features/error`, `swift-features/error-extern` |
| `--kotlin-error-type`, with and without `--kotlin-suspend-wrap` | `kotlin_error`, `kotlin_error_sync`, `kotlin_error_async`, `kotlin_error_negative`, `kotlin_error_any_negative`, `kotlin_error_any_suspend_negative` | `kotlin-jni-error/sync`, `kotlin-jni-error/suspend` |
| `--swift-error-type` with `--swift-legacy-records`, `--swift-async-wrap` and `--swift-async-queue` | `swift_error` | `swift-features/error-legacy` |
| `--swiftxx-out`, `--swiftxx-include-cpp-prefix` | all Swift cases | `swift-features/*/swiftxx` |
| `--swiftxx-namespace`, `--swiftxx-include-prefix`, `--swiftxx-base-lib-module`, `--swiftxx-base-lib-include-prefix` | `swift_options` | `swift-features/options` |
| `--kotlin-jni-out` | `kotlin_jni` | `kotlin-jni` |
| `--kotlin-jni-package` and `--kotlin-suspend-dispatcher` with `--kotlin-suspend-wrap` | `kotlin_suspend` | `kotlin-jni-package` |
| `--kotlin-suspend-wrap` | `kotlin_suspend` | `kotlin-jni-suspend` |
| `kotlin.jniTypename`, `jni.kotlin*` of an extern type, with `--kotlin-jni-out` and with `--jni-out` alone | `kotlin_extern` | `kotlin-jni-extern/kotlin`, `kotlin-jni-extern/jni`, `kotlin-jni-extern/jni-java` |
| `--kotlin-jni-java-bridge-out`, `--kotlin-jni-java-bridge-package` | `kotlin_jni_java_bridge` | `kotlin-jni-java-bridge/java`, `kotlin-jni-java-bridge/kotlin`, `kotlin-jni-java-bridge/bridge` |
| Two JNI glue sets in one library (runtime) | `two_glue` | none |

`run_djinni.sh` also checks the error cases: `--swift-async-wrap` without
`--swift-private-in-same-module`, `--swift-async-queue` without
`--swift-async-wrap` and with a value that closes a comment,
`--swift-error-type` with an outcome of another error type and with a
`future<>` method without `--swift-async-wrap`, `--kotlin-suspend-wrap` without
`--kotlin-jni-out`, `--kotlin-suspend-dispatcher` without
`--kotlin-suspend-wrap` and with a value that closes a comment,
`--kotlin-error-type` without `--kotlin-jni-out`, with a `future<>` method and
without `--kotlin-suspend-wrap`, with two error types, and with a static or a
suspend method with the name of a member of `Any`, `--java-out`
with `--kotlin-jni-out` and `--jni-out` for an extern type with the Kotlin keys,
two Kotlin classes with one simple name in a parcelable record, and a Protobuf
message without a `swift` block with `--swift-out` or `--swiftxx-out`, equal
`--swiftxx-namespace` and `--objcpp-namespace` with both outputs on, `deriving(ord)`
over the Kotlin class of an extern type with Kotlin keys, and an extern type whose
`jni.kotlinTypeSignature` and `kotlin.jniTypename` name two classes. It checks
the bridge flags: `--kotlin-jni-java-bridge-out` without `--kotlin-jni-out` or
without `--kotlin-jni-java-bridge-package`, `--kotlin-jni-java-bridge-package`
without `--kotlin-jni-java-bridge-out`, a bridge package that equals the Kotlin
JNI package, an extern type with two classes and no Protobuf marker, a flags type
inside a container, a `+j` record, an interface with type parameters, and a `+j`
method that takes a record without a converter. It checks
that every `+Private.swift` file of the options case imports
`--swiftxx-base-lib-module`, and that the warning for an interface with `+o` and
without `+sw` appears once.

These combinations have no test beyond the checked-in output:

- `--kotlin-jni-package` with a package other than `--java-package`: the JNI code
  binds to the Java names, so no script compiles it.
- `--kotlin-suspend-wrap` with `--jni-use-on-load-initializer true`: the binding
  check runs, the run-time test does not.
- The separate-module case is not run at run time.
- The Parceler of a Kotlin class of an extern type: the `Parcel` of the check is a
  stub that returns null, so no program writes and reads a record. The check
  compiles the generated Kotlin with the Parcelize plugin, and checks that the
  Parceler throws `BadParcelableException` for the null byte array.
- The typecheck of the options case does not prove `--swiftxx-include-prefix`
  and `--swiftxx-base-lib-module`, because the module map of the case also has
  `DjinniSupportCxx`. The `grep` for the import and the checked-in output cover
  them.

### Swift checks (macOS)

The Swift checks need `swiftc` with the C++ interoperability mode (Xcode 26.5).
The Docker image of the pipeline has no `swiftc`, so the pipeline does not run
them. Run them on a Mac before you merge a change to a Swift file:

```
./ci/swift-typecheck.sh      # Swift 5, Swift 6, Swift 6 with NonisolatedNonsendingByDefault, and the whole Crux IDL with --swift-error-type
./ci/swift-runtime-test.sh   # also --swift-legacy-records
```

### Kotlin checks (pipeline and local)

The step `Kotlin JNI checks` of the pipeline runs `./ci/kotlin-ci.sh` in the
Docker image. The script downloads a pinned `kotlinc` and a pinned
kotlinx-coroutines jar (SHA-256 sums are in the script), and runs
`kotlin-jni-check.sh` and `kotlin-jni-runtime-test.sh` with `CI=1`, so a
missing tool fails the step. The script uses `g++` and `-include stdexcept`.
On a Mac, run the two scripts with `kotlinc`, `clang++` and a JDK installed.

## Async interface support

With the new yaml type `future<>` we can now write Djinni interfaces that return
results asynchronously more easily.

Instead of writing this:

```
FooCb = interface {
  complete(res: i32): void;
}
Foo = interface {
  bar(cb: FooCb): void;
}
```

We can now write:

(use `@extern` directive to include support of `future` type to your `idl` file)

```
@extern "../djinni/support-lib/future.yaml"

Foo = interface {
  bar(): future<i32>;
}
```

The `future<>` djinni type is mapped to the `Future` types defined in the C++,
Java and ObjC djinni support library. In Javascript, `future<>` is mapped to the
builtin `Promise` type (and therefore supports the `await` syntax).

The C++ `Future` type has optional support for coroutines. It is on when the
compiler defines `__cpp_coroutines` (C++17 with `-fcoroutines-ts` on an older
clang); then you can use `co_await` on future objects. Clang in C++20 mode
defines only `__cpp_impl_coroutine`, so the support is off there.

A `Promise` that is destroyed without a value or an exception completes its
future with `djinni::BrokenPromiseException`. A waiter on the other side of
the language boundary then gets an error and does not wait for ever: a Swift
`await` throws `DjinniError`, a Kotlin `suspend` function throws
`DjinniCppException`, and a Java `Future.get` throws an `ExecutionException`
with a `DjinniCppException` as its cause. Keep the promise alive until you
complete it. When a second call replaces a stored promise, the future of the
first call breaks. A broken promise runs the handlers of its future on the
thread that destroys it, as `setValue` does. So destroy or replace a promise
outside any lock that a handler can take. Move the old promise into a local that
you declare before the lock, as `ci/swift-runtime/runtime_async_impl.cpp` does. A
handler that `Future::then` runs can throw any type. The future that `then`
returns gets the exception, and the completion of the first future does not fail.

## FAQ

Q. Do I need to use Bazel to build my project?

A. No. You may use whatever build system or IDE you like. All you need for your
project is including the generated files in it. We use Bazel to build the code
generator and unit tests, but it's not needed for building user projects. You
still need to have Bazel installed if you want to run the code generator though,
because the run_djinni.sh script indirectly uses it to ensure the code generator
is built and up to date.

Q. Can we include arbitrary bytes in the `string` type?

A. No! iOS and Java strings are unicode, so arbitrary bytes won't necessarily be
able to get translated into such strings.

Q. How many Djinni objects can I have?

A. There is no limit in iOS.  But on Android, JNI has a limit on the number of
global references you can create (usually ~64k). Each `interface` type Djinni
object (either native object in java or java object in native) takes up one
global reference. `record` type objects do not take up global references.
