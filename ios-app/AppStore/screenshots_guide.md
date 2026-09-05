# App Store 截图导出指南 · 神枢 Black God

> 源文件：`screenshots.html`（自包含单文件，无外链，双击即可用浏览器打开）
> 产出物：5 张 iPhone 6.7″ 截图 PNG，1290×2796，可直接上传 App Store Connect。

## 0. 这 5 张是什么

| 序号 | 主题 | 顶部标语（中） | 顶部标语（英） |
|---|---|---|---|
| ① | 主对话界面 | 直连 Claude，逐字实时回复 | Straight to Claude. Streamed word by word. |
| ② | API Key 配置 | 自带 API Key，零后端 · 零中转 | Bring your own key. No servers of ours. |
| ③ | 多模型选择 | 多模型自由切换，费用自己掌控 | Switch between Claude models in one tap. |
| ④ | 神枢状态 | 对话记录只留在你的 iPhone | Your history lives only on your device. |
| ⑤ | 本地优先设置 | Keychain 加密，无账号 · 无埋点 | Encrypted by iOS Keychain. No tracking. |

设计规格：
- 画布 393×852 CSS 像素 = iPhone 6.7″ 逻辑尺寸；与 App Store 6.7″ 规格 1290×2796 **同比例**，放大 3.28 倍即精确对齐。
- 色系：玄黑森林 · 翡翠活光。主色 `#3FA57A`，高光 `#4FE096`，背景 `#0B120E`。
- 每张 = 顶部品牌行 + 序号 + 中文大标题（衬线银字，关键词翡翠活光）+ 英文副标 + 钛金属边 iPhone 样机（灵动岛、侧键、屏幕反光），样机下沿出血裁切，是 App Store 常见构图。
- 字体走系统栈（苹方 / Noto Sans CJK / 宋体 / Noto Serif CJK），不依赖网络。**建议在 macOS 上导出**，苹方与宋体渲染最接近 iOS 真机。

---

## 1. 方法一：脚本一键导出（推荐，像素精确）

需要 Node.js 18+。在 `ios-app/AppStore/` 目录下执行：

```bash
npm i -D playwright && npx playwright install chromium   # 首次安装（约 150 MB）
node export_screenshots.mjs                              # 6.7″ → ./png/6_7/  1290×2796
node export_screenshots.mjs --size 6.9                   # 6.9″ → ./png/6_9/  1320×2868
```

脚本会逐张读取 PNG 头核验尺寸，全部 `✓` 即可上传；输出文件名形如 `1-主对话.png`。

> App Store Connect 目前只要求 **6.9″ 或 6.7″ 其一**（iPhone 16 Pro Max 等新机型对应 6.9″），
> 其余小尺寸机型 Apple 会自动缩放，无需再单独出图。若表单里同时列出两档，两条命令都跑一遍即可。

---

## 2. 方法二：Chrome 开发者工具手动截图（无需装任何东西）

1. 用 Chrome / Edge 打开 `screenshots.html`，在地址末尾加 **`?export`**（隐藏顶部工具条、去掉间距）。
2. 按 `F12`（macOS：`⌥⌘I`）打开开发者工具 → 点左上角「切换设备工具栏」图标（或 `⇧⌘M`）进入设备模拟。
3. 顶部机型下拉选「Responsive」，把宽度设为 **2100**、高度 **900**；点右侧 `⋮` → 「Add device pixel ratio」，把 **DPR 填 3.2817**（这个值能让 393×852 恰好取整成 1290×2796）。
4. 按 `⌘⇧C`（Windows：`Ctrl+Shift+C`）进入选取模式，点第 1 张截图的深色背景任意空白处，Elements 面板会高亮到 `<section class="shot" id="shot-1">`（若高亮到子元素，按 `↑` 上移到 `section.shot`）。
5. 在该节点上右键 → **Capture node screenshot**，浏览器会下载一张 1290×2796 的 PNG。
6. 对 `#shot-2` … `#shot-5` 重复第 4–5 步。
7. 用「预览」或任意看图软件确认尺寸是 1290×2796；若是 1290×2797，说明 DPR 没设成 3.2817（用了 3.28 或 1290/393），改回后重截。

> 6.9″（1320×2868）用手动方式无法一次凑齐精确像素（Chromium 取整怪癖），请用方法一的脚本。

---

## 3. 方法三：Safari（macOS）

Safari 没有「节点截图」，可以走整页导出再裁：
1. 打开 `screenshots.html?export`，`⌥⌘I` 打开 Web 检查器 → 「元素」标签。
2. 右键 `<section id="shot-1">` → 「捕获屏幕快照」（Safari 17+ 支持），得到 1x 图（393×852）。
3. 1x 图仅够预览，**上架请用方法一**（Safari 不支持自定义 DPR）。

---

## 4. 上传到 App Store Connect

1. App Store Connect → 我的 App → 神枢 → 「iOS App」版本页 → 「App 预览和截屏」。
2. 选 **6.7″ 显示屏**（或 6.9″）标签页，把 5 张 PNG 按 ①→⑤ 顺序拖入。第 1 张会作为搜索结果里的主图，务必是「主对话」。
3. 简体中文与英文两个本地化页面**共用同一套图**即可（画面本身已是中英双语标语）。
4. 保存后页面上方会出现绿色对勾；若报「尺寸不符」，回到第 1 节重新核验 PNG 尺寸。

上传前自检清单：
- [ ] 5 张全部 1290×2796（或 1320×2868），RGB，无透明通道（脚本导出的 PNG 默认满足）。
- [ ] 画面里的模型名称与 `NexusClient.swift → availableModels()` 一致（当前：opus-5 / fable-5-1 / opus-4-8 / sonnet-4-6 / haiku-4-5）。
- [ ] 文案与 `metadata/zh-Hans/description.txt` 主张一致：零后端、直连、Keychain、本地存储、无账号无埋点。
- [ ] 没有出现真实 API Key（画面用的是 `sk-ant-api03-••••••••••7Qx` 占位）。

---

## 5. 改文案 / 改内容

- 标语：编辑对应 `<section>` 里 `<header class="copy">` 的 `<h2>`（中文，`<em>` 包住的词变翡翠活光）和 `<p class="en">`（英文）。
- 手机内界面：每个 `<div class="app">` 就是一屏 393×852 的 HTML，直接改文字即可；内容底部尽量不超过 App 坐标 **y ≈ 750**（样机下沿在此被画布裁掉）。
- 配色：只改 `:root` 里的 `--jade / --jade-hi / --bg` 等令牌，不要在组件里硬编码颜色。
- 改完在浏览器里刷新预览，再跑一遍方法一导出。

---

## 6. 目录约定

```
ios-app/AppStore/
├── screenshots.html          ← 截图源文件（本指南对象）
├── screenshots_guide.md      ← 本指南
├── export_screenshots.mjs    ← 一键导出脚本
└── png/                      ← 脚本产出（已加入 .gitignore，不入库）
    ├── 6_7/1-主对话.png …
    └── 6_9/…
```
