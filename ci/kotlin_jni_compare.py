#!/usr/bin/env python3
"""Proves that Kotlin classes bind to the JNI code that was generated for the Java classes.

Usage: kotlin_jni_compare.py <java classes dir> <kotlin classes dir> <jni source dir> <package>

The script runs `javap -p -s` on both class trees and checks:
  1. every Java class of the package exists in the Kotlin tree;
  2. each class has the same native methods (name, descriptor, static) in both trees;
  3. the JNI function names of the generated C++ equal the names derived from the Kotlin native methods;
  4. each class, field and method that the generated C++ looks up exists in the Kotlin classes;
  5. each Java record has the same instance fields (name, descriptor) in Kotlin.
"""
import glob
import os
import re
import subprocess
import sys


def class_names(root, package):
    base = os.path.join(root, *package.split("."))
    names = []
    for path in glob.glob(os.path.join(base, "**", "*.class"), recursive=True):
        rel = os.path.relpath(path, root)[: -len(".class")]
        # Anonymous classes, such as the Parcelable creator, are not part of the binding.
        if re.search(r"\$\d+$", rel):
            continue
        names.append(rel.replace(os.sep, "."))
    return sorted(names)


def javap(root, names):
    """Returns {class: {"fields": set, "methods": set}}, where a member is (name, descriptor, flags)."""
    out = subprocess.run(["javap", "-p", "-s", "-cp", root] + names, capture_output=True, text=True, check=True).stdout
    classes, current, pending = {}, None, None
    for line in out.splitlines():
        decl = re.match(r"^(?:\w+ )*(?:class|interface|enum) ([\w.$]+)", line)
        if decl and not line.startswith(" "):
            current = decl.group(1)
            classes[current] = {"fields": set(), "methods": set()}
            continue
        member = re.match(r"^  ([^:]*?);$", line)
        if member and current:
            pending = member.group(1)
            continue
        desc = re.match(r"^    descriptor: (.*)$", line)
        if desc and pending and current:
            text = pending
            flags = set(w for w in text.split("(")[0].split() if w in ("static", "native", "abstract", "private", "final"))
            if "(" in text:
                head = text.split("(")[0].split()[-1]
                short = current.split(".")[-1]
                name = "<init>" if head in (current, short) else head
                if name != "static":
                    classes[current]["methods"].add((name, desc.group(1), tuple(sorted(flags))))
            else:
                name = text.split()[-1]
                classes[current]["fields"].add((name, desc.group(1), tuple(sorted(flags))))
            pending = None
    return classes


def mangle(text):
    return text.replace("_", "_1").replace(".", "_").replace("$", "_00024")


def jni_name(cls, method):
    return "Java_" + mangle(cls) + "_" + mangle(method)


def jni_lookups(jni_dir):
    """Returns the exported function names and the lookups: (class, kind, name, descriptor)."""
    exported, lookups = set(), set()
    for path in sorted(glob.glob(os.path.join(jni_dir, "*"))):
        if not path.endswith((".cc", ".cpp", ".h", ".hpp")):
            continue
        current = None
        for line in open(path):
            exported.update(re.findall(r"JNICALL (Java_\w+)\(", line))
            m = re.search(r'jniFindClass\("([^"]+)"\)', line)
            if m:
                current = m.group(1).replace("/", ".")
            m = re.search(r'jni(GetFieldID|GetMethodID|GetStaticMethodID)\(clazz\.get\(\), "([^"]+)", "([^"]+)"\)', line)
            if m and current:
                lookups.add((current, m.group(1), m.group(2), m.group(3)))
    return exported, lookups


def main():
    java_dir, kotlin_dir, jni_dir, package = sys.argv[1:5]
    java_names = class_names(java_dir, package)
    kotlin_names = class_names(kotlin_dir, package)
    java = javap(java_dir, java_names)
    kotlin = javap(kotlin_dir, kotlin_names)
    failures = []

    missing = [n for n in java_names if n not in kotlin]
    if missing:
        failures.append(f"classes missing in Kotlin: {missing[:5]}")
    print(f"1. classes: {len(java_names)} Java classes, {len(kotlin_names)} Kotlin classes, {len(missing)} missing")

    def natives(info):
        return {(n, d, "static" in f) for (n, d, f) in info["methods"] if "native" in f}

    native_count = 0
    for name in java_names:
        if name not in kotlin:
            continue
        j, k = natives(java[name]), natives(kotlin[name])
        native_count += len(j)
        if j != k:
            failures.append(f"native methods differ in {name}: Java only {sorted(j - k)[:3]}, Kotlin only {sorted(k - j)[:3]}")
    extra = [n for n in kotlin if n not in java and natives(kotlin[n])]
    if extra:
        failures.append(f"natives in classes that Java does not have: {extra}")
    print(f"2. native methods: {native_count} in Java, same name, descriptor and static flag in Kotlin")

    exported, lookups = jni_lookups(jni_dir)
    derived = {jni_name(n, m) for n in kotlin for (m, _, _) in natives(kotlin[n])}
    if derived != exported:
        failures.append(f"JNI function names differ: C++ only {sorted(exported - derived)[:3]}, Kotlin only {sorted(derived - exported)[:3]}")
    print(f"3. JNI functions: {len(exported)} exported by the C++, {len(derived)} derived from the Kotlin natives")

    bad = []
    for cls, kind, name, desc in sorted(lookups):
        info = kotlin.get(cls)
        if info is None:
            bad.append((cls, kind, name, desc, "no class"))
        elif kind == "GetFieldID":
            if not any(n == name and d == desc and "static" not in f for (n, d, f) in info["fields"]):
                bad.append((cls, kind, name, desc, "no field"))
        else:
            static = kind == "GetStaticMethodID"
            if not any(n == name and d == desc and ("static" in f) == static for (n, d, f) in info["methods"]):
                bad.append((cls, kind, name, desc, "no method"))
    if bad:
        failures.append(f"{len(bad)} JNI lookups do not bind, for example {bad[:3]}")
    fields = sum(1 for l in lookups if l[1] == "GetFieldID")
    print(f"4. JNI lookups: {len(lookups)} ({fields} fields, {len(lookups) - fields} methods) bind to the Kotlin classes")

    records = 0
    for name in java_names:
        jf = {(n, d) for (n, d, f) in java[name]["fields"] if "static" not in f}
        kf = {(n, d) for (n, d, f) in kotlin[name]["fields"] if "static" not in f} if name in kotlin else set()
        if jf and "$CppProxy" not in name:
            records += 1
            if jf != kf:
                failures.append(f"instance fields differ in {name}: Java only {sorted(jf - kf)[:3]}, Kotlin only {sorted(kf - jf)[:3]}")
    print(f"5. record fields: {records} classes have the same instance field names and descriptors")

    for failure in failures:
        print("FAIL: " + failure)
    if failures:
        sys.exit(1)
    print("KOTLIN JNI BINDING OK")


main()
