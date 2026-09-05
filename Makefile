.PHONY: test test-py

# 仓库现状（2026-09-05 起）：可在本机构建/测试的子系统只有枢语引擎 shuyu/。
# iOS App（ios-app/）走 Xcode / Codemagic / GitHub Actions(build.yml) 构建，非本 Makefile 范畴。
# 原 nexus-do 后端及其 build/selftest/sync 校验已随后端删除。

test:
	node --test shuyu/tests/*.test.mjs
	cd shuyu && python3 -m unittest discover -s tests

test-py:
	cd shuyu && python3 -m unittest discover -s tests
