# ==================== 构建阶段 ====================
FROM alpine:3.19 AS builder

# 安装编译工具
RUN apk add --no-cache gcc musl-dev go git upx

ENV GO111MODULE=on \
    CGO_ENABLED=0 \
    GOOS=linux \
    GOARCH=amd64

WORKDIR /build

# 复制源码并下载依赖（如果使用 go.mod）
COPY x-tunnel.go .
# 如果没有 go.mod，直接编译（本程序无外部依赖）
RUN go mod init xtunnel 2>/dev/null || true && \
    go get github.com/gorilla/websocket github.com/xtaci/smux github.com/google/uuid && \
    go build -ldflags="-s -w" -o xtunnel x-tunnel.go && \
    upx --best --lzma xtunnel

# ==================== 运行阶段 ====================
FROM alpine:3.19

# 安装运行时依赖（cloudflared 需要 ca-certificates）
RUN apk add --no-cache ca-certificates bash curl
RUN apk add --no-cache netcat-openbsd

# 下载 cloudflared（官方最新版，静态链接）
ADD https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 /usr/local/bin/cloudflared
RUN chmod +x /usr/local/bin/cloudflared

# 复制编译好的 xtunnel
COPY --from=builder /build/xtunnel /usr/local/bin/xtunnel
RUN chmod +x /usr/local/bin/xtunnel

# 创建启动脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 环境变量默认值（可在 apply.build 面板覆盖）
ENV XTUNNEL_TOKEN="" \
    EDGE_IP_VERSION="4"

EXPOSE 8080  # 占位端口，apply.build 要求暴露至少一个端口

CMD ["/entrypoint.sh"]
