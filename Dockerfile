# 构建阶段
FROM golang:1.21-alpine AS builder
RUN apk add --no-cache git
WORKDIR /app
COPY x-tunnel.go .
RUN go mod init xtunnel && \
    go get github.com/gorilla/websocket github.com/xtaci/smux github.com/google/uuid && \
    go build -o xtunnel x-tunnel.go

# 运行阶段
FROM alpine:latest
RUN apk add --no-cache ca-certificates bash curl coreutils netcat-openbsd

# 下载 cloudflared
ADD https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 /usr/local/bin/cloudflared
RUN chmod +x /usr/local/bin/cloudflared

COPY --from=builder /app/xtunnel /usr/local/bin/xtunnel
RUN chmod +x /usr/local/bin/xtunnel

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV XTUNNEL_TOKEN=""
ENV EDGE_IP_VERSION="4"

EXPOSE 8080

CMD ["/entrypoint.sh"]
