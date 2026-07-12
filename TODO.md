# 任务:企业级工业产品深度补全(权哥 2026-07-12 指令)

目标:把 CLAUDE.md 承诺但缺失的企业级工程设施全部落地(本仓是枢语引擎消费方,
源头侧同步工作在 shuyu-lang 仓同名分支进行)。

- [ ] 1. 建 tools/check-sync.mjs(与 shuyu-lang 源头引擎结构化比对;无源头仓时
       退化为内置指纹自检,供 CI 独立运行)
- [ ] 2. 建 tools/sync-ui.mjs(--check 校验 index.html 与构建注入 nexus_do.mjs 的
       双副本同步;默认模式重建)
- [ ] 3. 建 web/design/tokens.css 设计令牌单一事实源(深海·潮光色系,兼容现有金色品牌 Logo)
- [ ] 4. 建 docs/design/DESIGN_SYSTEM_V3.md(色系/字体五族/卡片 10-8-2 圆角/动效规则)
- [ ] 5. 修正 web/nexus-do/lexicon.js 过期容量注释(29.5亿 → 76.7亿)
- [ ] 6. 建 .github/workflows/engine-ci.yml(nexus-do 构建+自测+双副本校验+引擎指纹自检)
- [ ] 7. 全量跑测(npm test + 两个新工具) → 提交推送 claude/enterprise-industrial-product-5pjj95 → 开草稿 PR
- [ ] 8. 总结归档 docs/done/
