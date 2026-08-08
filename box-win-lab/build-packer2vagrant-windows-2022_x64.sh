#!/bin/bash
# Run this script to build the Windows 2022 base box and add it to Vagrant with automatic cleanup

set -x
set -e

# Use a build directory outside CWD to avoid cloud sync
BUILD_DIR="${BUILD_DIR:-/var/tmp/packer-windows-build}"
BOX_FILE="${BUILD_DIR}/../windows-2022-amd64-libvirt.box"

# Cleanup function
cleanup() {
    if [ -d "$BUILD_DIR" ]; then
        echo "Cleaning up build directory: $BUILD_DIR"
        rm -rf "$BUILD_DIR"
    fi
    if [ -f "$BOX_FILE" ]; then
        echo "Cleaning up box file: $BOX_FILE"
        rm -f "$BOX_FILE"
    fi
}

# Clone and build
git clone https://github.com/rgl/windows-vagrant.git "$BUILD_DIR"
pushd "$BUILD_DIR"
make build-windows-2022-libvirt

# Move box file to parent directory for vagrant box add
if [ -f "windows-2022-amd64-libvirt.box" ]; then
    mv "windows-2022-amd64-libvirt.box" "$BOX_FILE"
fi
popd

# Add box to vagrant (this will copy it to vagrant's box storage)
vagrant box add -f windows-2022-amd64 "$BOX_FILE"

# Cleanup after successful completion
cleanup
