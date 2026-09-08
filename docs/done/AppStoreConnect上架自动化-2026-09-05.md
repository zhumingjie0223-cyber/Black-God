# TODO — App Store Connect 上架自动化（让权哥只剩最少手工步骤）

> 背景：权哥要把开发者账号给我帮忙上架。我在 Linux 云机，不能跑 Xcode，也登不进 Apple 账号（需 2FA）。
> 能做的：写一个 App Store Connect API 工具，权哥把 API 密钥放进 Secrets 后，我一条命令把 Bundle ID 注册、
> 中英文案/关键词/宣传语/隐私链接/支持链接全部推上去。分支 `cursor/asc-automation-96d7`（off main）。

- [x] 1. `ios-app/AppStore/asc.py`：零第三方依赖（stdlib + cryptography）的 ASC API 客户端
  - ES256 JWT 签发（raw r||s 不是 DER），20 分钟内复用
  - `validate` / `check` / `register-bundle-id` / `push-metadata [--dry-run]` 四个子命令
  - 发送前按 Apple 字数上限校验；首版 whatsNew 被拒自动去字段重试；无凭据进离线计划模式
- [x] 2. 本机测试：临时 EC 密钥签 JWT 并用公钥验签；/tmp 假 Apple 跑通全流程 → 14 项断言全绿
  （PATCH/POST 分流、无可编辑版本按 project.yml 新建、whatsNew 重试、dry-run 不发写请求）；
  `validate` 实测中英文案全部在上限内（en-US subtitle 29/30 最贴边）
- [x] 3. `SUBMIT_GUIDE.md` 加「快速通道」：权哥 3 步手工 + agent 5 条命令，并明确哪些仍必须网页手工
- [x] 4. 提交 + 推送 + PR + 归档

## 结论（2026-09-05 完成）

**权哥说"开发者账号给你"。** 如实回答：账号密码 + 二次验证码给我没用也不安全（验证码打手机、我在 Linux 登不了 Xcode）。
真正能交给我的是一把权限受限的 **App Store Connect API 密钥**（App Manager 权限，走 Cursor Secrets 注入，不进聊天不进 git）。

**做了什么**：把上架流程里所有 API 开放的"填表"活写成 `asc.py`——Bundle ID 注册、中英文名称/副标题/隐私链接、
描述/关键词/推广文本/支持链接一条命令推完；没凭据也能离线校验和看计划。没有真 Apple 可测，就用假 Apple + 真密码学
把 JWT 和请求分流全跑了一遍。

**还剩权哥 3 步手工**（只有账号持有人能点）：生成 API 密钥、放进 Secrets、网页新建 App 记录（Apple API 不开放建 App）。
**推完文案后仍需网页手工**：截图、类别、年龄分级、App 隐私问卷、定价、选构建、审核备注。
**出包永远在 macOS**：本机 Xcode 或 Codemagic（`codemagic.yaml` 已就位，只差后台加一个用同一把密钥的集成）。

**教训记一笔**：连续两轮 `git mv TODO.md docs/done/…` 都把上一版内容提交了——Write 落盘和紧随其后的 shell 有竞态。
以后归档前先在 shell 里读一遍文件确认内容，再 mv + commit。
