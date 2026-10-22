#!/usr/bin/env python3
"""Writes Java stubs for the extern record types of the yaml files, so the generated classes compile.

Usage: kotlin_jni_stubs.py <extern dir> <out dir>
"""
import glob
import os
import re
import sys


def main():
    extern_dir, out = sys.argv[1:3]
    names = set()
    for path in glob.glob(os.path.join(extern_dir, "**", "*.yaml"), recursive=True):
        for doc in open(path).read().split("\n---\n"):
            m = re.search(r"^java:\n  typename: '([^']+)'", doc, re.M)
            if m and "." in m.group(1):
                names.add(m.group(1))
    tree = {}
    for name in names:
        parts = name.split(".")
        pkg = [p for p in parts if p[:1].islower()]
        classes = [p for p in parts if p[:1].isupper()]
        if not classes:
            continue
        node = tree.setdefault(".".join(pkg), {})
        for c in classes:
            node = node.setdefault(c, {})

    def emit(node, indent, nested):
        lines = []
        for cls in sorted(node):
            pad = "    " * indent
            static = "static " if nested else ""
            lines.append(f"{pad}public {static}class {cls} implements android.os.Parcelable {{")
            lines.append(f"{pad}    public {cls}(android.os.Parcel in) {{}}")
            lines.append(f"{pad}    public int describeContents() {{ return 0; }}")
            lines.append(f"{pad}    public void writeToParcel(android.os.Parcel out, int flags) {{}}")
            lines += emit(node[cls], indent + 1, True)
            lines.append(f"{pad}}}")
        return lines

    for pkg, classes in tree.items():
        for cls in classes:
            d = os.path.join(out, *pkg.split("."))
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, cls + ".java"), "w") as f:
                f.write(f"package {pkg};\n\n" + "\n".join(emit({cls: classes[cls]}, 0, False)) + "\n")


main()
