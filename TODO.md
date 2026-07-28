# TODO · 私人版全面强化方案 + 竞品对标

- [x] 出六轴 22 项强化方案(docs/私人版全面强化方案-2026-07-28.md)
- [x] 提交推送建 PR #86
- [x] 读权哥上传的竞品逆向资料(19 份 .md 有用 / 20 个 html·jsurls·bundle·空defs 无用)
- [x] 消化竞品精华,识别神枢三大能力缺口(MCP 扩展 / Plan-Act 双模式 / grounding 依据链)
- [x] 方案追加「竞品对标」章节 + 三项新增能力(七/八/九)
- [ ] 推送更新 PR
- [ ] 定实施第一刀(问权哥),动手改代码

## 竞品对标结论(消化后)
- 神枢独有底盘:DO+alarm 常驻意识,竞品全是「云端一次性会话」——时间维度+归属维度双代差不变。
- 竞品印证的已有方案:持久工作区(Manus/Devin/Replit)、跨天续跑/异步job队列(Manus/Lovable)、
  精准编辑(Aider/Devin/Hermes 的 str_replace,神枢 execEditFile 已有)、自我修正(Manus,神枢 execDevLoop 已有)、
  执行剧场(Manus VNC,神枢 broadcast 已有)、分级确认(Cline/Manus,神枢 dangerReason 已有)。
- 竞品暴露的真缺口 → 新增三项:
  ① MCP 动态工具扩展(Cline/Lovable/Copilot 都有,神枢零)——最大缺口,像装插件一样接第三方能力。
  ② Plan/Act 双模式 + 计划确认(Cline/Lovable)——先出计划给权哥拍板再执行,配 /api/confirm。
  ③ grounding 依据链(Gemini)——每次执行/回答带「依据:读了X·跑了Y·验证Z」,契合诚实人格。
- 具身轴深化清单(Minis):HealthKit/Vision-OCR/Speech/HomeKit/NFC/Location,是 iOS 工具扩展方向。
