.PHONY: build test test-ios test-shuyu check-sync

# 本地无签名编译验证；正式归档和发布按 AppStore/SUBMIT_GUIDE.md 执行。
build:
	cd ios-app && xcodegen generate
	xcodebuild build -project ios-app/BlackGod888.xcodeproj -scheme BlackGod888 -configuration Release -destination 'generic/platform=iOS' -derivedDataPath ios-app/build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''

test: test-ios test-shuyu

test-ios:
	bash tests/run_ios_runtime_tests.sh
	bash ios-app/StorageTests/run.sh

test-shuyu:
	cd shuyu && npm test
	cd shuyu && python3 -m unittest discover -s tests -v

# 旧 root 同步脚本依赖已经归档的网页副本。跨仓只运行受限的编号/词表核对，
# 不把它当作 v4.1 API 全面同步证明；需显式指定独立仓目录。
check-sync:
	@test -n "$(SHUYU_PEER)" || { echo '请指定独立仓目录：make check-sync SHUYU_PEER=/绝对路径/shuyu-lang'; exit 1; }
	node shuyu/tools/check-sync.mjs "$(SHUYU_PEER)"
