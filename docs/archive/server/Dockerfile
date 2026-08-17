# Black God — 主系统 Docker 镜像
# 整个 Black God 内核跑在容器里，主系统即沙箱

FROM python:3.11-slim

# 设置时区
ENV TZ=Asia/Shanghai
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1

# 安装系统依赖
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    sqlite3 \
    && rm -rf /var/lib/apt/lists/*

# 工作目录
WORKDIR /app

# 复制项目文件
COPY server/ ./server/
COPY web/ ./web/

# 安装 Python 依赖（最小化）
RUN pip install --no-cache-dir \
    openai \
    flask \
    requests

# 创建数据目录（持久化挂载点）
RUN mkdir -p /app/server/memory /app/server/skills

# 暴露端口
EXPOSE 8765

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8765/api/health || exit 1

# 启动命令
CMD ["python3", "server/server.py"]
