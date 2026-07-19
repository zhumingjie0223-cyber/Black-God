# TODO · Google Play(海外安卓/TWA)上架材料包

> 参数:域名 blackgod.lufei.uk · 包名沿用已有 uk.lufei.aquan.blackgod · 显示名 Black God。
> 核对:assetlinks 路由+env覆盖、manifest、内置包名与指纹——技术骨架已就绪,不动(动了废已有打包)。
> 本程只产出上架材料文档,不碰权哥证件(证件直接传 Google)。分支已从 origin/main 重建。

- [x] 0. 核对现状:assetlinks 路由(env覆盖)、manifest 完整、包名 uk.lufei.aquan.blackgod+指纹已内置。
- [x] 1. 写 docs/上架/Google-Play-TWA上架指南.md:谁做什么、前置、打包步骤、assetlinks对齐新域名。
- [x] 2. 商店文案定稿(应用名/简介/完整描述/关键词,中英)。
- [x] 3. Data safety 数据安全表单答案(按神枢真实隐私模型:BYOK/可导出/可删除/不卖不共享)。
- [x] 4. 上架 Checklist(你出资质截图 / 我出材料,可勾选)。
- [ ] 5. 提交推送;开新PR草稿;汇报。TODO归档 docs/done。

## 进度记录
- 关键:包名沿用 uk.lufei.aquan.blackgod(勿改);新域名 blackgod.lufei.uk 需绑到 Worker,
  assetlinks 走 https://blackgod.lufei.uk/.well-known/assetlinks.json(路由已支持)。

## 总结
Google Play(海外安卓/TWA)上架材料包完成:docs/上架/Google-Play-TWA上架指南.md——
谁做什么、域名绑定、TWA打包(Bubblewrap/PWABuilder)、assetlinks对齐(env覆盖追加Play签名指纹)、
商店文案(中英定稿)、Data safety表单答案(按神枢真实隐私模型)、上架Checklist、常见坑。
关键核对:TWA技术骨架(assetlinks路由+env覆盖、manifest、包名uk.lufei.aquan.blackgod+指纹)仓库已就绪,
不动;新域名blackgod.lufei.uk。海外不需软著/备案。证件全程你本人传Google,不经我手,未记录任何证件信息。
