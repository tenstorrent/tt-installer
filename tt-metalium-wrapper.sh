#!/bin/bash
# Wrapper script for TT-Metalium Docker container

# Default image and registry configuration
TT_METALIUM_REGISTRY="${TT_METALIUM_REGISTRY:-ghcr.io/tenstorrent/tt-metal}"
TT_METALIUM_IMAGE="${TT_METALIUM_IMAGE:-tt-metalium-ubuntu-22.04-amd64-release}"
METALIUM_VERSION="${TT_METALIUM_VERSION:-latest}"

# Parse arguments
DEV_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dev)
      DEV_MODE=1
      shift
      ;;
    --version=*)
      METALIUM_VERSION="${1#*=}"
      shift
      ;;
    --registry=*)
      TT_METALIUM_REGISTRY="${1#*=}"
      shift
      ;;
    --image=*)
      TT_METALIUM_IMAGE="${1#*=}"
      shift
      ;;
    --help)
      echo "Usage: $0 [OPTIONS] [COMMAND]"
      echo ""
      echo "Options:"
      echo "  --dev                Enable developer mode with additional permissions"
      echo "  --version=VERSION    Specify Metalium version (default: latest)"
      echo "  --registry=URL       Specify container registry URL"
      echo "  --image=IMAGE        Specify container image name"
      echo "  --help               Show this help message"
      echo ""
      echo "Environment Variables:"
      echo "  TT_METALIUM_VERSION   Alternative way to specify version"
      echo "  TT_METALIUM_REGISTRY  Alternative way to specify registry"
      echo "  TT_METALIUM_IMAGE     Alternative way to specify image name"
      echo ""
      exit 0
      ;;
    *)
      # End of options
      break
      ;;
  esac
done

# Construct the full image path
FULL_IMAGE_PATH="${TT_METALIUM_REGISTRY}/${TT_METALIUM_IMAGE}:${METALIUM_VERSION}"

# Base docker options that are always used
DOCKER_OPTS=(
  --rm -it
  --device=/dev/tenstorrent\*
  -v "${HOME}:/home/${USER}"
  -v /dev/hugepages-1G:/dev/hugepages-1G
  -w "/home/${USER}"
  -e HOME="/home/${USER}"
  -e USER="${USER}"
)

# Add developer mode options if enabled
if [[ "${DEV_MODE}" -eq 1 ]]; then
  echo "Starting TT-Metalium in developer mode with additional permissions"
  DOCKER_OPTS+=(
    --cap-add=SYS_PTRACE
    --security-opt seccomp=unconfined
    --user="$(id -u):$(id -g)"
    -v /tmp:/tmp
  )
fi

# Run the container
echo "Starting TT-Metalium: ${FULL_IMAGE_PATH}"
docker run "${DOCKER_OPTS[@]}" "${FULL_IMAGE_PATH}" "$@"