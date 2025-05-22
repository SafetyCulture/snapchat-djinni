#!/usr/bin/env zsh

# source directories
base_dir=$(cd "`dirname "$loc"`" && pwd)
generated_src="$base_dir/generated/kotlin"
package_path="com/safetyculture/krux/domain"

# destination root
krux_src="/Users/db/Developer/Krux/shared/src"

# source paths
common_main_src="$generated_src/commonMain/kotlin/$package_path"
android_main_src="$generated_src/androidMain/kotlin/$package_path"
ios_main_src="$generated_src/iosMain/kotlin/$package_path"

# destination paths
common_main_dest="$krux_src/commonMain/kotlin/$package_path"
android_main_dest="$krux_src/androidMain/kotlin/$package_path"
ios_main_dest="$krux_src/iosMain/kotlin/$package_path"

# we need to first delete any existing code
rm -rf $common_main_dest
rm -rf $android_main_dest
rm -rf $ios_main_dest

# create destination directories
mkdir -p $common_main_dest
mkdir -p $android_main_dest
mkdir -p $ios_main_dest

# then copy from generated src
cp -r $common_main_src/* $common_main_dest
cp -r $android_main_src/* $android_main_dest
cp -r $ios_main_src/* $ios_main_dest

