# Black God × 起航(QiHang) × Minis 合并对比与方案

> 基线：以 **Black God** 为统一对外品牌和主框架，把起航的优势功能合并进来，
> 参考 **Minis / OpenMinis**（起航前身）的成熟设计。成品放 `uumingtian-max/blackgod` 仓库。
>
> 数据来源说明：
> - **Minis** 列 = 来自公开仓库 [OpenMinis](https://github.com/OpenMinis)（已核实）。
> - **Black God** 列 = 来自项目作者描述 + 本仓库已有代码（iOS App、`web/` PWA）。
> - **起航** 列 = 来自作者提供的项目总结文字，⚠️**标「待核实」的需上传代码后确认**。

---

## 一、Minis（OpenMinis）已核实的关键事实

- 定位：**跨平台 AI Agent App**（主 App 源码标注 "open source coming soon"，暂未公开）。
- 技能体系：[`MinisSkills`](https://github.com/OpenMinis/MinisSkills) ⭐294，**47+ 个模块化技能**。
- **技能格式 = Agent Skills 标准**：每个技能是一个 kebab-case 目录，含必需的 `SKILL.md`
  （YAML frontmatter：`name` + `description` 用于触发；正文 ≤ ~500 行），可选
  `scripts/`、`references/`、`assets/`、`evals/evals.json`。**无独立 manifest**。
- 代表技能（与本项目直接相关）：
  - `appstoreprice-hub`（App Store 价格/查询）→ **对应起航的 App Store 工具**
  - `self-improving-agent`（自进化）→ 对应 Black God「自进化」
  - `web-search` / `exa-search` / `tavily-search`、`tg-hub`、各社交/金融/TTS/下载器 hub
- 其它：`ish-arm64`（iOS 上跑 Linux shell，⭐133）、`AwesomeMinis`（用例集 ⭐78）。

> 🔑 结论：Black God 技能若同为 `SKILL.md` 格式，则与 Minis 技能**可直接互通复用**，
> 合并几乎零摩擦；这是本次合并最大的现成红利。

---

## 二、功能对比表（起航列待代码核实）

| 功能 | 起航有? | Black God 有? | Minis 参考 | 谁更好 / 合并方案 |
|---|---|---|---|---|
| Agent 引擎 | 待核实 | ✅ 15 工具 + 自进化 | ✅ | 以 BG 为准；起航若有独有工具→并入 |
| 技能体系 | 待核实 | ✅ 73 技能（skills.db） | ✅ 47+ SKILL.md | **统一为 SKILL.md 标准**；去重合并 |
| App Store 查询 | ✅（核心工具） | ❓ | ✅ appstoreprice-hub | **合并起航实现**或封装为一个 SKILL.md |
| 文件浏览器 | ✅ | ❓ | — | 起航独有 → 作为前端工具并入 `web/tools/` |
| Minis 克隆前端 | ✅ | ✅ web/ PWA（新） | ✅ | 二选一/取长；**以 BG 黑金 PWA 为壳** |
| 官网首页 | ✅ qihang_index | ✅ web/index.html（黑金） | ✅ | **用 BG 黑金首页**，并入起航有价值内容 |
| 服务器/后端 API | 待核实 | ✅ 7 API @8765 | — | 以 BG 网关为准；起航接口统一接入 |
| 记忆系统 | 待核实 | ✅ | — | 以 BG 为准，优化查询 |
| TG Bot | ❓ | ✅ | ✅ tg-hub | 以 BG 为准 |
| 黑金 UI / 主题 | ❓ | ✅ web/theme.css | — | **统一用 BG 黑金主题**全站套用 |
| iOS 原生 App | ❓ | ✅（仓库内，开发中） | ✅（Minis 跨平台） | 需 Mac 才能构建，列未来项 |

---

## 三、合并决策原则（不重做）

1. **直接合并**：起航独有、且 BG 没有的前端工具（文件浏览器、App Store 工具等）
   → 整理进 `web/tools/<tool>/`，统一套 `web/theme.css`，首页加入口。
2. **统一标准**：所有技能收敛到 **`SKILL.md` 格式**（对齐 Minis），去重；
   重复实现保留更优的一个。
3. **删除/弃用**：与 BG 重复且更弱的实现（如起航的 minis 克隆前端，若不及 BG PWA）。
4. **统一品牌**：对外名称 = **Black God**；视觉 = 黑金主题；首页 = `web/index.html`。

---

## 四、🚧 还缺什么才能落地（需要你提供）

OpenMinis 只是**起航的前身/参考**，里面**没有起航本身的代码**（主 App 未开源）。
要真正执行合并，仍需你上传 **起航的实际代码包（zip）**：
- 起航全部源码（前后端）、去敏感信息的配置、数据库 SQL、README/功能清单。

拿到后我会：①把上表「起航」列与「待核实」全部填实 → ②按上面决策把可复用前端工具
并入 `web/tools/` 并统一黑金风格 → ③本地截图验证 → ④提交推送。

---

## 五、本次范围外（如实说明）

- 服务器实际部署 / 数据库迁移（我登不上 `8.222.169.202`，交接维护方）。
- iOS 原生 App 打包与系统级集成（联系人/相册/日历，需 Mac+Xcode）。
- 不画饼：能合并多少以上传的真实代码为准。
