#!/usr/bin/env python3
"""Writes the stub inputs the Swift typecheck needs.

s12protos <extern dir> <out.swift>
    One SwiftProtobuf message stub for every `swift: typename` in the extern yaml files.
cxx-stubs <extern dir> <out dir>
    Headers that stand in for the protobuf C++ headers and the generated message translators.
cxx-header <swiftxx dir> <out.hpp>
    The declarations the generated Swift calls into, taken from the generated Swift/C++ headers.
"""
import glob
import os
import re
import sys

STUB = """    public static let protoMessageName = "stub"
    public static let _protobuf_nameMap = SwiftProtobuf._NameMap()
    public var unknownFields = SwiftProtobuf.UnknownStorage()
    public init() {}
    public mutating func decodeMessage<D: SwiftProtobuf.Decoder>(decoder: inout D) throws {}
    public func traverse<V: SwiftProtobuf.Visitor>(visitor: inout V) throws {}
    public static func == (lhs: Self, rhs: Self) -> Bool { true }
    public func isEqualTo(message: any SwiftProtobuf.Message) -> Bool { true }
"""


def s12protos(extern_dir, out):
    names = set()
    for path in glob.glob(os.path.join(extern_dir, "**", "*.yaml"), recursive=True):
        names.update(re.findall(r"^  typename: '(S12_[^']+)'", open(path).read(), re.M))
    tree = {}
    for name in names:
        node = tree
        for part in name.split("."):
            node = node.setdefault(part, {})

    def emit(node, indent):
        lines = []
        for name in sorted(node):
            pad = "    " * indent
            lines.append(f"{pad}public struct {name}: SwiftProtobuf.Message, @unchecked Sendable {{")
            lines += [pad + l if l else l for l in STUB.splitlines()]
            lines += emit(node[name], indent + 1)
            lines.append(f"{pad}}}")
        return lines

    with open(out, "w") as f:
        f.write("import SwiftProtobuf\n\n" + "\n".join(emit(tree, 0)) + "\n")


def cxx_header(swiftxx_dir, out):
    decls = []
    for path in sorted(glob.glob(os.path.join(swiftxx_dir, "*.h"))):
        text = open(path).read()
        for name in re.findall(r"^djinni::swift::AnyValue (\w+)\(const djinni::swift::ParameterList\* params\);", text, re.M):
            decls.append(f"djinni::swift::AnyValue {name}(const djinni::swift::ParameterList* params);")
        for proxy in re.findall(r"^class (\w+): public ", text, re.M):
            decls.append(
                f"struct {proxy} {{ static djinni::swift::AnyValue make(void* instance, djinni::swift::DispatchFunc dispatcher); }};"
            )
    with open(out, "w") as f:
        f.write('#pragma once\n#include "djinni_support.hpp"\n\nnamespace djinni_generated {\n')
        f.write("\n".join(decls) + "\n}\n")


def cxx_stubs(extern_dir, out_dir):
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
    {"s12protos": s12protos, "cxx-header": cxx_header, "cxx-stubs": cxx_stubs}[sys.argv[1]](*sys.argv[2:])
