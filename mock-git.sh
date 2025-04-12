#!/bin/bash
# Script to mock git functionality for testing

# Intercept git ls-remote for version fetching
if [[ "$1" == "ls-remote" ]]; then
  if [[ "$@" == *"tt-kmd.git"* ]]; then
    echo "refs/tags/ttkmd-${TT_KMD_VERSION:-1.0.0}"
  elif [[ "$@" == *"tt-firmware.git"* ]]; then
    echo "refs/tags/v${TT_FW_VERSION:-1.0.0}"
  elif [[ "$@" == *"tt-system-tools.git"* ]]; then
    echo "refs/tags/v${TT_SYSTOOLS_VERSION:-1.0.0}"
  fi
  exit 0
# Intercept git clone to create a directory without network access
elif [[ "$1" == "clone" ]]; then
  echo "Mocking git clone: $@"
  
  # Extract target directory (3rd argument)
  TARGET_DIR="$3"
  
  # Create the directory and add a dummy .git folder
  mkdir -p "$TARGET_DIR"
  mkdir -p "$TARGET_DIR/.git"
  
  # If cloning tt-kmd, create a dummy module
  if [[ "$@" == *"tt-kmd"* ]]; then
    mkdir -p "$TARGET_DIR/src"
    echo "// Dummy KMD module" > "$TARGET_DIR/src/tenstorrent.c"
    echo "This is a mock tt-kmd repo created by the testing script" > "$TARGET_DIR/README.md"
  fi
  
  exit 0
# For all other git commands, just pretend they worked
else
  echo "Mocking git command: $@"
  exit 0
fi