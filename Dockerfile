# ==================== 构建阶段 ====================
FROM alpine:3.19 AS builder

RUN apk add --no-cache gcc musl-dev go git upx

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

WORKDIR /build

COPY x-tunnel.go .

# 初始化模块并下载依赖（兼容新版 Go）
RUN go mod init xtunnel && \
    go mod tidy && \
    go build -ldflags="-s -w" -o xtunnel x-tunnel.go && \
    upx --best --lzma xtunnel

# ==================== 运行阶段 ====================
FROM alpine:3.19

RUN apk add --no-cache ca-certificates bash curl coreutils netcat-openbsd

# 下载 cloudflared
ADD https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 /usr/local/bin/cloudflared
RUN chmod +x /usr/local/bin/cloudflared

# 从构建阶段复制 xtunnel
COPY --from=builder /build/xtunnel /usr/local/bin/xtunnel
RUN chmod +x /usr/local/bin/xtunnel

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV XTUNNEL_TOKEN=""
ENV EDGE_IP_VERSION="4"

EXPOSE 8080

CMD ["/entrypoint.sh"]
