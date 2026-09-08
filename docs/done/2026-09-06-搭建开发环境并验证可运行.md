# TODO — 搭建开发环境并验证可运行（Cloud Agent）

任务：为本仓库搭好开发环境，实际跑起来应用并证明环境正常工作。

- [x] 探明本分支（`cursor/ios-asi-upgrade-96d7`）可运行组件与依赖
  - 结论：本分支不含 `web/nexus-do/`（那是 main 上的 CF Worker 主体）。本分支可运行的是
    `shuyu/` 枢语引擎（Node + Python 双实现、CLI、CF Worker、`shuyu.html` 浏览器演示）；
    `ios-app/` 是 Swift 原生工程，Linux 无 Xcode 无法构建。
- [x] 确认工具链：Node v22.14.0、Python 3.12.3 已就绪；仓库无外部依赖（`shuyu/package.json`
  无 dependencies，`pyproject.toml` 仅配 ruff），开箱即用。
- [x] 运行 shuyu 引擎全套测试并跑通：Node `node --test tests/*.test.mjs` → 84/84 通过；
  Python `python3 -m unittest discover -s tests` → 33/33 通过。
- [x] 实际运行应用：
  - Python CLI（`--count` / `--id` / `--coin` / `--search`）正常输出。
  - 起本地 HTTP 适配器把 `worker.mjs` 的 `fetch` 跑成实时服务，逐一验证
    `/ /decode /encode /search /compose /coin /talk /status` 全部返回正确。
  - 起静态服务器打开 `shuyu.html`，浏览器交互（重新造词 / 跑意识流）正常，已录屏。
  - 交叉验证：种子 `神枢` 在 Python 与 JS Worker 都得到同一编号 780009883，双实现同构成立。
- [x] 新增 `.cursor/environment.json`：无外部依赖，`install` 阶段跑 shuyu 双实现测试作为
  开箱冒烟校验，保证后续 Cloud Agent 拉起即为健康环境。
- [x] 触发一次环境草稿构建，验证 `.cursor/environment.json` 可用。
- [x] 归档本 TODO 到 `docs/done/`，提交并建 PR。

## 总结

本分支开发环境**开箱即用**：基础镜像已带 Node v22 与 Python 3.12，仓库无需 `npm install`/`pip install`
（无第三方依赖）。可运行主体为 `shuyu/` 枢语引擎——Node 84 项 + Python 33 项测试全绿，CLI、
CF Worker HTTP API、`shuyu.html` 浏览器演示均实测可用，且 Python↔JS 双实现对同一种子产出同一编号，
一致性成立。新增 `.cursor/environment.json` 把上述测试固化为 `install` 阶段的冒烟校验，让后续
Cloud Agent 一拉起就跑一遍双实现测试，环境不健康会当场暴露。iOS 原生工程因 Linux 无 Xcode
不在本环境构建范围内。
