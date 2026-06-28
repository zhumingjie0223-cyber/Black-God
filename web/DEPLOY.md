# Black God 网站首页 —— 上线说明

这套 `web/` 文件是 **aquan.love 的新版黑金品牌首页**。做好后需要放到服务器上才能生效。

## 文件清单

```
web/
├── index.html      # 品牌首页（主入口）
├── theme.css       # 黑金主题样式
├── manifest.json   # PWA 配置（可添加到主屏幕）
├── sw.js           # 离线缓存 Service Worker
├── logo.png        # 「神」字 Logo
├── icon-192.png    # PWA 图标
└── icon-512.png    # PWA 图标
```

## 怎么让它在 aquan.love 生效（交给服务器维护方照做）

服务器上现有站点目录是 `/opt/bg-agent/web/`，端口 `8765`，服务名 `bg-agent.service`。

```bash
# 1. 备份现有首页（保险起见）
cp /opt/bg-agent/web/index.html /opt/bg-agent/web/index.html.bak_$(date +%Y%m%d_%H%M%S)

# 2. 把本仓库 web/ 下的文件拷到服务器站点目录
#    （从仓库拉取后执行，或用 scp 上传）
cp web/index.html web/theme.css web/manifest.json web/sw.js \
   web/logo.png web/icon-192.png web/icon-512.png \
   /opt/bg-agent/web/

# 3. 重启服务（按实际服务名）
systemctl restart bg-agent.service

# 4. 验证
curl -I http://127.0.0.1:8765/            # 应返回 200
curl    http://127.0.0.1:8765/api/health  # 应返回 {"status":"ok"}
```

然后手机浏览器打开 `http://aquan.love`，应看到黑金新首页。
iOS Safari：分享 → 添加到主屏幕；Android Chrome：会自动提示安装。

## 首页依赖的后端接口（服务器现有，无需改动）

- `POST /api/chat`   —— 输入框「开始执行」调用
- `GET  /api/tasks`  —— 「最近任务」区域调用
- `GET  /api/health` —— 健康检查

> 说明：首页是纯静态前端，不含任何密钥。后端接口由服务器上的 `server.py` 提供，本次不改动后端。
