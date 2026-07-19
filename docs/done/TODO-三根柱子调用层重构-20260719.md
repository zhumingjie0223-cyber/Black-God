# TODO — 神枢调用层地基改造:三根柱子(权哥 2026-07-19「去做吧」)

核心:重写模型调用层(callBrain/callGateway),把三条验收线焊进系统层,而非提示词。
铁律:先懂再动 · 不许假(真跑验过) · 只增不删既有能力 · /api/confirm 红线不动 · 保持 selftest 绿 + 双副本同步。

## 架构设计

统一"脑调用"管道(所有对话走它):
```
brainCall(system, userMsg, opts) →
 1. 解析 provider 配置(cfg.gateway_url/key/model | env | instance)
 2. 判定方言:openai | anthropic | cloudflare(按 URL/模型名特征或显式 cfg.provider)
 3. 用对应 ADAPTER 造请求(端点/头/体各家不同)
 4. 发送;失败则捕获真实原因(status + 错误体),不吞
 5. 重试阶梯:400 去 temperature 重试 → 换下一个脑
 6. 成功:用 adapter 的解析器取 text
 7. 出口归一化 normalizeIdentity(text, mode):抹掉"我是Kimi/由月之暗面开发"等自述→神枢/赵思涵
 8. 有真输出返回;全失败返回 {ok:false, error:真实原因}——绝无空壳
```

### 柱2 · Provider 适配层(集百家之长)
- `openai`:POST {base}/chat/completions,`Authorization: Bearer`,体 {model,messages,max_tokens,temperature},取 choices[0].message.content。(兼容 Kimi/DeepSeek/通义/GLM 等)
- `anthropic`:POST {base}/v1/messages,头 `x-api-key`+`anthropic-version`,体 {model,system,messages,max_tokens},取 content[0].text。← 让 claude-fable-5 真能被调
- `cloudflare`:env.AI.run(现有兜底脑)
- 判定:显式 cfg.provider 优先;否则按 URL(含 anthropic→anthropic)/模型名(claude-*→anthropic)推断

### 柱1 · 身份出口归一化(换脑不换魂,系统层)
- `normalizeIdentity(text, mode)`:确定性检测第一人称自述底层模型/厂商(我是X/我由X开发训练/作为X模型),替换为 公共=神枢(Black God)/ 主人=赵思涵。
- 保守匹配:只抓自我identification,不误伤"用户问及某模型"这类正常内容。
- 每条回复都过,不依赖提示词。

### 柱3 · 保证真输出 · 不空回响
- 删掉 callBrain 第 967 行"在,随时待命"空壳。
- 失败如实带出原因(401/429/余额/格式…);跨脑真重试;全失败→诚实报错给用户,绝不假装答了。

## 步骤
- [ ] 1. 摸清所有调用点:handleTalk / runAgentLoop / callBrain / callGateway / handlePubTalk / 及生图生声里的 callBrain
- [ ] 2. 写 adapter 层(纯函数造请求体+解析,可测)+ provider 判定
- [ ] 3. 重构 callBrain 用 adapter + 错误捕获 + 重试阶梯 + 删空壳
- [ ] 4. 重构 callGateway(游客)同构复用 adapter
- [ ] 5. normalizeIdentity 出口层,接到两条返回路径
- [ ] 6. 上层 caller 改成"失败报真错"(handleTalk/handlePubTalk)
- [ ] 7. 加测试(adapter 造体/身份归一/不空壳);build+selftest+sync 全绿
- [ ] 8. 真机验:Moonshot(openai 方言)跑通真回复 + 身份不漏;anthropic 造体单测
- [ ] 9. 中文提交推送 + PR
- [ ] 10. 总结归档

## 红线
- 不动神枢核心人格设定文案/词根/编码;/api/confirm 二次确认不动;既有 OpenAI 兼容 BYOK 路径不能退化
