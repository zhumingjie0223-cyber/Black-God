FROM node:22-alpine
RUN apk add --no-cache bash git curl python3 ctags chromium nss freetype harfbuzz ca-certificates
ENV CHROME_PATH=/usr/bin/chromium-browser PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
WORKDIR /app
COPY package.json ./
RUN npm install --omit=dev
COPY task_runner.mjs .
EXPOSE 8080
CMD ["node","task_runner.mjs"]
