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
  Every generated class and every class of `DjinniSupport` is `@unchecked Sendable`.
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
  The method is `async`, and it returns when C++ returns.
- A method that returns `outcome<T, E>` is `async throws(E) -> T`.
- A method that returns `future<T>` is `async throws -> T`. It awaits
  `DJFuture.value`. A cancelled task stops waiting and throws `CancellationError`.
  The C++ future is not cancelled. A C++ exception that is thrown before the
  future exists is thrown as `DjinniError`.
- Any other method is `async -> T`. A C++ exception stops the program for these
  methods and for the methods that return `outcome<T, E>`, because the proxy
  methods of these methods do not throw. With `--swift-async-wrap`, every method
  should return `outcome<>`.
- A C++ object has one wrapper, so its calls run one after another on one queue.
  Two values from C++ that name the same object are the same Swift object.
- Static methods stay synchronous, in `<Interface>_statics`.
- The wrapper needs `--swift-private-in-same-module`. The generator stops with an
  error without it.

Error type (`--swift-error-type <name>`):

- `<name>` is the Swift name of the error record. For the IDL record
  `crux_error`, the name is `CruxError`.
- Each instance method of an interface with `+c` must return `outcome<T, E>`,
  or `future<outcome<T, E>>`. The Swift name of `E` must be `<name>`. If not,
  the generator stops before it writes a file. It names the interface, the
  method and the error type it found, and it exits with code 1.
- The error record conforms to `Error`. It does not need `deriving(error)`.
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
  objects. It also checks the async wrappers, typed errors, task cancellation
  and many threads. A watchdog fails the run when it deadlocks.
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
- `--java-out` is not changed. You can use both flags.

`ci/kotlin-jni-check.sh` generates Java, JNI and Kotlin for the Crux assets IDL
and for the test-suite IDL. It compiles both on the JVM, with `javac` and
`kotlinc` and its Parcelize plugin. Then `ci/kotlin_jni_compare.py` compares
the classes with `javap -p -s`. The script checks the classes, the native
methods, the JNI function names, every class, field and method that the JNI
code looks up (also the lookups of `support-lib/jni`), the `JNINativeMethod`
tables with `--jni-use-on-load-initializer`, and the instance fields of the
records.

`ci/kotlin-jni-runtime-test.sh` runs the classes. It builds the generated JNI C++
and a C++ implementation into a library, and runs Kotlin against it on the JVM
with `-Xcheck:jni`. The test calls C++ from Kotlin, calls a Kotlin object from
C++, and checks records, enums, outcomes, futures, C++ exceptions, the proxy of a
C++ object that goes back to C++, an interface that C++ and Kotlin implement, the
release of collected proxies, and many threads. The script skips with exit code
77 and a message when `javac`, `java`, `kotlinc`, `clang++`, `jni.h` or
`kotlin-stdlib.jar` is missing, or the system is not macOS or Linux. With `CI` or
`KOTLIN_JNI_RUNTIME_REQUIRED` set, a missing part is an error.

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
