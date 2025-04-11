#!/bin/bash
# Script to run tt-installer tests locally

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Available test modes
MODES=("normal" "container" "no-metalium" "dev-mode")

# Function to log with color
log() {
  echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
  echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
  echo -e "${RED}[ERROR] $1${NC}"
}

# Function to show help
show_help() {
  echo "Usage: $0 [options]"
  echo
  echo "Options:"
  echo "  -h, --help          Show this help message"
  echo "  -m, --mode MODE     Test mode to run (normal, container, no-metalium, dev-mode)"
  echo "  -a, --all           Run all test modes"
  echo "  -b, --build-only    Only build the test image, don't run tests"
  echo "  -i, --image NAME    Use a custom image name (default: tt-installer-test)"
  echo
  echo "Available test modes:"
  echo "  normal              Standard installation"
  echo "  container           Container mode (skips KMD, HugePages, Metalium)"
  echo "  no-metalium         Skip Metalium installation"
  echo "  dev-mode            Enable developer mode for Metalium"
}

# Parse arguments
BUILD_ONLY=0
RUN_ALL=0
IMAGE_NAME="tt-installer-test"
TEST_MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      show_help
      exit 0
      ;;
    -m|--mode)
      TEST_MODE="$2"
      shift 2
      ;;
    -a|--all)
      RUN_ALL=1
      shift
      ;;
    -b|--build-only)
      BUILD_ONLY=1
      shift
      ;;
    -i|--image)
      IMAGE_NAME="$2"
      shift 2
      ;;
    *)
      error "Unknown option: $1"
      show_help
      exit 1
      ;;
  esac
done

# Validate test mode
if [[ -n "$TEST_MODE" ]]; then
  valid_mode=0
  for mode in "${MODES[@]}"; do
    if [[ "$mode" == "$TEST_MODE" ]]; then
      valid_mode=1
      break
    fi
  done
  
  if [[ $valid_mode -eq 0 ]]; then
    error "Invalid test mode: $TEST_MODE"
    echo "Available modes: ${MODES[*]}"
    exit 1
  fi
fi

# Check if both specific mode and all modes were requested
if [[ $RUN_ALL -eq 1 && -n "$TEST_MODE" ]]; then
  warn "Both specific mode and all modes requested. Running all modes."
  TEST_MODE=""
fi

# If no mode specified and not all modes, default to normal
if [[ -z "$TEST_MODE" && $RUN_ALL -eq 0 ]]; then
  TEST_MODE="normal"
  log "No test mode specified, defaulting to: $TEST_MODE"
fi

# Check for install.sh
if [[ ! -f "install.sh" ]]; then
  error "install.sh not found in current directory"
  exit 1
fi

# Build the test image
log "Building test image: $IMAGE_NAME"
docker build -t "$IMAGE_NAME" -f Dockerfile .

if [[ $BUILD_ONLY -eq 1 ]]; then
  log "Image built successfully. Exiting as requested."
  exit 0
fi

# Create a temporary directory for testing
TEST_DIR=$(mktemp -d)
log "Created temporary test directory: $TEST_DIR"

# Copy install.sh to the test directory
cp install.sh "$TEST_DIR/"
if [[ -f "tt-metalium-wrapper.sh" ]]; then
  cp tt-metalium-wrapper.sh "$TEST_DIR/"
fi

# Run the tests
if [[ $RUN_ALL -eq 1 ]]; then
  log "Running all test modes"
  
  for mode in "${MODES[@]}"; do
    log "========================================================"
    log "Running test mode: $mode"
    log "========================================================"
    
    docker run --rm -v "$TEST_DIR:/tt-installer" -e TEST_MODE="$mode" "$IMAGE_NAME"
    
    log "Test mode $mode completed"
    echo
  done
  
  log "All tests completed successfully"
else
  log "========================================================"
  log "Running test mode: $TEST_MODE"
  log "========================================================"
  
  docker run --rm -v "$TEST_DIR:/tt-installer" -e TEST_MODE="$TEST_MODE" "$IMAGE_NAME"
  
  log "Test completed successfully"
fi

# Clean up
log "Cleaning up temporary directory"
rm -rf "$TEST_DIR"

log "Done!"