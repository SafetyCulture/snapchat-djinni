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
  Swift classes with `async` methods
- `--swift-error-type <name>`: the Swift name of the error record. See below.
- `--swiftxx-out`: output folder for the C++ glue code
- `--swiftxx-namespace`: C++ namespace of the glue code (default: `djinni_generated`)
- `--swiftxx-include-prefix`: path prefix for includes of glue headers
- `--swiftxx-include-cpp-prefix`: path prefix for includes of the main C++ headers
- `--swiftxx-base-lib-module`: Swift module that exposes the support library to
  C++ (default: `DjinniSupportCxx`)
- `--swiftxx-base-lib-include-prefix`: path prefix for includes of the support library
- `--ident-swiftxx-class`, `--ident-swiftxx-file`: identifier styles of the glue code

Swift 6 defaults:

- A record is a `public struct` with `public let` fields and a public memberwise
  `init`.
- Every record is `Sendable`. Swift checks the conformance when every field is
  `Sendable`: primitives, `String`, `Data`, `Date`, enums, records, protobuf
  types, `DJFuture`, and `Result` with `Sendable` arguments. The conformance is
  `@unchecked Sendable` when a field is an interface, `DataRef`, `DataView`, or
  an extern type without a known `Sendable` mapping. This also applies inside
  `optional<>`, `list<>`, `set<>` and `map<>`.
- Enums and flags are `Sendable`. An interface protocol is `AnyObject, Sendable`.
  Every generated proxy class and the shared classes of `DjinniSupport` are `@unchecked Sendable`.
- A host class that implements a `+sw` interface must be `Sendable`. Make it a
  `final` class with immutable state, or mark it `@unchecked Sendable`.
- `deriving(sendable)` adds no Swift conformance. The resolver still requires it
  on field records.

Async wrappers (`--swift-async-wrap`):

- An interface with `+c` and without `+sw` becomes a `public final class`. It has
  the name of the interface, so there is no protocol for it. An interface that
  has `+sw` stays a protocol, because the host implements it.
- The class has one serial `DispatchQueue` with the label
  `<label-prefix>.<interfaceName>`. Every instance method calls C++ on that queue.
  The method is `async throws`, and it returns when C++ returns.
- A C++ exception is never fatal. The generated proxy throws `DjinniError`, and
  the wrapper method gives it to the caller. `DjinniError.errorMessage` is the
  message of the exception. The shim catches `std::exception` and every other
  exception type (the message of the latter is `unknown C++ exception`).
- Without `--swift-error-type`, a method that returns `outcome<T, E>` is
  `async throws -> T`. It throws `E` when C++ returns an error, and
  `DjinniError` when C++ throws.
- A method that returns `future<T>` is `async throws -> T`. It awaits
  `DJFuture.value`. A cancelled task stops waiting and throws `CancellationError`.
  The C++ future is not cancelled. Without `--swift-error-type`, a C++ exception
  that is thrown before the future exists is thrown as `DjinniError`, and a
  promise that C++ rejects later also throws `DjinniError`. With
  `--swift-error-type`, `future<outcome<T, E>>` is rejected at generation.
- Any other method is `async throws -> T`, or `async throws` for a method with no
  return value. It throws `DjinniError` when C++ throws.
- A C++ object has one wrapper, so its calls run one after another on one queue
  (first in, first out). Two values from C++ that name the same object are the
  same Swift object. The callback of a future runs on the queue of the wrapper
  that started the call, not on the actor of the caller. A cancelled task stops
  waiting at once, but a C++ call that already runs on the queue cannot be
  stopped: the queue slot is occupied until C++ returns.
- Static methods stay synchronous, in `<Interface>_statics`.
- The wrapper needs `--swift-private-in-same-module`. The generator stops with an
  error without it.
- A host object that implements a generated protocol must be `Sendable` (the
  protocols are `AnyObject, Sendable`). A host object that lives on the main
  actor conforms with `@MainActor` on the class and `nonisolated` on the
  protocol methods that C++ calls from its own thread; the wrapper hops to the
  main actor itself.

