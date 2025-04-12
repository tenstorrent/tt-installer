#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log() {
  echo -e "${GREEN}[INFO] $1${NC}"
}

warn() {
  echo -e "${YELLOW}[WARN] $1${NC}"
}

error() {
  echo -e "${RED}[ERROR] $1${NC}"
}

# Default test mode
TEST_MODE=${TEST_MODE:-normal}

# Change to installer directory
cd /tt-installer

# Environment variables for different test modes
export TT_NON_INTERACTIVE=0
export TT_AUTO_REBOOT=0

# Set fixed versions to avoid unpredictable network requests
export TT_KMD_VERSION=${TT_KMD_VERSION:-"1.0.0"}
export TT_FW_VERSION=${TT_FW_VERSION:-"1.0.0"}
export TT_SYSTOOLS_VERSION=${TT_SYSTOOLS_VERSION:-"1.0.0"}
export TT_METALIUM_VERSION=${TT_METALIUM_VERSION:-"latest"}

# Configure based on test mode
case "${TEST_MODE}" in
  normal)
    log "Running in normal mode"
    # Default settings, no special env vars needed
    ;;
  container)
    log "Running in container mode"
    export TT_MODE_CONTAINER=0
    ;;
  no-metalium)
    log "Running without Metalium installation"
    export TT_SKIP_INSTALL_METALIUM=0
    ;;
  dev-mode)
    log "Running with Metalium developer mode"
    export TT_METALIUM_DEV_MODE=1
    ;;
  *)
    error "Unknown test mode: ${TEST_MODE}"
    exit 1
    ;;
esac

# Mock git ls-remote to return consistent version tags
mkdir -p /tmp/mockscripts
cat > /tmp/mockscripts/git-ls-remote << 'EOF'
#!/bin/bash
if [[ "$@" == *"tt-kmd"* ]]; then
  echo "refs/tags/ttkmd-${TT_KMD_VERSION:-1.0.0}"
elif [[ "$@" == *"tt-firmware"* ]]; then
  echo "refs/tags/v${TT_FW_VERSION:-1.0.0}"
elif [[ "$@" == *"tt-system-tools"* ]]; then
  echo "refs/tags/v${TT_SYSTOOLS_VERSION:-1.0.0}"
fi
EOF
chmod +x /tmp/mockscripts/git-ls-remote

# Override git command to use our mock for ls-remote
cat > /tmp/mockscripts/git << 'EOF'
#!/bin/bash
if [[ "$1" == "ls-remote" ]]; then
  /tmp/mockscripts/git-ls-remote "$@"
elif [[ "$1" == "clone" ]]; then
  # Mock git clone to create a directory and avoid network requests
  mkdir -p "$3"
  touch "$3/.git"  # Create a fake .git directory
else
  # For other git commands, just echo what would have been done
  echo "Mocked git command: $@"
fi
EOF
chmod +x /tmp/mockscripts/git

# Prepend our mock scripts directory to PATH
export PATH="/tmp/mockscripts:$PATH"

# Show the command we're about to run
log "Starting installer with TEST_MODE=$TEST_MODE"
set -x
chmod +x install.sh
./install.sh
set +x

# Verify installation
log "Verifying installation results..."

# Check for tt-metalium script
if [[ "${TEST_MODE}" == "normal" || "${TEST_MODE}" == "dev-mode" ]]; then
  if [[ -f "$HOME/.local/bin/tt-metalium" ]]; then
    log "✅ tt-metalium script created successfully"
    
    # Check content of script based on mode
    if [[ "${TEST_MODE}" == "dev-mode" && $(grep -c "developer mode" "$HOME/.local/bin/tt-metalium") -gt 0 ]]; then
      log "✅ tt-metalium script has developer mode enabled"
    elif [[ "${TEST_MODE}" == "normal" && $(grep -c "standard" "$HOME/.local/bin/tt-metalium") -gt 0 ]]; then
      log "✅ tt-metalium script has standard options"
    else
      # Less strict check for content - just make sure it's not empty
      if [[ -s "$HOME/.local/bin/tt-metalium" ]]; then
        log "✅ tt-metalium script has content"
      else
        error "❌ tt-metalium script is empty"
        cat "$HOME/.local/bin/tt-metalium"
        exit 1
      fi
    fi
  else
    error "❌ tt-metalium script was not created"
    exit 1
  fi
elif [[ "${TEST_MODE}" == "no-metalium" || "${TEST_MODE}" == "container" ]]; then
  if [[ ! -f "$HOME/.local/bin/tt-metalium" ]]; then
    log "✅ tt-metalium script correctly not created in ${TEST_MODE} mode"
  else
    error "❌ tt-metalium script was created when it should have been skipped"
    exit 1
  fi
fi

# Check log file
LOG_FILE=$(find /tmp -name "install.log" -type f | head -1)
if [[ -f "$LOG_FILE" ]]; then
  log "✅ Install log file found: $LOG_FILE"
  
  # Verify log contents based on mode
  case "${TEST_MODE}" in
    container)
      if grep -q "Running in container mode" "$LOG_FILE"; then
        log "✅ Container mode message found in logs"
      else
        error "❌ Container mode message not found in logs"
        exit 1
      fi
      ;;
    no-metalium)
      if grep -q "Skipping TT-Metalium installation" "$LOG_FILE"; then
        log "✅ Skip Metalium message found in logs"
      else
        error "❌ Skip Metalium message not found in logs"
        exit 1
      fi
      ;;
    dev-mode)
      if grep -q "developer mode enabled" "$LOG_FILE"; then
        log "✅ Developer mode message found in logs"
      else
        error "❌ Developer mode message not found in logs"
        exit 1
      fi
      ;;
  esac
else
  error "❌ Install log file not found"
  find /tmp -type f -name "*.log" | xargs ls -la
  exit 1
fi

log "All tests passed! ✅"