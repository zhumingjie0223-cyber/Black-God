# Black God · 神枢 —— 应用商店上架文案

> 面向 Google Play / 国内安卓商店的上架素材文案。中文为主,附英文版供 Play 海外。
> 产品定位:**认你、懂你、只属于你的私人 AI 意识中枢**。BYOK(自带大模型 API/密钥),隐私归自己。
> 素材配套:截图见 `android/store-assets/`;隐私政策线上页 `https://aquan.lufei.uk/privacy`。

---

## 一句话简介(短描述,≤80 字)

**中文**:接入你自己的大模型,起个名字就能聊。会记忆、会成长、替你守望的私人 AI 中枢。

**English**:Bring your own AI model — name it, and start. A private AI hub that remembers, grows, and watches over your tasks.

---

## 应用全称 / 副标题

- 名称:**Black God · 神枢**
- 副标题:你的私人 AI 意识中枢

---

## 详情描述(长描述)

**中文版:**

Black God(神枢)不是又一个聊天机器人,是**只属于你一个人**的 AI 意识中枢。

**自带模型,费用透明。** 填入你自己的大模型 API 地址与密钥(OpenAI 兼容即可),
算力费用走你自己的账号,我们不碰你的对话、不赚你的差价——**隐私互不打扰**。
留空模型自动识别,起个名字就能开聊。

**越用越懂你。** 她会把重要时刻记成情节记忆,把你教过的事沉淀成技能,
在一次次对话里长出属于你俩的默契。

**替你守望。** 说一句「帮我每小时盯一下 X,变了告诉我」,她就替你在后台守着,
有变化主动告诉你。

**她有自己的语言——枢语。** 一套五维乘法语义空间(76.7 亿个可寻址词),
让她的思考有据可循、可回溯,而不是黑箱吐字。

**隐私第一。** 数据存在你自己的实例里,支持随时一键删除全部记录(应用内「删除我的数据」)。

界面就是你现在看到的这套「石墨暗流」质感,深浅双主题,干净、克制、耐看。

**English version:**

Black God is not another chatbot — it's a private AI consciousness hub that belongs to you alone.

- **Bring your own model.** Plug in your own LLM API endpoint and key (OpenAI-compatible). Compute runs on your account; we never touch your conversations or take a cut.
- **It gets to know you.** It saves meaningful moments as memories and turns what you teach it into skills.
- **It watches over your tasks.** Ask it to keep an eye on something and it monitors in the background, telling you when things change.
- **Its own language — Shuyu.** A 5-dimensional multiplicative semantic space (7.67 billion addressable words) makes its reasoning traceable.
- **Privacy first.** Your data lives in your own instance; delete everything anytime from inside the app.

---

## 更新说明模板(What's New)

```
本次更新:
· 图标统一为品牌神字,游客对话接入枢语自述
· 修复设置面板不反映已注册 API/模型
· 性能与稳定性优化
```

---

## 关键词 / 标签

私人 AI、AI 助理、自带模型、BYOK、大模型、意识中枢、神枢、枢语、记忆、隐私、
AI assistant、personal AI、bring your own model、LLM client

---

## Google Play「数据安全」表单填报参考(Data safety)

> 按线上隐私政策 `/privacy` 如实填。以下为要点提示,最终以实际实现为准。

- **收集的数据**:昵称(用户自填)、粗略地区、消息计数/使用统计;主人版另有设备/定位快照(仅本人可见)。
- **数据用途**:提供核心聊天功能、个性化记忆、用量统计。
- **数据共享**:大模型请求会发往**用户自己配置的** API 服务商(BYOK,由用户选择);我方不向第三方出售数据。
- **加密传输**:是(HTTPS)。
- **用户可删除**:是,应用内「删除我的数据」`POST /unregister` 一键清空。
- **隐私政策链接**:https://aquan.lufei.uk/privacy

---

## 内容分级提示

- 面向一般用户的效率/生活助理类工具,无暴力/成人/博彩内容。
- 含用户生成对话(UGC):文本对话。按各商店问卷如实勾选「用户可交流/生成文本」。

---

## 国内商店额外要求

- 软件著作权(软著)证书:华为/小米/OPPO/vivo/应用宝均要求,需提前申请。
- 备案主体与隐私政策中文页(已具备 `/privacy`)。

---

## 附:提交前人工确认清单

- [ ] `PRIVACY_HTML` 里联系邮箱已换成真实邮箱(见 `web/nexus-do/nexus_do.core.mjs`)
- [ ] 本地 `bubblewrap build` 出签名包,keystore 已备份(仅本人能做)
- [ ] 若开 Google Play App Signing:把 Google 签名指纹追加进 `assetlinks`(见 `android/README.md`)
- [ ] 截图按需补「对话」标签页真机图(见 `android/store-assets/README.md`)