Error type (`--swift-error-type <name>`):

- `<name>` is the Swift name of the error record. For the IDL record
  `crux_error`, the name is `CruxError`.
- Each instance method of an interface with `+c` must return `outcome<T, E>`.
  The Swift name of `E` must be `<name>`. `future<outcome<T, E>>` is not
  allowed: it has two error channels, and a cancelled wait has no `E` to throw.
  If a method breaks the rule, the generator stops before it writes a file. It
  names the interface, the method and the error type it found, and it exits
  with code 1.
- The error record conforms to `Error`. It does not need `deriving(error)`.
- With `--swift-async-wrap`, a method that returns `outcome<T, E>` is
  `async throws(<name>) -> T`. A C++ exception of this method becomes a
  `<name>` value. The error record must conform to
  `DjinniSupport.CppExceptionConvertible`. The generator cannot know a
  meaningful value for every field, so you declare the conformance:

  ```swift
  import DjinniSupport

  extension CruxError: CppExceptionConvertible {
      public init(cppException error: DjinniError) {
          self.init(message: error.errorMessage, code: -1)
      }
  }
  ```

  The wrapper calls `init(cppException:)` with the `DjinniError` of the call.
  `DjinniError.errorMessage` is the message of the exception.
- Declare the conformance in a source file of the module that compiles the
  generated Swift (the module of `--swift-module`). The wrapper needs
  `--swift-private-in-same-module`, so a declaration in another module does not
  help. If the conformance is missing, `swiftc` stops in the generated wrapper
  with the message `global function 'cppOutcome' requires that '<name>' conform
  to 'CppExceptionConvertible'`.
- A static method is exempt, for example a factory. A host interface without
  `+c` is exempt.
- An interface with `+c +sw` is checked, although `--swift-async-wrap` does not
  wrap it.
- An extern record with the Swift name `<name>` is accepted. It must conform to
  `Error` itself.
- The generator also stops when no record has the Swift name `<name>`.
- The check runs only with `--swift-out`. The flag does not depend on
  `--swift-async-wrap`.

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
  queue. A promise that is called twice keeps its first result.
- Known limit: Swift compares strings by canonical equivalence. A `Set` or a
  `Dictionary` with a string key merges two keys that Swift treats as equal,
  such as `"é"` (U+00E9) and `"e\u{301}"`, although C++ treats the byte
  sequences as two keys. The generated types do not change for this.

Extern yaml files have two new blocks. A type without them cannot be used in Swift.

