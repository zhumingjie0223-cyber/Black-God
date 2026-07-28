# TODO · 逆向工具箱 nexus_reverse.mjs

任务:把权哥发的网页逆向片段(JSVMP hook + 魔改 base64 + RC4)做成神枢的正式功能模块。
定位:补进现有安全/逆向线(hijack 劫持工坊 / redteam / execBrowse),将来自动分析
加密/反爬网站时的拆解工具;公开版技术用户也用得到。

范围:新建独立模块 web/nexus-do/nexus_reverse.mjs + 自测,不碰 4644 行核心大文件。只增不删。

- [x] 读 web/nexus-do 现有模块风格(ESM export 约定)
- [x] nexus_reverse.mjs:自定义字母表 base64 编/解码(UTF-8 安全,往返成立)
- [x] nexus_reverse.mjs:RC4 加/解密(对称,字节级,base64 包装便于文本往返)
- [x] nexus_reverse.mjs:JSVMP 追踪 hook 生成器
- [x] nexus_reverse.test.mjs:base64 标准+魔改往返 + RC4 已知向量+往返 + hook 生成 + 报错分支
- [x] node --test 10/10 全绿(RC4 教科书向量 bbf316e8d940af0ad3 验证正确)
- [x] 提交推送 PR #86
- [x] 归档 TODO 到 docs/done/

## 总结
逆向工具箱落地:base64(可传网站魔改字母表)、RC4(对称,含 base64 包装)、JSVMP apply 追踪
hook 生成器,全为确定性纯函数、UTF-8 安全、10 个测试全绿(含 RC4 标准向量验证)。
独立模块 nexus_reverse.mjs,未碰核心,只增不删。后续接入 agent 动作集/hijack 工坊时
继续走 dangerReason/确认门,本次只交付模块本体。
