FROM node:22-alpine
RUN apk add --no-cache bash git curl python3 ctags chromium nss freetype harfbuzz ca-certificates
ENV CHROME_PATH=/usr/bin/chromium-browser PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY task_runner.mjs .
# 伪命令桥：沙箱里可直接敲 nexus-memory / nexus-shuyu / nexus-soul 调神枢能力
COPY bin/ /usr/local/bin/
RUN chmod +x /usr/local/bin/nexus.mjs /usr/local/bin/nexus-memory /usr/local/bin/nexus-shuyu /usr/local/bin/nexus-soul
EXPOSE 8080
CMD ["node","task_runner.mjs"]
