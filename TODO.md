# TODO — 多脑注册表:神枢接入 1~9 条 API 自由调度(权哥 2026-07-19)

方向:所有模型 API 都能接进来供神枢自由调度。最低 1、正常 3、最高 9。
建在已完成的柱2 适配层之上(openai/anthropic 方言 + temperature 重试 + 身份归一化 + 诚实报错)。

## 设计
- 配置 cfg.brains:数组 ≤9,每条 {url,key,model,provider?,label?,on}。旧单网关自动迁为第1条(向后兼容)。
- 自由调度 = 有序故障转移 + 分级优先:按序试,挂了(限流/欠费/报错,靠真错捕获判定)自动换下一条,CF 兜底垫底。永不卡死一条。
- 每条走适配层 + temperature 重试 + 身份归一化 + 诚实报错(全失败带最后真因)。

## 阶段
- [x] 阶段一(后端):resolveBrains() 注册表解析(兼容旧单网关)+ callBrain 改多脑故障转移循环 + auto-model 按 url 缓存 + setConfig/getConfig 支持 brains 数组(key 掩码)+ 测试。callGateway(游客)暂保持单条(游客一条自己的即可)。
- [ ] 阶段二(UI):设置·大脑模型面板支持增删改 2~9 条(每条含一键粘贴),标签+开关+拖序。
- [ ] 各阶段:build+selftest+双副本+真机验证(Moonshot 至少一条真跑)→ 中文提交 → PR → 合并自动部署。

## 红线
- 向后兼容:现有单网关配置不丢、不退化;/api/confirm 不动;身份归一化/诚实报错保持。

## 附:Claude key 发现(2026-07-19)
权哥给的 sk-ant-oat01- 是 OAuth token(需 Authorization: Bearer,非 x-api-key;且限流、为 Claude Code 用)。
接 Claude 进神枢建议用标准 sk-ant-api03- key(适配层 x-api-key 直接支持)。
未来可给 anthropic 适配加 Bearer(OAuth)支持作为可选。
