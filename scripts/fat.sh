#
# Creates a fat/universal framework for the ElectrodeContainer.
#
# Basic algorithm:
#
# 1. Copy the project to 2 new folders: one for device build, and one for simulator build
# 2. Build those 2 projects and merge their binary framework files into one via lipo
# 3. Make a copy of the device framework and update it to include the relevant pieces from the simulator framework plus the merged binary from #2
# 4. Use Carthage to build an archive of the fat framework
#
# Preconditions for this to work:
#
# 1. This script must be in the same directory as the project file and project content directory
# 2. That project's "ECDevice" scheme must be created and have "Release" selected for it's "Run" build configuration
# 3. If there are API files, make sure they are included in Build Phases -> Headers -> Public
# 4. "Debug Information Format" should be "DWARF with dSYM File" for both debug and release.
# 5. Bitcode must be disabled.

# Project variables
project_config_dir="Config"
project_name="ElectrodeContainer"
target_name="ElectrodeContainer"
device_scheme_name="ECDevice"
simulator_scheme_name="ElectrodeContainer"

# Directory variables
script_dir=$(PWD)
device_dir=$script_dir/device
simulator_dir=$script_dir/simulator
fat_dir=$script_dir/fat
fat_framework=$fat_dir/Release-iphoneos/ElectrodeContainer.framework
log_dir=$script_dir/logs
binary_dir=$script_dir/binaries
carthage_dir=$script_dir/Carthage/Build/iOS
products_dir=$script_dir/products

# Logging variables
device_build_log=$log_dir/device_build_log.txt
simulator_build_log=$log_dir/simulator_build_log.txt
carthage_archive_log=$log_dir/carthage_archive_log.txt

# Binary name variables
device_binary_name="DeviceBinary"
simulator_binary_name="SimulatorBinary"
fat_binary_name="FatBinary"

# Make sure we have a clean slate
rm -r $device_dir 2>/dev/null
rm -r $simulator_dir 2>/dev/null
rm -r $fat_dir 2>/dev/null
rm -r $log_dir 2>/dev/null
rm -r $binary_dir 2>/dev/null
rm -r $carthage_dir 2>/dev/null
rm -r $products_dir 2>/dev/null

# Make the directories we'll be using
mkdir $device_dir
mkdir $simulator_dir
mkdir $fat_dir
mkdir $log_dir
mkdir $binary_dir
mkdir -p $carthage_dir
mkdir $products_dir

# Make one copy of the project in a new folder called "device"
echo "Copying project to $device_dir/..."
cp -r ./$project_name $device_dir
cp -r ./$project_name.xcodeproj $device_dir
cp -r ./$project_config_dir $device_dir

# Make another copy of the project in a new folder called "simulator"
echo "Copying project to $simulator_dir/..."
cp -r ./$project_name $simulator_dir
cp -r ./$project_name.xcodeproj $simulator_dir
cp -r ./$project_config_dir $simulator_dir

# Build the project in the device folder and copy the binary to the script's folder
echo "Building for device, logging to $device_build_log..."
cd $device_dir
/usr/bin/xcodebuild -target $target_name -configuration Release -destination generic/platform=iOS -scheme "$device_scheme_name" clean build > $device_build_log 2>&1
device_build_location=$(xcodebuild -showBuildSettings | grep "\sBUILD_DIR" | grep -oEi "\/.*")
device_framework=$device_build_location/Release-iphoneos/$project_name.framework
cp $device_framework/$project_name $binary_dir/$device_binary_name
device_symbols=$device_build_location/Release-iphoneos/$project_name.framework.dSYM
cp -r $device_symbols $binary_dir/$device_binary_name.framework.dSYM
echo "Device build complete with output in $device_build_location/"

# Build the project in the simulator folder and copy the binary to the script's folder
echo "Building for simulator, logging to $simulator_build_log..."
cd $simulator_dir
/usr/bin/xcodebuild -target $target_name -configuration Debug -sdk iphonesimulator ONLY_ACTIVE_ARCH=NO -scheme "$simulator_scheme_name" clean build > $simulator_build_log 2>&1
simulator_build_location=$(xcodebuild -showBuildSettings | grep "\sBUILD_DIR" | grep -oEi "\/.*")
simulator_framework=$simulator_build_location/Debug-iphonesimulator/$project_name.framework
cp $simulator_framework/$project_name $binary_dir/$simulator_binary_name
simulator_symbols=$simulator_build_location/Debug-iphonesimulator/$project_name.framework.dSYM
cp -r $simulator_symbols $binary_dir/$simulator_binary_name.framework.dSYM
echo "Simulator build complete with output in $simulator_build_location/"

# Lipo the binaries together: once for the actual binary and once for the symbols binary.
echo "Merging into fat binary..."
cd $binary_dir
lipo -create -output $fat_binary_name $device_binary_name $simulator_binary_name
lipo -create -output $fat_binary_name.dSYM.binary $device_binary_name.framework.dSYM/Contents/Resources/DWARF/$project_name $simulator_binary_name.framework.dSYM/Contents/Resources/DWARF/$project_name

# Create a directory for the fat framework and copy the device folder to it.
echo "Building fat framework in $fat_dir/..."
cp -r $device_build_location/Release-iphoneos $fat_dir

# Copy the fat binary into the fat directory, overwriting the existing device binary.
cp $binary_dir/$fat_binary_name $fat_framework/$project_name

# Copy the files from the simulator directory's modules into the fat directory's modules.
cp $simulator_framework/Modules/$project_name.swiftmodule/* $fat_framework/Modules/$project_name.swiftmodule/

# Update the plist to include both "iPhoneOS" and "iPhoneSimulator"
#cd $fat_framework
#plutil -replace CFBundleSupportedPlatforms -json '["iPhoneOS", "iPhoneSimulator"]' Info.plist

# Create archive for Carthage
echo "Archiving for Carthage deployment, logging to $carthage_archive_log..."
cd $script_dir
cp -r $fat_framework $carthage_dir
cp -r $fat_framework/../$project_name.framework.dSYM $carthage_dir
carthage archive $project_name > carthage_archive_log 2>&1
echo "Carthage archive complete"

# Copy the important products into one location.
cp -r $fat_framework $products_dir
cp -r $device_symbols $products_dir
cp $binary_dir/$fat_binary_name.dSYM.binary $products_dir/$project_name.framework.dSYM/Contents/Resources/DWARF/$project_name
mv $project_name.framework.zip $products_dir
echo "Done! Final products are in $products_dir/"
