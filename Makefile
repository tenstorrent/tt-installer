install.sh: install.m4 ttis.sh scripts/inline-ttis.sh
	cp install.m4 install.sh.temp
	sed -i "s|__INSTALLER_DEVELOPMENT_BUILD__|$(shell date +%Y.%m.%d-%H.%M.%S )-$(shell git log --format="%h" -n 1 )|g" install.sh.temp
	argbash install.sh.temp -o install.sh
	scripts/inline-ttis.sh install.sh ttis.sh

GOLDEN_TAG := $(shell grep -oP '(?<=TTIS_GOLDEN_VERSIONS_TAG=")[^"]+' install.m4)
GOLDEN_URL := https://github.com/tenstorrent/tt-sw-manifest/releases/download/$(GOLDEN_TAG)/golden.tar.gz

fetch-golden:
	mkdir -p installer-golden-versions/golden
	curl -fsSL "$(GOLDEN_URL)" | tar -xz --strip-components=1 -C installer-golden-versions/golden/

clean:
	rm -rf install.sh install.sh.temp

