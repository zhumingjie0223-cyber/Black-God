# iOS 上架就绪:图标合规 + 上架校验闸门

任务背景:先前把环境搭建理解成"跑 shuyu/CF 演示",权哥澄清——**要的是可以上架**,CF/神枢 Worker 在本分支不要了。遂转向 iOS 上架线(纯 SwiftUI 客户端、零后端、用户自带 API Key,构建走 Codemagic macOS 出 IPA)。

- [x] 摸清上架链:`ios-app/`(SwiftUI 工程,XcodeGen 定义)+ `codemagic.yaml`(macOS 出 IPA、发 TestFlight)+ `AppStore/`(中英文案、隐私政策、截图源)。安卓 TWA 依赖 CF Worker(`aquan.lufei.uk`),与"CF 不要了"冲突,本轮不动。
- [x] **修上架硬伤**:`ios-app/AppIcon.png` 原是 **764×1024 竖版海报(含标语)**,不符合 App Store 图标 **1024×1024** 硬要求。以品牌神字 Logo(`assets/logo/brand_logo.png`)为源,裁神字主体重构为 **1024×1024、RGB 无 alpha、全出血无圆角**的深石墨底方图(忠实品牌、不另起炉灶)。
- [x] 新增 `ios-app/Assets.xcassets/AppIcon.appiconset`(1024 单尺寸)并在 `project.yml` 纳入 `Assets.xcassets`——`xcodegen generate` 后工程直接带图标,不必再在 Xcode 手动导入。
- [x] 新增上架就绪校验器 `ios-app/AppStore/preflight.mjs`(纯 Node 零依赖):核对工程名/BundleID/版本号/构建号/加密声明、CI 与工程一致性、中英双语文案齐全与字符上限、隐私/支持链接、图标 1024×1024 无 alpha、asset catalog 引用完整。**32 项全绿**;负向验证(塞回旧图标)精确报红并退出码 1,证明闸门有效。
- [x] 修正 `AppStore/SUBMIT_GUIDE.md` 滞后的版本号(`1.0.0/构建1` → `1.1.0/构建2`,与 `project.yml`、`release_notes` 一致),并把图标步骤改为"已内置、无需手动导入"。
- [x] `.cursor/environment.json` 的 `install` 从"跑 shuyu 测试"改为"跑 iOS 上架 preflight",让环境闸门对齐"可上架"。

## 总结

本轮把方向从"跑本地服务演示"纠正到**iOS 上架就绪**,并交付实打实的成果:修掉了会直接卡上架的**图标尺寸不合规**硬伤(764×1024 → 1024×1024 全出血无 alpha),把图标内置进 Xcode 资源目录使工程 `xcodegen generate` 即可带图标打包,补齐一个**纯 Node 的上架就绪校验器**(32 项全绿、可作 CI/环境闸门,已负向验证有效),并修正了文档版本号不一致。

诚实边界:iOS 真机编译/出 IPA 必须在 **macOS + Xcode**(既定路线是 Codemagic,`codemagic.yaml` 已配好),Linux 云环境天然编不了 iOS,故本轮不做真机构建;能在本环境自动化的上架前闸门已全部做实并跑绿。安卓 TWA 因依赖 CF Worker,与"CF 不要了"冲突,留待权哥就安卓路线单独拍板。
