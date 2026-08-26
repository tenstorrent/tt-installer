install.sh: install.m4 ttis.sh scripts/inline-ttis.sh
	cp install.m4 install.sh.temp
	sed -i "s|__INSTALLER_DEVELOPMENT_BUILD__|$(shell date +%Y.%m.%d-%H.%M.%S )-$(shell git log --format="%h" -n 1 )|g" install.sh.temp
	argbash install.sh.temp -o install.sh
	scripts/inline-ttis.sh install.sh ttis.sh

GOLDEN_TAG := $(shell grep -oP '(?<=TTIS_GOLDEN_VERSIONS_TAG=")[^"]+' install.m4)

fetch-golden:
	mkdir -p installer-golden-versions/golden
	curl -fsSL "https://api.github.com/repos/tenstorrent/tt-sw-manifest/releases/tags/$(GOLDEN_TAG)" \
		| jq -r '.assets[] | select(.name | endswith(".ttis")) | [.name, .browser_download_url] | @tsv' \
		| while IFS=$$'\t' read -r name url; do \
			curl -fsSL -o "installer-golden-versions/golden/$${name}" "$${url}"; \
		done

# Update the pinned uv version + installer hash in install.m4 (latest release
# by default, or `make bump-uv UV_VERSION=0.12.5` for a specific one).
bump-uv:
	scripts/bump-uv.sh $(UV_VERSION)

clean:
	rm -rf install.sh install.sh.temp

test: install.sh
	bash tests/unit/test-planning.sh
	bash tests/test-dry-run.sh
	bash tests/test-generation.sh

test-docker: install.sh
	bash tests/run-docker-matrix.sh

TEST_SCRIPTS := tests/test-dry-run.sh tests/unit/test-planning.sh tests/test-generation.sh tests/run-docker-matrix.sh

test-static:
	bash -n $(TEST_SCRIPTS)
	shellcheck $(TEST_SCRIPTS)

