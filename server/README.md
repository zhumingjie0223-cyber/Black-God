# Black God Server

Black God 后端服务器（Python）

## 🚀 快速启动

### 1. 安装依赖

```bash
pip3 install anthropic openai requests
```

### 2. 配置环境变量

```bash
export BG_BASE=http://your-model-gateway/v1
export BG_KEY=your-api-key
export BG_MODEL=auto
```

### 3. 启动服务

```bash
cd server/
python3 server.py
```

服务将运行在 `http://0.0.0.0:8765`

---

## 📁 项目结构

```
server/
├── server.py           # 主服务器（HTTP Server + Agent）
├── start.sh            # 启动脚本
├── core/               # 核心模块
│   ├── agent.py        # Agent 引擎
│   ├── tools.py        # 工具调用
│   └── prompt.py       # Prompt 管理
├── memory/             # 记忆系统
│   ├── global.json     # 全局记忆
│   └── daily/          # 每日记忆
└── skills/             # 技能库（73个技能）
```

---

## 🔧 API 接口

### 1. `/api/chat` - 对话执行

```bash
POST /api/chat
Content-Type: application/json

{
  "message": "帮我写一个冒泡排序",
  "research_mode": false,
  "web_search_enabled": true
}
```

**响应：**
```json
{
  "response": "代码内容...",
  "steps": [
    {"tool": "shell_execute", "status": "success"}
  ],
  "execution_time": 2.3
}
```

### 2. `/api/stats` - 统计信息

```bash
GET /api/stats
```

**响应：**
```json
{
  "skills": 73,
  "tools": 15,
  "completed_tasks": 9
}
```

### 3. `/api/memory` - 记忆管理

```bash
POST /api/memory
Content-Type: application/json

{
  "action": "save",
  "content": "用户偏好：喜欢简洁代码"
}
```

### 4. `/api/tasks` - 任务列表

```bash
GET /api/tasks
```

### 5. `/api/capabilities` - 能力清单

```bash
GET /api/capabilities
```

---

## 🧠 核心特性

### Agent 引擎
- 自动规划（多步推理）
- 工具调用（15+ 工具）
- 验证驱动（执行后验证）
- 错误重试（失败自动修复）

### 工具系统
- `shell_execute` - 执行命令
- `browser_use` - 浏览器自动化
- `file_write` - 写文件
- `file_read` - 读文件
- `memory_write` - 保存记忆
- `memory_get` - 查询记忆
- 更多...

### 技能系统
- 73 个专业技能
- 动态加载（按需注入）
- 关键词触发

---

## 🔒 安全配置

### 环境变量

| 变量 | 说明 | 示例 |
|------|------|------|
| BG_BASE | API 基础 URL | http://localhost:9000/v1 |
| BG_KEY | API 密钥 | sk-blackgod-xxx |
| BG_MODEL | 模型名称 | auto |

### 端口配置

默认端口：`8765`

修改端口：
```python
# server.py
server = HTTPServer(('0.0.0.0', 8765), RequestHandler)
```

---

## 📊 性能指标

- API 响应时间：0.2-0.5s
- 简单任务执行：2-3s
- 并发支持：50+ QPS

---

## 🐛 调试

### 查看日志

```bash
tail -f /var/log/bg-agent.log
```

### 健康检查

```bash
curl http://localhost:8765/health
```

---

## 🚢 部署

### Systemd 服务

```ini
[Unit]
Description=Black God Agent
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bg-agent
Environment="BG_BASE=http://localhost:9000/v1"
Environment="BG_KEY=sk-blackgod-xxx"
Environment="BG_MODEL=auto"
ExecStart=/usr/bin/python3 /opt/bg-agent/server.py
Restart=always

[Install]
WantedBy=multi-user.target
```

启动服务：
```bash
systemctl enable bg-agent
systemctl start bg-agent
systemctl status bg-agent
```

---

## 📝 开发

### 添加新工具

编辑 `core/tools.py`：

```python
def new_tool(params):
    """新工具"""
    # 实现逻辑
    return {"result": "success"}
```

### 添加新 API

编辑 `server.py`：

```python
def _new_api(self):
    """新接口"""
    data = self._get_json_body()
    # 处理逻辑
    self._json({"success": True})
```

---

## 🔗 相关链接

- **前端**: [../web/](../web/)
- **文档**: [../docs/](../docs/)
- **GitHub**: https://github.com/uumingtian-max/blackgod

---

## 📄 许可证

MIT License
