# 【最高优先级铁律 · TODO.md 驱动执行】

**接到任何多步骤任务,先列清单再动手——防跑偏纪律,任何时候不得违反:**

1. 接到任何多步骤任务,动手前先在仓库根目录写一个 `TODO.md`,把任务拆成可勾选的
   步骤清单(`- [ ] 步骤`)。
2. 每完成一步,立刻把对应项改成 `- [x]` 并写一句结果。
3. 当上下文变长、或感觉快忘了目标时,重新读一遍 `TODO.md` 找回方向,严禁凭记忆瞎跑。
4. 任务全部完成后,`TODO.md` 末尾写一段总结,再把它归档到 `docs/done/` 里。
5. 中途权哥打断或换方向,先更新 `TODO.md` 再执行新指令,保证任何时候看 `TODO.md`
   都知道干到哪了。

# Black God — 项目指南

神枢(Nexus)· 主动型智能体产品:Cloudflare Workers 三项目部署
(blackgod88 静态站 / nexus-do 大脑 / nexus-studio 工作台)+ iOS 应用。

## 常用命令

```bash
cd web/nexus-do && node build.mjs && node selftest.mjs   # 构建 + 83 项自测(改 UI 必跑)
node tools/sync-ui.mjs --check                           # UI 双副本同步校验
```

## 铁律

- **UI 一切样式走设计令牌**:单一事实源 `web/design/tokens.css`,规范见
  `docs/design/DESIGN_SYSTEM_V3.md`(深海·潮光色系/字体五族/卡片 10-8-2 圆角),
  禁止页面私设色值;动效只用 transform/opacity。
- 改 `web/nexus-do/index.html` 后必须重新构建(页面是构建时整体注入 Worker 的)。
- `web/nexus-do/lexicon.js` 是枢语引擎消费方副本,**权威源头在 shuyu-lang 仓库**,
  改词根表/编码规则必须两仓同步并跑 shuyu-lang 的 `tools/check-sync.mjs`。
- `/api/confirm` 危险操作二次确认是安全红线,任何重构不得移除。
- **所有面向权哥的输出一律中文**(对话/提交说明/PR/文档),禁止中英夹杂。
