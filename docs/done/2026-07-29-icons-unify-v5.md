# 全站图标统一到 v5 + PWA 启动屏改深色

权哥全权授权后，把品牌图标全站统一到 v5 阿泉风。

## 图标链路（核实后）
- worker 图标全部来自 `icon_asset.mjs` 两个内联常量：
  ICON_PNG_B64（apple-touch/icon-192/icon-180/logo.png/shen-icon 共用）、
  ICON_PNG_512_B64（icon-512）；favicon `ICON_SVG` 复用 ICON_PNG_B64 + rx112 圆角裁切。
- PWA manifest 内联在 nexus_do.core.mjs。

## 改动
- icon_asset.mjs：ICON_PNG_B64 → v5@192px、ICON_PNG_512_B64 → v5@512px
  （favicon/apple-touch/主屏图标/页面 <img src=/logo.png> 全部随之升级 v5）
- manifest 启动屏 background_color/theme_color：浅色 #F4FBF6 → 深色 #0A100C
  （深色玉绿 app 启动屏不再刺眼白屏）
- 同步实体文件 web/logo.png、icon-192、icon-512、shen-icon → v5 对应尺寸
- icon_asset.mjs 体积 559KB→519KB（v5 反而更省）

## 验证
- node build.mjs 重建 + node selftest.mjs 228 全过
- icon_asset.mjs 确认含 v5 base64；manifest 深色进产物
- 无头渲染 favicon（ICON_SVG）确认 v5 圆角裁切完整无损

未改 index.html（logo 底图上一提交已换 v5）。theme-color meta 已随主题切换，无需动。
