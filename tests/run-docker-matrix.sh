#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
INSTALLER="${ROOT}/install.sh"
IMAGES=(matejak/argbash ubuntu:22.04 ubuntu:24.04 debian:13 fedora:41 fedora:42 fedora:43)
declare -A EXISTING_IMAGES=()

docker_cmd() {
	sudo docker "$@"
}

record_existing_images() {
	local image
	for image in "${IMAGES[@]}"; do
		if docker_cmd image inspect "${image}" >/dev/null 2>&1; then
			EXISTING_IMAGES["${image}"]=1
		fi
	done
}

cleanup() {
	local image
	for image in "${IMAGES[@]}"; do
		if [[ "${EXISTING_IMAGES[${image}]:-0}" != "1" ]]; then
			docker_cmd rmi -f "${image}" >/dev/null 2>&1 || true
		fi
	done
}

build_with_argbash() {
	docker_cmd pull matejak/argbash >/dev/null
	docker_cmd run --rm -u "$(id -u):$(id -g)" -e PROGRAM=argbash -v "${ROOT}:/work" -w /work matejak/argbash install.m4 -o install.sh
	bash -lc "sed 's/\r//g' '${ROOT}/ttis.sh' > /tmp/ttis-inline.sh; sed 's/\r//g' '${ROOT}/scripts/inline-ttis.sh' | bash -s -- '${INSTALLER}' /tmp/ttis-inline.sh"
}

install_container_deps() {
	case "$1" in
		ubuntu:*|debian:*)
			apt-get update
			DEBIAN_FRONTEND=noninteractive apt-get install -y python3 jq diffutils
			;;
		fedora:*)
			dnf install -y python3 jq diffutils
			;;
		*)
			echo "Unsupported image: $1" >&2
			return 1
			;;
	esac
}

fixture_for_image() {
	case "$1" in
		ubuntu:22.04) printf '%s' 'tests/fixtures/dry-run-ubuntu-22.04.ttis' ;;
		ubuntu:24.04) printf '%s' 'tests/fixtures/dry-run-apt.ttis' ;;
		debian:13) printf '%s' 'tests/fixtures/dry-run-debian-13.ttis' ;;
		fedora:41) printf '%s' 'tests/fixtures/dry-run-fedora-41.ttis' ;;
		fedora:42) printf '%s' 'tests/fixtures/dry-run-dnf.ttis' ;;
		fedora:43) printf '%s' 'tests/fixtures/dry-run-fedora-43.ttis' ;;
		*) return 1 ;;
	esac
}

platform_for_image() {
	case "$1" in
		ubuntu:22.04) printf '%s' 'Platform: ubuntu 22.04 (apt-get)' ;;
		ubuntu:24.04) printf '%s' 'Platform: ubuntu 24.04 (apt-get)' ;;
		debian:13) printf '%s' 'Platform: debian 13 (apt-get)' ;;
		fedora:41) printf '%s' 'Platform: fedora 41 (dnf)' ;;
		fedora:42) printf '%s' 'Platform: fedora 42 (dnf)' ;;
		fedora:43) printf '%s' 'Platform: fedora 43 (dnf)' ;;
		*) return 1 ;;
	esac
}

run_image() {
	local image="$1"
	local fixture platform
	fixture=$(fixture_for_image "${image}")
	platform=$(platform_for_image "${image}")
	docker_cmd run --rm -v "${ROOT}:/work" -w /work "${image}" bash -lc "
set -euo pipefail
$(declare -f install_container_deps)
install_container_deps '${image}'
bash tests/test-generation.sh
bash tests/unit/test-planning.sh
bash tests/test-dry-run.sh
out=\$(mktemp)
bash install.sh --dry-run --versions '${fixture}' --no-install-studio --no-install-inference-server > \"\${out}\" 2>&1
grep -qF '${platform}' \"\${out}\"
rm -f \"\${out}\"
"
}

main() {
	record_existing_images
	trap cleanup EXIT
	build_with_argbash
	for image in ubuntu:22.04 ubuntu:24.04 debian:13 fedora:41 fedora:42 fedora:43; do
		run_image "${image}"
	done
	echo "docker matrix passed"
}

main "$@"
