# 神枢 App Store 截图

最终截图应展示此次发布构建的真实使用界面。保留深墨绿品牌与现有「神」字图标；可以在实拍界面外加说明，但不能用 HTML 假界面证明功能已实现。Apple 要求截图反映 App 实际体验。[审核指南 2.3](https://developer.apple.com/app-store/review/guidelines/)

## 推荐画面

1. 对话：显示实际发送的普通问题、任务进度或真实回复。
2. API 配置：服务商、模型、隐藏的 Key 及 AI 数据共享选择。
3. 工作台：任务起点及已收藏记忆入口。
4. 记录：由测试任务真实产生的任务历史、步骤和结果；没有记录时保留真实空状态。
5. 我的：隐私政策与本地数据清除入口。

不要展示真实 Key、真实个人信息、尚未实现的功能或伪造成功记录。避免「数据永不离开设备」「Key 从不发送」「已上线」「逐字回复」等与此版本不符或未经验证的文案。模型名称以 `NexusModelCatalog.swift` 和发布包实际选择器为准。

## 尺寸和目录

截至 2026-09-08，Apple 的 iPhone **6.9 英寸显示屏**组接受竖图 `1260×2736`、`1290×2796`、`1320×2868`；每组 1–10 张，可用 JPEG 或 PNG，不能包含 alpha/透明。其他设备与横版规格按提交时页面核对。[Apple 截图规格](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)

本仓库 fastlane lane 接受 RGB 不透明 PNG，目录按语言组织：

```text
实际截图目录/
├── zh-Hans/
│   ├── 01-chat.png
│   └── 02-api.png
└── en-US/
    ├── 01-chat.png
    └── 02-api.png
```

用最终构建在相应 iPhone 模拟器或真机获取屏幕截图，检查文本、尺寸和透明通道。英文商店页面也应如实反映当前以中文为主的界面，可加准确英文说明。将目录绝对路径设为 `ASC_SCREENSHOTS_DIR` 后再运行上传 lane。

## 现有 HTML 样稿

`screenshots.html` 与 `export_screenshots.mjs` 保留为设计参考。导出脚本检查图像尺寸，不验证界面真实性、功能、模型或隐私文案；导出成功不等于可直接提交。Fastlane 不自动调用该脚本。

如需查看旧设计样稿，可在 `AppStore` 目录使用原命令：

```bash
node export_screenshots.mjs
node export_screenshots.mjs --size 6.9
```

这些命令需要本地已安装的 Playwright/Chromium。默认产物在 `png/6_7/`（1290×2796），另一档在 `png/6_9/`（1320×2868）；这里的目录名是旧约定，不等于当前 App Store Connect 的显示屏组名称。将样稿替换为真实界面并核对后，才整理进正式截图目录。
