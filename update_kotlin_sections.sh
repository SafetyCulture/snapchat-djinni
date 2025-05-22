#!/bin/bash

# Find all *.djinni.yaml files in the specified directory
find kotlin_multiplatform/djinni/extern/s12 -name "*.djinni.yaml" | while read file; do
  echo "Processing $file"
  
  # Create a temporary file
  temp_file=$(mktemp)
  
  # Process the file using the awk script
  awk -f update_kotlin.awk "$file" > "$temp_file"
  
  # Replace the original file with the processed file
  mv "$temp_file" "$file"
done

echo "All files processed successfully."