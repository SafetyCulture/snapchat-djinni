#!/usr/bin/env python3
"""Proves that Kotlin classes bind to the JNI code that was generated for the Java classes.

Usage: kotlin_jni_compare.py <java classes dir> <kotlin classes dir> <jni source dir> <package> [<extra package>] [<java signature>=<kotlin signature>]...

An extra package holds classes that only the Kotlin tree has, such as the Kotlin class of an extern type. The JNI
lookups of these classes are checked. A signature pair replaces a class in the descriptors of the Java classes, so a
record with an extern type that has Kotlin keys has the same descriptors in both trees.

The script runs `javap -p -s` on both class trees and checks:
  1. every Java class of the package exists in the Kotlin tree;
  2. each class has the same native methods (name, descriptor, static) in both trees;
  3. the JNI function names of the generated C++ equal the names derived from the Kotlin native methods;
  4. each class, field and method that the generated C++ looks up exists in the Kotlin classes, and the
     lookups that support-lib/jni makes for each CppProxy class (`<init>(J)V`, `nativeRef`) and each enum
     (`values()`) exist;
  5. each Java record has the same instance fields (name, descriptor) in Kotlin;
  6. with --jni-use-on-load-initializer, the JNINativeMethod tables of the generated C++ list the native
     methods of the Kotlin classes (name and descriptor).

A lookup of a class that the Java tree does not have, such as the hand-written subclass of a record with +j,
is skipped.
"""
import glob
import os
import re
import subprocess
import sys


def class_names(root: str, package: str) -> list[str]:
    base = os.path.join(root, *package.split("."))
    names = []
    for path in glob.glob(os.path.join(base, "**", "*.class"), recursive=True):
        rel = os.path.relpath(path, root)[: -len(".class")]
        # Anonymous classes, such as the Parcelable creator, are not part of the binding.
        if re.search(r"\$\d+$", rel):
            continue
        names.append(rel.replace(os.sep, "."))
    return sorted(names)


def javap(root: str, names: list[str], substitutions=()) -> dict[str, dict]:
    """Returns {class: {"fields": set, "methods": set}}, where a member is (name, descriptor, flags)."""
    out = subprocess.run(["javap", "-p", "-s", "-cp", root] + names, capture_output=True, text=True, check=True).stdout
    classes, current, pending = {}, None, None
    for line in out.splitlines():
        decl = re.match(r"^(?:\w+ )*(?:class|interface|enum) ([\w.$]+)", line)
        if decl and not line.startswith(" "):
            current = decl.group(1)
            classes[current] = {"fields": set(), "methods": set(), "enum": "extends java.lang.Enum" in line}
            continue
        member = re.match(r"^  ([^:]*?);$", line)
        if member and current:
            pending = member.group(1)
            continue
        desc = re.match(r"^    descriptor: (.*)$", line)
        if desc and pending and current:
            descriptor = desc.group(1)
            for java_sig, kotlin_sig in substitutions:
                descriptor = descriptor.replace(java_sig, kotlin_sig)
            text = pending
            flags = set(w for w in text.split("(")[0].split() if w in ("static", "native", "abstract", "private", "final"))
            if "(" in text:
                head = text.split("(")[0].split()[-1]
                short = current.split(".")[-1]
                name = "<init>" if head in (current, short) else head
                if name != "static":
                    classes[current]["methods"].add((name, descriptor, tuple(sorted(flags))))
            else:
                name = text.split()[-1]
                classes[current]["fields"].add((name, descriptor, tuple(sorted(flags))))
            pending = None
    return classes


def mangle(text: str) -> str:
    return text.replace("_", "_1").replace(".", "_").replace("$", "_00024")


def jni_name(cls: str, method: str) -> str:
    return "Java_" + mangle(cls) + "_" + mangle(method)


def jni_lookups(jni_dir: str) -> tuple[set[str], set[tuple[str, str, str, str]], list[str]]:
    """Returns the exported function names, the lookups (class, kind, name, descriptor) and the unparsed lookups.

    A line that calls jniGetFieldID, jniGetMethodID or jniGetStaticMethodID counts as one lookup. Every one of
    them must match the parser and follow a jniFindClass, so a change in the shape of the generated C++ cannot
    turn a lookup into a silent skip."""
    exported, lookups, unparsed = set(), set(), []
    call = re.compile(r"\bjni(?:GetFieldID|GetMethodID|GetStaticMethodID)\s*\(")
    for path in sorted(glob.glob(os.path.join(jni_dir, "*"))):
        if not path.endswith((".cc", ".cpp", ".h", ".hpp")):
            continue
        current = None
        for number, line in enumerate(open(path), 1):
            exported.update(re.findall(r"JNICALL (Java_\w+)\(", line))
            m = re.search(r'jniFindClass\("([^"]+)"\)', line)
            if m:
                current = m.group(1).replace("/", ".")
            m = re.search(r'jni(GetFieldID|GetMethodID|GetStaticMethodID)\s*\(\s*clazz\.get\(\)\s*,\s*"([^"]+)"\s*,\s*"([^"]+)"\s*\)', line)
            if m and current:
                lookups.add((current, m.group(1), m.group(2), m.group(3)))
            elif call.search(line):
                unparsed.append(f"{os.path.basename(path)}:{number}: {line.strip()}")
    return exported, lookups, unparsed


