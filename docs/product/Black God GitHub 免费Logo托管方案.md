# Black God Logo GitHub 免费托管方案

## 用 GitHub 免费做什么

1. **免费托管 Logo 文件**
   - `logo.svg`
   - `icon.svg`
   - `icon-512.png`
   - `apple-touch-icon.png`
   - `favicon.png`

2. **免费跑 GitHub Actions**
   - 自动把 SVG 转成 PNG
   - 自动压缩图片
   - 自动生成 App 图标尺寸

3. **免费开 GitHub Pages**
   - 做一个 Black God 品牌展示页
   - 地址类似：`https://uumingtian-max.github.io/blackgod-brand/`

4. **免费当静态资源 CDN**
   - 原始文件可通过 raw.githubusercontent.com 访问
   - 也可以配合 jsDelivr CDN：
     `https://cdn.jsdelivr.net/gh/用户名/仓库名@main/logo.svg`

---

## 推荐仓库名

`blackgod-brand`

## 目录结构

```text
blackgod-brand/
├── README.md
├── index.html
├── assets/
│   ├── logo.svg
│   ├── icon.svg
│   ├── poster-logo.svg
│   └── generated/
│       ├── icon-512.png
│       ├── icon-192.png
│       ├── apple-touch-icon.png
│       └── favicon.png
└── .github/
    └── workflows/
        └── build-icons.yml
```

---

## 免费路线

### 方案 A：只托管文件
最简单，上传 SVG 文件即可。

### 方案 B：自动生成 PNG
用 GitHub Actions 自动装 `librsvg2-bin`，执行：

```bash
rsvg-convert -w 512 -h 512 assets/icon.svg -o assets/generated/icon-512.png
rsvg-convert -w 192 -h 192 assets/icon.svg -o assets/generated/icon-192.png
rsvg-convert -w 180 -h 180 assets/icon.svg -o assets/generated/apple-touch-icon.png
rsvg-convert -w 32 -h 32 assets/icon.svg -o assets/generated/favicon.png
```

### 方案 C：GitHub Pages 展示页
开启 Settings → Pages → Deploy from branch → main 即可。

---

## Black God 线上可用方式

等 GitHub 文件生成后，Black God 页面可以引用：

```html
<link rel="apple-touch-icon" href="https://cdn.jsdelivr.net/gh/uumingtian-max/blackgod-brand@main/assets/generated/apple-touch-icon.png">
<link rel="icon" href="https://cdn.jsdelivr.net/gh/uumingtian-max/blackgod-brand@main/assets/generated/favicon.png">
<img src="https://cdn.jsdelivr.net/gh/uumingtian-max/blackgod-brand@main/assets/icon.svg" alt="Black God">
```

---

## 结论

GitHub 免费够用。  
最适合拿来放 Black God 的品牌素材、Logo、图标、展示页和自动构建流程。
