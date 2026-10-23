Real s12 fixtures for the Swift/Kotlin checks. Do not edit by hand; regenerate from s12-proto.

Source (recorded for reproducibility): s12-proto heads #177 `b225647` on #176 `2bac790`; the
patched image `protobuf/protoc-gen-cruxclient-go/internal/swift/testdata/whitelist.binpb.gz`;
options `swift_module,kotlin_package`.

- `s12_assets_v1_asset.pb.swift`, `s12_assets_v1_assets.pb.swift`: real #177 Go-plugin Swift
  output (`internal/swift/testdata/golden/` at `b225647`). Swift typenames use the `S12ASSETS…`
  prefix.
- `asset.djinni.yaml`, `asset.djinni.swiftxx.h`: real #176/#177 yaml + Swift/C++ translator
  header for APISchema `protos/s12/assets/v1/asset.proto`. The yaml carries `swift:`,
  `swiftxx:`, `kotlin.jniTypename` and the `jni.kotlin*` keys; typenames agree with the
  goldens above (`S12ASSETS…`, zero `S12_Assets_` hits).
- `message.djinni.yaml`, `message.djinni.kotlin.jni.h`: the routeguide sample from
  `testdata/routeguide/swift/` and `generated-kotlin/routeguide/v1/` at `b225647`; the kotlin
  header is the #176 golden shape for the CI stub translator.
