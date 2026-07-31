.PHONY: build test check-sync

build:
	cd web/nexus-do && node build.mjs

test: build
	cd web/nexus-do && node selftest.mjs
	cd shuyu && npm test
	python3 server/test_integration.py
	python3 server/test_tone_hint.py
	python3 server/test_agent_studio.py
	python3 tools/test_suite.py

check-sync:
	node tools/check-sync.mjs
