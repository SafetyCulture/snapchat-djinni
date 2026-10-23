Real s12 fixtures for the Swift typecheck (`ci/swift-typecheck.sh`). Do not edit by hand;
regenerate from s12-proto.

Source (recorded for reproducibility): s12-proto heads #177 `b225647` on #176 `2bac790`; the
patched image `protobuf/protoc-gen-cruxclient-go/internal/swift/testdata/whitelist.binpb.gz`;
options `swift_module,kotlin_package`.

All 19 `.pb.swift` files come from `internal/swift/testdata/golden/` at `b225647`:
`s12_assets_v1_{action,asset,assets,field,location,maintenance,type,user}.pb.swift`,
`s12_common_{expiry_status,geo_position,measurement_unit,media,money,rpc_status,sorting}.pb.swift`,
`s12_common_v1_status_badge_color.pb.swift`, `s12_subscriptions_v1_common.pb.swift`,
`s12_typefield_v1_{domain,field}.pb.swift`. Swift typenames use the Crux prefix of the package: `S12ASSETS…` (`s12_assets_v1_*`), `S12COM…` (`s12_common_*`), `S12SUBSCRIPTIONS…` and `S12TFD…` (`s12_typefield_v1_*`).

`asset.djinni.yaml` and `asset.djinni.swiftxx.h` are the real #176/#177 yaml and Swift/C++
translator header for APISchema `protos/s12/assets/v1/asset.proto`. The yaml carries `swift:`,
`swiftxx:`, `kotlin.jniTypename` and the `jni.kotlin*` keys; typenames agree with the goldens.

Wired: `ci/swift-typecheck.sh` compiles the `.pb.swift` files into the S12Protos module and
`ci/swift_fixtures.py` copies `asset.djinni.yaml` in place of the synthesised blocks.
Not wired (no script reads them): `asset.djinni.swiftxx.h`, `message.djinni.yaml` and
`message.djinni.kotlin.jni.h`. They are the reference shape for the swiftxx translators and the
Kotlin JNI stub translator (`ci/kotlin-jni/extern/kotlin_extern.djinni.kotlin.jni.h`), and they
land in the checks when the Kotlin extern fixture and the swiftxx stub generator consume them
(decline approved by Main: the wiring of the routeguide sample is deferred because the other Crux
yamls still derive their Swift names in `swift_fixtures.py`; the split is recorded here and in the
PR body of #29).
