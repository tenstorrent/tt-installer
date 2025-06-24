install.sh: install.m4
	cp install.m4 install.sh.temp
	sed -i "s|__INSTALLER_DEVELOPMENT_BUILD__|$(shell date +%Y.%m.%d-%H.%M.%S )-$(shell git log --format="%h" -n 1 )|g" install.sh.temp
	argbash install.sh.temp -o install.sh

clean:
	rm -rf install.sh install.sh.temp

