FROM node:22-alpine

RUN apk add --no-cache bash git curl python3

WORKDIR /app

COPY task_runner.mjs .

EXPOSE 8080

CMD ["node", "task_runner.mjs"]