```yaml
swift:
  typename: 'S12_Assets_V1_Asset'
  module: 'S12Protos'
  generic: false
  translator: 'ProtobufMarshaller<S12_Assets_V1_Asset>'
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

- `ci/swift-typecheck.sh` generates Swift for the Crux assets IDL. It runs
  `swiftc -typecheck` in Swift 5 mode and in Swift 6 mode with strict
  concurrency checking, and compiles the C++ glue with `-fsyntax-only`. It does
  the same for the Swift cases of the test suite (`test-suite/djinni/swift_*.djinni`).
- `ci/swift-runtime-test.sh` builds a Swift program with a C++ implementation
  of generated interfaces, and runs it in both Swift modes. The program checks
  calls in both directions, the identity of proxies and the release of host
  objects. It also checks the async wrappers, typed errors, C++ exceptions of
  wrapped methods, Swift errors that C++ catches, task cancellation and many
  threads. A watchdog fails the run when it deadlocks.
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
  `parseFrom(ByteArray)`, the same methods as the JNI translator. Two classes
  with the same simple name need different Parceler names. The generator
  reports them before it writes a file. The Java output does not change.
- `deriving(ord)` on a record with such a field needs a Kotlin class that is
  `Comparable`, as the Java class must be.
- A yaml without the keys gives the same output as before.

### Kotlin coroutines

`--kotlin-suspend-wrap` makes the instance methods of an interface `suspend`
functions. It needs `--kotlin-jni-out` and kotlinx-coroutines in the consumer
module. The classes are tested with kotlinx-coroutines 1.10; the check scripts
select the newest cached jar, and CI pins 1.10.2 (`ci/kotlin-ci.sh`).

- It applies to an interface with `+c` and without `+j`. The JNI code calls only
  the native methods of such an interface. It calls the methods of an interface
  that Kotlin implements (`+j`) by their JVM signature, and a `suspend` function
  has another signature. So an interface with `+j` keeps its normal methods.
- The generated class `CppProxy` runs the native call in
  `withContext(dispatcher)`. The dispatcher is
  `Dispatchers.IO.limitedParallelism(1)`. Each `CppProxy` has its own
  dispatcher, and one C++ object has one `CppProxy`.
- Each C++ object runs one native call at a time. The thread can change between
  calls. The calls to different objects run in parallel. This is the same as the
  queue of the Swift async wrapper. For a `future<T>` method, only the native
  call is serialized: the wait for the result runs outside the dispatcher, so a
  second call can start while the first future is pending.
- Each object that is in a C++ call uses one thread. The 64-thread limit of
  `Dispatchers.IO` does not apply to these views, so N objects that block use
  N threads.
- If a C++ call calls a Kotlin listener, and the listener calls `runBlocking` on
  the same object, the call deadlocks. The object has one slot. The serial queue
  of the Swift async wrapper behaves the same.
- A method that returns `future<T>` is `suspend fun m(): T`. It uses
  `suspendCancellableCoroutine` over `com.snapchat.djinni.Future.then`.
- A cancelled coroutine stops waiting and throws `CancellationException`. A
  result that comes later is dropped. The frame of a cancelled coroutine is
  released before the C++ future completes. **The C++ future is not cancelled.** The Java
  `Future` and the C++ `Future` have no cancel path.
- A cancelled coroutine does not call C++ when the cancel happens before the
  `withContext` block starts. A cancel that comes later cannot stop the native
  call.
- A method that returns `outcome<T, E>` is not unwrapped. It returns
  `com.snapchat.djinni.Outcome<T, E>`.
- `JNI_TRANSLATE_EXCEPTIONS_RETURN` catches every C++ exception and sets a
  `com.snapchat.djinni.DjinniCppException`. It is a subclass of
  `RuntimeException`, so existing `catch (e: RuntimeException)` blocks still
  work. The message is `what()` of a `std::exception`, or `unknown C++
  exception` for any other type. Before this change a `std::exception` gave a
  `RuntimeException`, and any other type stopped the JVM. Without
  `DjinniCppException` on the class path the JNI code sets a `RuntimeException`.
- A failed future throws `DjinniCppException`, also when C++ rejects it with
  an exception that does not derive from `std::exception`, and when the C++
  promise is dropped without a value (`BrokenPromiseException`).
  `--java-cpp-exception` only adds `@Throws`.
- A static method stays a normal method.

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
it selects. `KOTLIN_JNI_CHECK_CRUX=0` skips the Crux assets IDL.

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

- calls from Kotlin to C++ and from C++ to a Kotlin object
- records, enums, outcomes, futures and C++ exceptions, including a promise that C++
  drops and an exception that does not derive from `std::exception`
- the proxy of a C++ object that goes back to C++
- an extern type with the Kotlin keys that goes between its Kotlin class and
  C++, alone, in a list and as an optional field
- an interface that C++ and Kotlin implement
- the release of collected proxies
- many threads

The second program uses the suspend functions of `--kotlin-suspend-wrap`. It
checks these items:

- a `future<>` that completes, fails or has the type `void`
- cancellation while a future waits, and a coroutine that is cancelled before
  the call
- the release of a cancelled coroutine before the future completes
- a late result and a timeout
- the serialisation of the calls to one object
- 1000 concurrent coroutines

The script skips with exit code 77 and a message when one of these parts is
missing:

- `javac`, `java`, `kotlinc` or `clang++`
- `jni.h`, `kotlin-stdlib.jar` or `kotlinx-coroutines-core-jvm.jar`
- a supported system (macOS or Linux)

With `CI` or `KOTLIN_JNI_RUNTIME_REQUIRED` set, a missing part is an error.

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
| `--swift-error-type` with `--swift-legacy-records` and `--swift-async-wrap` | `swift_error` | `swift-features/error-legacy` |
| `--swiftxx-out`, `--swiftxx-include-cpp-prefix` | all Swift cases | `swift-features/*/swiftxx` |
| `--swiftxx-namespace`, `--swiftxx-include-prefix`, `--swiftxx-base-lib-module`, `--swiftxx-base-lib-include-prefix` | `swift_options` | `swift-features/options` |
| `--kotlin-jni-out` | `kotlin_jni` | `kotlin-jni` |
| `--kotlin-jni-package` with `--kotlin-suspend-wrap` | `kotlin_suspend` | `kotlin-jni-package` |
| `--kotlin-suspend-wrap` | `kotlin_suspend` | `kotlin-jni-suspend` |
| `kotlin.jniTypename`, `jni.kotlin*` of an extern type, with `--kotlin-jni-out` and with `--jni-out` alone | `kotlin_extern` | `kotlin-jni-extern/kotlin`, `kotlin-jni-extern/jni`, `kotlin-jni-extern/jni-java` |

`run_djinni.sh` also checks the error cases: `--swift-async-wrap` without
`--swift-private-in-same-module`, `--swift-error-type` with a method that has no
`outcome<>`, `--kotlin-suspend-wrap` without `--kotlin-jni-out`, `--java-out`
with `--kotlin-jni-out` and `--jni-out` for an extern type with the Kotlin keys,
two Kotlin classes with one simple name in a parcelable record, and a Protobuf
message without a `swift` block with `--swift-out` or `--swiftxx-out`. It checks
that the options case imports `--swiftxx-base-lib-module`.

These combinations have no test beyond the checked-in output:

- `--kotlin-jni-package` with a package other than `--java-package`: the JNI code
  binds to the Java names, so no script compiles it.
- `--kotlin-suspend-wrap` with `--jni-use-on-load-initializer true`: the binding
  check runs, the run-time test does not.
- The separate-module case and `--swift-error-type` without `--swift-async-wrap`
  are not run at run time.
- The Parceler of a Kotlin class of an extern type: the `Parcel` of the check is a
  stub that returns null, so no program writes and reads a record. The check
  compiles the generated Kotlin with the Parcelize plugin.
- The typecheck of the options case does not prove `--swiftxx-include-prefix`
  and `--swiftxx-base-lib-module`, because the module map of the case also has
  `DjinniSupportCxx`. The `grep` for the import and the checked-in output cover
  them.

### Swift checks (macOS)

The Swift checks need `swiftc` with the C++ interoperability mode (Xcode 26.5).
The Docker image of the pipeline has no `swiftc`, so the pipeline does not run
them. Run them on a Mac before you merge a change to a Swift file:

```
./ci/swift-typecheck.sh      # also the options case, in Swift 5 and Swift 6 mode
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

The C++ `Future` type has optional support for coroutines. If coroutines are
availble (eg. compiling with C++20 or C++17 with -fcoroutines-ts), then you can
use `co_await` on future objects.

A `Promise` that is destroyed without a value or an exception completes its
future with `djinni::BrokenPromiseException`. A waiter on the other side of
the language boundary then gets an error and does not wait for ever: a Swift
`await` throws `DjinniError`, a Kotlin `suspend` function and a Java
`Future.get` throw `DjinniCppException`. Keep the promise alive until you
complete it. When a second call replaces a stored promise, the future of the
first call breaks. A handler that `Future::then` runs can throw any type. The
future that `then` returns gets the exception, and the completion of the
first future does not fail.

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
