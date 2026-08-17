.PHONY: build test check-sync

build:
	cd web/nexus-do && node build.mjs

test: build
	cd web/nexus-do && node selftest.mjs
	node --test shuyu/tests/*.test.mjs
	cd shuyu && python3 -m unittest discover -s tests
	node tools/sync-ui.mjs --check
	node tools/check-sync.mjs

check-sync:
	node tools/check-sync.mjs
