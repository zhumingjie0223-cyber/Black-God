# 变更日志 CHANGELOG

本项目重要变更记录。日期用绝对日期(UTC)。

## 2026-08-09 — UI 收口 + 词库恢复 + 配置清理(版本确认)

**版本确认(权哥拍板)：主界面 `web/nexus-do/index.html`(Black God)是唯一 UI，今后 UI 只做更新，不再维护多副本/多入口。**

### UI 收口
- 归档移除 3 个无路由服务的孤儿页(工作台 `studio.html`、语音合成 `voice.html`、控制台 `dashboard`)
  与死工作流 `deploy-studio.yml`，全部存 `docs/archive/ui-收口-2026-08-09/`(含核实结论与回退说明)。
- `tools/sync-ui.mjs` 收掉工作台双副本校验段(其权威源早已归档)，只保留主界面 ↔ 构建产物内嵌副本校验。
- README 工作台 UI 描述同步修正(原「内核 /studio 直达」为过时文档)。

### 词库
- 消费副本 `web/nexus-do/lexicon_data.js` 词族/编号表全量恢复至 `shuyu/` 权威源版(权哥拍板)；
  被替换的脱敏教育版归档 `docs/archive/脱敏教育版词库-2026-08-09.json` 可回退。情绪表(产品定制层)未动。

### 配置清理
- 归档删除过期部署配置 `web/nexus-do/wrangler.toml`(备份 `docs/archive/wrangler.toml.2026-08-09.bak`)；
  生产权威配置为 `wrangler.jsonc`，CI 全部工作流核实无一引用 toml。(backlog「wrangler 双配置」一条销案)

### 测试
- 构建、selftest 236/236、sync-ui、check-sync(词族/编号表一致)、枢语 JS 27/27 + Python 9/9 全部通过。

## 2026-08-03 — 收官整理(chore)

**清冗余 / 修遗留 / 更新文档索引** 一次性收官整理。

### 文档
- 新增 `docs/README.md`:docs/ 顶层目录导航,每个子目录一句话说明,详细逐文件清单指向既有 `docs/INDEX.md`。
- 新增 `docs/TODO-backlog.md`:记录代码扫描发现的不确定项(空 catch、wrangler 双配置、playwright-core 未锁版本),供后续定夺。
- 新增本 `CHANGELOG.md`。

### 构建 / 忽略规则
- `.gitignore` 新增忽略构建产物 `web/nexus-do/nexus_do.mjs`(由 `build.mjs` 生成);`index.built.html` 此前已忽略。已提交版本不删除。

### 依赖核查(未删任何依赖)
- `web/nexus-do/package.json`:无第三方 dependencies,version 1.0.0,scripts(build/pretest/test)正常,无废弃或重复字段。
- `web/nexus-do/container/package.json`:仅 `playwright-core: latest`。建议锁定具体版本以保证镜像可复现(记入 backlog,未擅改)。
- **发现但未删**:`web/nexus-do/` 同时存在过期的 `wrangler.toml` 与生产权威 `wrangler.jsonc`,属重复配置。涉部署红线,按铁律不擅删,建议归档删除 `wrangler.toml`(见 backlog),待权哥确认。

### 代码质量
- 扫描 `web/nexus-do` 全部 `.mjs`/`.js`:无真实 TODO/FIXME/HACK 遗留(唯一 "TODO" 是代码生成提示词字符串);9 处空 catch 均为尽力而为式吞异常或代码生成模板内容,非明确 bug;无 `.DS_Store`/`*.log`/`*.tmp` 等临时文件。**未发现确定 bug,无代码行为改动。**

### 测试
- `node --check nexus_do.core.mjs`、`node --check nexus_do.mjs`:通过。
- `npm run build`:通过。
- `npm test`:236/236 通过。
