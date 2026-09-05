# TODO · 神枢 iOS App Store 截图（HTML+CSS）

> 任务：为神枢 iOS App 制作 5 张 App Store 截图，单个 HTML 文件并排展示，
> 石墨暗流·玉绿色系（主色 #3FA57A，背景 #0E1114），iPhone 6.7 寸比例 393×852（@3x 导出 1290×2796）。

- [x] 1. 摸底（已读 Theme/ChatView/APIConfigView/MeView/NexusClient/商店文案；模型清单取自 NexusClient.availableModels；环境有 playwright+chromium+Noto CJK 字体可验证渲染）：读 ios-app/ 现有 UI（Theme / ChatView / APIConfigView / MeView / 商店文案），确定截图内容与文案
- [x] 2. 设计（标语：①直连Claude逐字实时回复 ②自带API Key零后端零中转 ③多模型自由切换费用自己掌控 ④对话记录只留在你的iPhone ⑤Keychain加密无账号无埋点；均配英文副标）：5 张主题 ①主对话 ②API Key 配置 ③多模型选择 ④本地历史记录 ⑤隐私安全；每张顶部中英双语营销标语 + 手机样机内 App 界面
- [x] 3. 编码：写 `ios-app/AppStore/screenshots.html`（已完成，内联 SVG 图标、系统字体栈、`?export` 导出模式）（自包含单文件，无外链依赖，5 张并排，每张 393×852）
- [x] 4. 编码：写 `ios-app/AppStore/screenshots_guide.md`（含 DevTools 手动法 + `export_screenshots.mjs` 脚本一键法，另同步更新 SUBMIT_GUIDE.md 与 .gitignore）（浏览器截图导出 PNG 的操作说明，含 @3x 1290×2796 导出方法）
- [x] 5. 验证（Playwright 无头 Chromium 渲染三轮，修正手机遮挡副标、④⑤超长、①输入栏被裁、Key 字段截断；6.7″ 1290×2796 与 6.9″ 1320×2868 各 5 张尺寸逐一核验通过，PNG 为 RGB 无透明）：无头浏览器渲染截图，肉眼核对排版/配色/溢出
- [x] 6. 提交：中文 commit，push 到 main；TODO.md 归档到 docs/done/

## 总结

- 产出 `ios-app/AppStore/screenshots.html`：5 张 393×852 截图并排，石墨暗流·玉绿色系（#3FA57A / #4FE096 / #0E1114），
  每张 = 品牌行 + 序号 + 中文衬线大标题（关键词玉绿）+ 英文副标 + 钛边 iPhone 样机（灵动岛/侧键/反光）+ 手绘 App 界面。
- 五屏内容全部对齐现有 iOS 代码与商店文案：模型名取自 `NexusClient.availableModels()`，
  Key 文案取自 `APIConfigView` footer，隐私主张取自 `description.txt`（零后端 / Keychain / 本地存储 / 无账号无埋点）。
- 产出 `screenshots_guide.md` + `export_screenshots.mjs`：脚本按「目标高度÷852 定倍率 + 按宽度居中裁切」导出，
  已验证 6.7″ 与 6.9″ 均像素精确；手动法给出 DPR=3.2817 这一能让 393×852 恰好取整成 1290×2796 的关键参数。
- 顺带更新 `SUBMIT_GUIDE.md` 截图条目与目录树，`.gitignore` 排除脚本产出目录。
