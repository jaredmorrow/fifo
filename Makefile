REL=0.2.0
CHUNTER_VER=$(shell cd chunter; git log --pretty=format:'%d' --abbrev-commit --date=short -1 | sed -e's; .HEAD, \([^,]*\),.*;\1;')
SNIFFLE_VER=$(shell cd sniffle; git log --pretty=format:'%d' --abbrev-commit --date=short -1 | sed -e's; .HEAD, \([^,]*\),.*;\1;')
SNARL_VER=$(shell cd snarl; git log --pretty=format:'%d' --abbrev-commit --date=short -1 | sed -e's; .HEAD, \([^,]*\),.*;\1;')
WIGGLE_VER=$(shell cd wiggle; git log --pretty=format:'%d' --abbrev-commit --date=short -1 | sed -e's; .HEAD, \([^,]*\),.*;\1;')
REL_DIR=/zones/21e0bc5d-af4e-4a44-8137-c7d50870dcbd/root/var/db/fifo/releases
REL_URL=http://release.project-fifo.net

all: chunter snarl sniffle wiggle force

chunter: force
	cd chunter; env GIT_SSL_NO_VERIFY=true ./rebar get-deps
	cd chunter; env GIT_SSL_NO_VERIFY=true ./rebar update-deps
	env GIT_SSL_NO_VERIFY=true make -C chunter tar

snarl: force
	cd snarl; env GIT_SSL_NO_VERIFY=true ./rebar get-deps
	cd snarl; env GIT_SSL_NO_VERIFY=true ./rebar update-deps
	env GIT_SSL_NO_VERIFY=true make -C snarl tar

sniffle: force
	cd sniffle; env GIT_SSL_NO_VERIFY=true ./rebar get-deps
	cd sniffle; env GIT_SSL_NO_VERIFY=true ./rebar update-deps
	env GIT_SSL_NO_VERIFY=true make -C sniffle tar

wiggle: force
	cd wiggle; env GIT_SSL_NO_VERIFY=true ./rebar get-deps
	cd wiggle; env GIT_SSL_NO_VERIFY=true ./rebar update-deps
	env GIT_SSL_NO_VERIFY=true make -C wiggle tar

force:
	true

versions: force
	echo "chunter: ${CHUNTER_VER}" > versions
	echo "snarl: ${SNARL_VER}" >> versions
	echo "sniffle: ${SNIFFLE_VER}" >> versions
	echo "wiggle: ${WIGGLE_VER}" >> versions

copy: versions
	mkdir -p $(REL_DIR)/$(REL)
	cp httpd-vhosts.conf *.xml *.js modules.tar.bz2 fifofy.sh versions */rel/*.tar.bz2 $(REL_DIR)/$(REL)
	sed -i .sed 's;__BASE_URL__;$(REL_URL);g' $(REL_DIR)/$(REL)/fifofy.sh
	sed -i .sed 's;__REL__;$(REL);g' $(REL_DIR)/$(REL)/fifofy.sh
	rm $(REL_DIR)/$(REL)/fifofy.sh.sed

update:
	git fetch --tags
	git checkout master
	git pull
	git checkout 0.2.0
	git pull
	git submodule init
	cd chunter; git checkout master; git fetch --tags
	cd sniffle; git checkout master; git fetch --tags
	cd snarl; git checkout master; git fetch --tags
	cd wiggle; git checkout master; git fetch --tags
	cd chunter; git checkout 0.2.0; git pull
	cd sniffle; git checkout 0.2.0; git pull
	cd snarl; git checkout 0.2.0; git pull
	cd wiggle; git checkout 0.3.0; git pull
	git submodule update
clean:
	rm -r chunter erllibcloudapi libsnarl libsniffle snarl sniffle wiggle
