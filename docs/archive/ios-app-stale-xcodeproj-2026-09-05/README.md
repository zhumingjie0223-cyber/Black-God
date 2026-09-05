# 归档：ios-app/BlackGod.xcodeproj（失效工程文件）

归档日期：2026-09-05

原路径：`ios-app/BlackGod.xcodeproj/project.pbxproj`

失效原因：该 pbxproj 引用的源文件（BlackGodApp.swift、ContentView.swift、SettingsView.swift、
NexusDeviceBridge.swift，且假定源码在 `BlackGod/` 子目录）在仓库里均已不存在，
Bundle ID 为旧值 `com.blackgod.ai`，无法打开构建。

现行做法：`ios-app/project.yml` 是唯一的工程真源，用 `xcodegen generate` 现场生成
`BlackGod888.xcodeproj`（已在 .gitignore 忽略，不再提交生成物）。上架参数见
`ios-app/AppStore/SUBMIT_GUIDE.md`。
