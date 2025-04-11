FROM ubuntu:22.04

# Arguments for customization
ARG USERNAME=tester
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    python3 \
    python3-pip \
    python3-venv \
    dkms \
    sudo \
    systemd \
    ca-certificates \
    gnupg \
    lsb-release \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user
RUN groupadd --gid ${USER_GID} ${USERNAME} \
    && useradd --uid ${USER_UID} --gid ${USER_GID} -m ${USERNAME} \
    && echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} \
    && chmod 0440 /etc/sudoers.d/${USERNAME}

# Simulate Tenstorrent devices
RUN mkdir -p /dev \
    && touch /dev/tenstorrent_0 \
    && touch /dev/tenstorrent_1

# Create mock scripts for testing
RUN mkdir -p /usr/local/bin

# Create mock for systemctl to avoid errors in container
RUN echo '#!/bin/bash\nif [[ "$1" == "is-active" && "$2" == "--quiet" && "$3" == "docker" ]]; then\n  exit 1\nfi\nexit 0' > /usr/local/bin/systemctl \
    && chmod +x /usr/local/bin/systemctl

# Create mock for tt-smi
RUN echo '#!/bin/bash\necho "TT-SMI v0.1.0"\necho "Found 2 Tenstorrent devices"\necho "Device 0: Grayskull (Serial: GS000001)"\necho "  PCI: 0000:01:00.0"\necho "  Memory: 16GB"\necho "  Temperature: 45°C"\necho "Device 1: Wormhole (Serial: WH000001)"\necho "  PCI: 0000:02:00.0"\necho "  Memory: 32GB"\necho "  Temperature: 47°C"' > /usr/local/bin/tt-smi \
    && chmod +x /usr/local/bin/tt-smi

# Create mock for tt-flash
RUN echo '#!/bin/bash\necho "TT-Flash v0.1.0"\necho "Firmware update successful"\nexit 0' > /usr/local/bin/tt-flash \
    && chmod +x /usr/local/bin/tt-flash

# Create mock for modinfo
RUN echo '#!/bin/bash\nif [[ "$1" == "-F" && "$2" == "version" && "$3" == "tenstorrent" ]]; then\n  exit 1\nfi' > /usr/local/bin/modinfo \
    && chmod +x /usr/local/bin/modinfo

# Create mock for docker
RUN echo '#!/bin/bash\nif [[ "$1" == "pull" ]]; then\n  echo "Successfully pulled $2"\nfi\nif [[ "$1" == "run" ]]; then\n  echo "Would run container with args: $@"\nfi\nexit 0' > /usr/local/bin/docker \
    && chmod +x /usr/local/bin/docker

# Create a starter script for tests
COPY --chmod=755 <<-"EOF" /start.sh
#!/bin/bash
set -e

# Default test mode
TEST_MODE=${TEST_MODE:-normal}

cd /tt-installer

# Environment variables for different test modes
export TT_NON_INTERACTIVE=0
export TT_AUTO_REBOOT=0

case "${TEST_MODE}" in
  normal)
    echo "Running in normal mode"
    # Default settings, no special env vars needed
    ;;
  container)
    echo "Running in container mode"
    export TT_MODE_CONTAINER=0
    ;;
  no-metalium)
    echo "Running without Metalium installation"
    export TT_SKIP_INSTALL_METALIUM=0
    ;;
  dev-mode)
    echo "Running with Metalium developer mode"
    export TT_METALIUM_DEV_MODE=1
    ;;
  *)
    echo "Unknown test mode: ${TEST_MODE}"
    exit 1
    ;;
esac

# Show the command we're about to run
set -x

# Run the installer
./install.sh

# Verify installation
echo "Verifying installation results..."

# Check for tt-metalium script
if [[ "${TEST_MODE}" == "normal" || "${TEST_MODE}" == "dev-mode" ]]; then
  if [[ -f "$HOME/.local/bin/tt-metalium" ]]; then
    echo "✅ tt-metalium script created successfully"
    
    # Check content of script based on mode
    if [[ "${TEST_MODE}" == "dev-mode" && $(grep -c "developer mode" "$HOME/.local/bin/tt-metalium") -gt 0 ]]; then
      echo "✅ tt-metalium script has developer mode enabled"
    elif [[ "${TEST_MODE}" == "normal" && $(grep -c "standard options" "$HOME/.local/bin/tt-metalium") -gt 0 ]]; then
      echo "✅ tt-metalium script has standard options"
    else
      echo "❌ tt-metalium script content doesn't match expected mode"
      cat "$HOME/.local/bin/tt-metalium"
      exit 1
    fi
  else
    echo "❌ tt-metalium script was not created"
    exit 1
  fi
elif [[ "${TEST_MODE}" == "no-metalium" || "${TEST_MODE}" == "container" ]]; then
  if [[ ! -f "$HOME/.local/bin/tt-metalium" ]]; then
    echo "✅ tt-metalium script correctly not created in skip mode"
  else
    echo "❌ tt-metalium script was created when it should have been skipped"
    exit 1
  fi
fi

# Check log file
LOG_FILE=$(find /tmp -name "install.log" | head -1)
if [[ -f "$LOG_FILE" ]]; then
  echo "✅ Install log file found: $LOG_FILE"
  
  # Verify log contents based on mode
  case "${TEST_MODE}" in
    container)
      if grep -q "Running in container mode" "$LOG_FILE"; then
        echo "✅ Container mode message found in logs"
      else
        echo "❌ Container mode message not found in logs"
        exit 1
      fi
      ;;
    no-metalium)
      if grep -q "Skipping TT-Metalium installation" "$LOG_FILE"; then
        echo "✅ Skip Metalium message found in logs"
      else
        echo "❌ Skip Metalium message not found in logs"
        exit 1
      fi
      ;;
    dev-mode)
      if grep -q "developer mode enabled" "$LOG_FILE"; then
        echo "✅ Developer mode message found in logs"
      else
        echo "❌ Developer mode message not found in logs"
        exit 1
      fi
      ;;
  esac
else
  echo "❌ Install log file not found"
  exit 1
fi

echo "All tests passed! ✅"
EOF

# Setup volumes and workdir
VOLUME ["/tt-installer"]
WORKDIR /

# Set default user
USER ${USERNAME}

ENTRYPOINT ["/start.sh"]