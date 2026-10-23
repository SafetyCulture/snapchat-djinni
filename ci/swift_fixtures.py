#!/usr/bin/env python3
"""Builds the Swift test fixtures from the Crux IDL.

Copies crux/djinni/domain next to a deps/snapchat-djinni link that points at this
checkout, writes a top-level IDL that imports the requested files, and copies every extern
yaml file those files reach. Each copied protobuf yaml document gets the `swift:` and
`swiftxx:` blocks that the s12 generator writes, with `S12Protos` as the Swift module.
"""
import os
import re
import shutil
import sys


def swift_names(cpp_typename: str) -> tuple[str, str]:
    parts = cpp_typename.split("::")
    ns = [p for p in parts if not p[:1].isupper()]
    msgs = [p for p in parts if p[:1].isupper()]
    return "::".join(ns), "::".join(msgs)


def add_blocks(doc: str) -> str:
    m = re.search(r"^cpp:\n(?:  .*\n)+", doc, re.M)
    t = re.search(r"^  typename: '([^']+)'", m.group(0), re.M) if m else None
    h = re.search(r"^  header: '\"([^\"]+)\.pb\.h\"'", m.group(0), re.M) if m else None
    if not t or not h or "\nswift:" in doc:
        return doc
    ns, msg = swift_names(t.group(1))
    # The Swift name of a message is its Objective-C name (the Crux prefix); a yaml without an
    # objc block cannot name the message
    o = re.search(r"^objc:\n(?:  .*\n)+", doc, re.M)
    ot = re.search(r"^  typename: '([^']+)'", o.group(0), re.M) if o else None
    if not ot:
        raise SystemExit(f"cannot derive the Swift name: the yaml has no objc block ({t.group(1)})")
    typename = ot.group(1)
    block = (
        "swift:\n"
        f"  typename: '{typename}'\n"
        "  module: 'S12Protos'\n"
        "  generic: false\n"
        f"  translator: 'ProtobufMarshaller<{typename}>'\n"
        "  translator.module: 'DjinniSupport'\n"
        "swiftxx:\n"
        f"  translator: 'djinni::swift::{ns}::{msg}::Translator'\n"
        f"  header: '\"{h.group(1)}.djinni.swiftxx.h\"'\n"
    )
    if "\nkotlin:" in doc:
        return doc.replace("\nkotlin:", "\n" + block + "kotlin:", 1)
    return doc.rstrip("\n") + "\n" + block


def main() -> None:
    domain, extern_src, fx, djinni_root, tops = sys.argv[1:6]
    idl_dir = os.path.join(fx, "crux", "djinni", "domain")
    extern_dir = os.path.join(fx, "extern")
    shutil.copytree(domain, idl_dir)
    os.makedirs(os.path.join(fx, "crux", "deps"), exist_ok=True)
    os.symlink(djinni_root, os.path.join(fx, "crux", "deps", "snapchat-djinni"))
    with open(os.path.join(idl_dir, "swift_fixture.djinni"), "w") as f:
        for t in tops.split(","):
            f.write(f'@import "{t}"\n')

    seen, todo, externs = set(), ["swift_fixture.djinni"], set()
    while todo:
        name = todo.pop()
        path = os.path.normpath(os.path.join(idl_dir, name))
        if path in seen:
            continue
        seen.add(path)
        base = os.path.dirname(path)
        for kind, target in re.findall(r'^@(import|extern)\s+"([^"]+)"', open(path).read(), re.M):
            if kind == "import":
                todo.append(os.path.relpath(os.path.join(base, target), idl_dir))
            elif not target.endswith("future.yaml"):
                externs.add(target.lstrip("/"))
    for rel in sorted(externs):
        src = os.path.join(extern_src, rel)
        dst = os.path.join(extern_dir, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        # The assets yaml is the committed real sample; the others get the synthesised blocks
        if os.path.basename(rel) == "asset.djinni.yaml":
            shutil.copy(os.path.join(djinni_root, "ci", "fixtures", "s12", "asset.djinni.yaml"), dst)
            continue
        docs = open(src).read().split("\n---\n")
        with open(dst, "w") as f:
            f.write("\n---\n".join(add_blocks(d) for d in docs))
    print(f"fixture: {len(seen)} idl files, {len(externs)} extern yaml files")


main()
