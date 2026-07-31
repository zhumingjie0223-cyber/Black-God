# TODO — 执行脑真沙箱·代码加固(权哥 2026-07-19)

方向:执行脑(真沙箱的手)的代码这层先硬化。端到端真机验证需等新加坡服务器在线
(沙箱这边网络出不去,连不上 8443),但超时兜底、破坏性命令二次确认这些能自测的先补齐。

## 步骤
- [x] execRemote 加客户端超时兜底(AbortController 65 秒硬断,服务器 60 秒),绝不悬死;超时如实报。
- [x] 破坏性命令识别 dangerReason/isDangerousCmd:保守清单(rm -rf 根/家/通配、mkfs、dd 裸写、
      关机重启、fork 炸弹、curl|sh、chmod -R 根、抹 fs 签名),只拦真正不可逆/毁机的。
- [x] execRemote 危险命令需 confirm 才真跑(安全红线,同 /import?confirm);未接入优先于危险判定。
- [x] 直调 exec 能力入口透传 confirm(params.confirm===true)。
- [x] selftest +10 用例(各类危险识别/常规不误拦/未确认拦下/未接入优先)。
- [x] build + selftest(191 全过) + node --check + sync-ui --check 双副本一致。
- [ ] 中文提交 → 力推分支 → 建草稿 PR → 合并自动部署。

## 红线
- /api/confirm 二次确认不动,反而把这层安全思想延伸到执行脑;不碰词根表、身份归一化。
- 危险清单保守,常规命令(ls/git/node/npm/build/rm -f 单文件)照常放行,不阻碍真执行。
