#!/usr/bin/env python3
"""Writes the stub inputs the Swift typecheck needs.

The SwiftProtobuf messages come from the committed fixtures in ci/fixtures/s12.
cxx-stubs <extern dir> <out dir>
    Headers that stand in for the protobuf C++ headers and the generated message translators.
cxx-header <out.hpp> <swiftxx dir>...
    The declarations the generated Swift calls into, taken from the generated Swift/C++ headers.
"""
import glob
import os
import re
import sys


def cxx_header(out: str, *swiftxx_dirs: str) -> None:
    decls = []
    for path in sorted(p for d in swiftxx_dirs for p in glob.glob(os.path.join(d, "*.h*"))):
        text = open(path).read()
        for name in re.findall(r"^djinni::swift::AnyValue (\w+)\(const djinni::swift::ParameterList\* params\);", text, re.M):
            decls.append(f"djinni::swift::AnyValue {name}(const djinni::swift::ParameterList* params);")
        for proxy in re.findall(r"^class (\w+): public ", text, re.M):
            decls.append(
                f"struct {proxy} {{ static djinni::swift::AnyValue make(void* instance, djinni::swift::DispatchFunc dispatcher); }};"
            )
    namespace = os.environ.get("SWIFTXX_NAMESPACE", "djinni_generated")
    if not re.fullmatch(r"[A-Za-z_]\w*(::[A-Za-z_]\w*)*", namespace):
        raise SystemExit(f"invalid SWIFTXX_NAMESPACE: {namespace!r}")
    with open(out, "w") as f:
        f.write(f'#pragma once\n#include "djinni_support.hpp"\n\nnamespace {namespace} {{\n')
        f.write("\n".join(decls) + "\n}\n")


def cxx_stubs(extern_dir: str, out_dir: str) -> None:
    pb = {}  # pb header -> {typename path tree}
    tr = {}  # swiftxx header -> list of (namespace path, cpp typename)
    for path in glob.glob(os.path.join(extern_dir, "**", "*.yaml"), recursive=True):
        for doc in open(path).read().split("\n---\n"):
            cpp = re.search(r"^cpp:\n  typename: '([^']+)'\n  header: '\"([^\"]+)\"'", doc, re.M)
            sx = re.search(r"^swiftxx:\n  translator: '([^']+)'\n  header: '\"([^\"]+)\"'", doc, re.M)
            if not cpp or not sx:
                continue
            node = pb.setdefault(cpp.group(2), {})
            for part in cpp.group(1).split("::"):
                node = node.setdefault(part, {})
            tr.setdefault(sx.group(2), []).append((sx.group(1), cpp.group(1)))

    def emit(node, depth_is_ns=True):
        lines = []
        for name in sorted(node):
            if name[:1].isupper():
                lines.append(f"struct {name} {{")
                lines += emit(node[name])
                lines.append("};")
            else:
                lines.append(f"namespace {name} {{")
                lines += emit(node[name])
                lines.append("}")
        return lines

    for header, tree in pb.items():
        dst = os.path.join(out_dir, header)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w") as f:
            f.write("#pragma once\n#include <cstddef>\n#include <string>\n" + "\n".join(emit(tree)) + "\n")
    for header, items in tr.items():
        dst = os.path.join(out_dir, header)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "w") as f:
            f.write('#pragma once\n#include "djinni_support.hpp"\n')
            for translator, cpp in items:
                ns = translator.rsplit("::", 1)[0]
                f.write(f"namespace {ns} {{ struct Translator {{ using CppType = ::{cpp};\n")
                f.write("  static CppType toCpp(const djinni::swift::AnyValue&); static djinni::swift::AnyValue fromCpp(const CppType&); }; }\n")


if __name__ == "__main__":
    {"cxx-header": cxx_header, "cxx-stubs": cxx_stubs}[sys.argv[1]](*sys.argv[2:])
