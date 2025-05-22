BEGIN { in_type = 0; has_kotlin = 0; java_typename = ""; in_java = 0; in_jni = 0; }

# Start of a new type
/^---/ {
  # If we were in a type and it did not have kotlin section, add it
  if (in_type && !has_kotlin && java_typename != "") {
    # Extract the simple typename from the java typename
    split(java_typename, parts, "\\.")
    simple_typename = parts[length(parts)]

    # Create the kotlin package by inserting "krux" after "safetyculture"
    gsub("com.safetyculture", "com.safetyculture.krux", java_typename)
    kotlin_package = java_typename
    gsub("\\.[^.]*$", "", kotlin_package)  # Remove the class name

    print "kotlin:"
    print "  typename: \047" simple_typename "\047"
    print "  package: \047" kotlin_package "\047"
    print "  isProtobufMessage: true"
    print ""
  }

  # Reset for the new type
  in_type = 1
  has_kotlin = 0
  java_typename = ""
  in_java = 0
  print
  next
}

# Check for kotlin section
/^kotlin:/ {
  has_kotlin = 1
  print
  next
}

# Track if we're in the java section
/^java:/ {
  in_java = 1
  print
  next
}

# Capture java typename if we're in the java section
in_java && /^  typename: / {
  java_typename = $2
  gsub("\047", "", java_typename)  # Remove quotes
}

# Track if we're in the jni section
/^jni:/ {
  in_jni = 1
}

# Reset in_java flag when we move to a new section
/^[a-z]+:/ && !/^java:/ {
  in_java = 0
  if (!/^jni:/) {
    in_jni = 0
  }
}

# End of file - check if we need to add kotlin section for the last type
END {
  if (in_type && !has_kotlin && java_typename != "") {
    # Extract the simple typename from the java typename
    split(java_typename, parts, "\\.")
    simple_typename = parts[length(parts)]

    # Create the kotlin package by inserting "krux" after "safetyculture"
    gsub("com.safetyculture", "com.safetyculture.krux", java_typename)
    kotlin_package = java_typename
    gsub("\\.[^.]*$", "", kotlin_package)  # Remove the class name

    print "kotlin:"
    print "  typename: \047" simple_typename "\047"
    print "  package: \047" kotlin_package "\047"
    print "  isProtobufMessage: true"
    print ""
  }
}

# Default action - print the line, but skip blank lines after jni section
{
  if ($0 == "" && in_jni) {
    # Skip blank line after jni section
    in_jni = 0
  } else {
    print
  }
}
