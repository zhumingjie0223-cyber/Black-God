.PHONY: build test test-ios test-shuyu generate prepare-runtime
IOS_DESTINATION ?= platform=iOS Simulator,name=iPhone 17 Pro Max

prepare-runtime:
	python3 tools/runtime/build.py

generate: prepare-runtime
	python3 tools/shuyu/bundle.py
	cd ios-app && xcodegen generate

build: generate
	cd ios-app && xcodebuild build -project BlackGod.xcodeproj -scheme BlackGod -configuration Release -destination 'generic/platform=iOS' -derivedDataPath build CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY=''

test: test-shuyu test-ios

test-shuyu:
	python3 tools/shuyu/bundle.py --check
	cd shuyu && npm test
	cd shuyu && python3 -m unittest discover -s tests

test-ios: generate
	cd ios-app && xcodebuild test -project BlackGod.xcodeproj -scheme BlackGod -destination '$(IOS_DESTINATION)' CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