def native_tables(jni_dir: str) -> tuple[dict[str, set[tuple[str, str]]], list[str]]:
    """Returns ({class: {(name, descriptor)}}, problems) from the JNINativeMethod tables of the generated C++.

    The tables are in the files of the types. The registrations are in the module file. So the function
    reads all tables first and the registrations second."""
    entry = re.compile(r'const_cast<char\*>\("([^"]+)"\),\s*const_cast<char\*>\("([^"]+)"\)')
    texts = [open(path).read() for path in sorted(glob.glob(os.path.join(jni_dir, "*")))
             if path.endswith((".cc", ".cpp", ".h", ".hpp"))]
    tables = {}
    for text in texts:
        for name, body in re.findall(r"const JNINativeMethod (\w+)\[[^\]]*\]\s*=\s*\{(.*?)\};", text, re.S):
            tables[name] = set(entry.findall(body))
    registrations, problems = {}, []
    for text in texts:
        found = re.findall(r'jniRegisterNatives\(env, "([^"]+)", (\w+)\)', text)
        found += re.findall(r'JNIMethodLoadAutoRegister\w* \w+\("([^"]+)", (\w+)\)', text)
        for cls, table in found:
            if not tables.get(table):
                problems.append(f"the table {table} of {cls} is unknown or empty")
                continue
            registrations.setdefault(cls.replace("/", "."), set()).update(tables[table])
    return registrations, problems


def main() -> None:
    java_dir, kotlin_dir, jni_dir, package = sys.argv[1:5]
    extra_packages = [a for a in sys.argv[5:] if "=" not in a]
    substitutions = [tuple(a.split("=", 1)) for a in sys.argv[5:] if "=" in a]
    java_names = class_names(java_dir, package)
    kotlin_names = class_names(kotlin_dir, package)
    java = javap(java_dir, java_names, substitutions)
    kotlin = javap(kotlin_dir, kotlin_names + [n for p in extra_packages for n in class_names(kotlin_dir, p)])
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

    exported, lookups, unparsed = jni_lookups(jni_dir)
    # With no parsed lookups, checks 4-6 check nothing
    if not lookups:
        failures.append("no JNI field or method lookups found in the generated C++")
    if unparsed:
        failures.append(f"{len(unparsed)} JNI lookups are not parsed, for example {unparsed[:3]}")
    registrations, table_problems = native_tables(jni_dir)
    failures.extend(table_problems)
    derived = {jni_name(n, m) for n in kotlin for (m, _, _) in natives(kotlin[n])}
    # A native method that is only registered in a table, such as the module guard, has no exported function.
    registered_only = {jni_name(c, n) for c, listed in registrations.items() for (n, _) in listed} - exported
    if exported - derived or derived - exported - registered_only:
        failures.append(f"JNI function names differ: C++ only {sorted(exported - derived)[:3]}, Kotlin only {sorted(derived - exported - registered_only)[:3]}")
    print(f"3. JNI functions: {len(exported)} exported by the C++, {len(derived)} derived from the Kotlin natives ({len(derived - exported)} registered only)")

    bad, skipped = [], 0
    for cls, kind, name, desc in sorted(lookups):
        if cls not in java and cls not in kotlin:
            skipped += 1
            continue
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
    # The lookups of support-lib/jni for each CppProxy class and each enum.
    fixed = 0
    for name in java_names:
        info = kotlin.get(name)
        if info is None:
            continue
        if name.endswith("$CppProxy"):
            fixed += 2
            if not any(n == "<init>" and d == "(J)V" for (n, d, f) in info["methods"]):
                failures.append(f"{name} has no constructor (J)V")
            if not any(n == "nativeRef" and d == "J" for (n, d, f) in info["fields"]):
                failures.append(f"{name} has no field nativeRef J")
        if java[name]["enum"]:
            fixed += 1
            wanted = f"()[L{name.replace('.', '/')};"
            if not any(n == "values" and d == wanted and "static" in f for (n, d, f) in info["methods"]):
                failures.append(f"{name} has no static values() {wanted}")
    print(f"4. JNI lookups: {len(lookups) - skipped} ({fields} fields, {len(lookups) - fields} methods) of the generated C++ and {fixed} of support-lib/jni bind to the Kotlin classes ({skipped} skipped)")

    records = 0
    for name in java_names:
        jf = {(n, d) for (n, d, f) in java[name]["fields"] if "static" not in f}
        kf = {(n, d) for (n, d, f) in kotlin[name]["fields"] if "static" not in f} if name in kotlin else set()
        if jf and "$CppProxy" not in name:
            records += 1
            if jf != kf:
                failures.append(f"instance fields differ in {name}: Java only {sorted(jf - kf)[:3]}, Kotlin only {sorted(kf - jf)[:3]}")
    print(f"5. record fields: {records} classes have the same instance field names and descriptors")

    if registrations:
        entries = 0
        for cls, listed in sorted(registrations.items()):
            info = kotlin.get(cls)
            if info is None:
                failures.append(f"registered class {cls} is missing in Kotlin")
                continue
            have = {(n, d) for (n, d, f) in info["methods"] if "native" in f}
            have_java = {(n, d) for (n, d, f) in java[cls]["methods"] if "native" in f} if cls in java else None
            entries += len(listed)
            # An entry that the Java class lacks too, such as a static method of another language, is not a Kotlin error.
            missing = listed - have - (listed - have_java if have_java is not None else set())
            if missing:
                failures.append(f"JNINativeMethod entries without a Kotlin native in {cls}: {sorted(missing)[:3]}")
        print(f"6. JNINativeMethod tables: {entries} entries of {len(registrations)} classes match the Kotlin natives")
    else:
        print("6. JNINativeMethod tables: none (the JNI code is bound by name)")

    for failure in failures:
        print("FAIL: " + failure)
    if failures:
        sys.exit(1)
    print("KOTLIN JNI BINDING OK")


main()
