.PHONY: build test check-sync

build:
	cd web/nexus-do && node build.mjs

test: build
	cd web/nexus-do && node selftest.mjs
	cd shuyu && npm test
	python3 tools/test_suite.py

check-sync:
	node tools/check-sync.mjs
