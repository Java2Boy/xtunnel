#!/bin/sh
set -e

# 将所有输出重定向到标准输出（便于平台收集日志）
exec >&2

echo "========================================="
echo "==> Starting entrypoint script"
echo "========================================="

# 检查必需环境变量
if [ -z "$KOMARI_TOKEN" ]; then
    echo "ERROR: KOMARI_TOKEN environment variable is not set."
    echo "Please set KOMARI_TOKEN in apply.build environment variables."
    exit 1
fi

echo "==> KOMARI_TOKEN is set, proceeding."

# 安装 komari-agent
echo "==> Installing komari-agent..."
if curl -fsSL https://raw.githubusercontent.com/luodaoyi/komari-zig-agent/main/install.sh | sh -s -- \
    --endpoint ${KOMARI_ENDPOINT:-https://ping.25t.de5.net} \
    --token ${KOMARI_TOKEN}; then
    echo "==> komari-agent installed successfully."
else
    echo "ERROR: Failed to install komari-agent."
    exit 1
fi

# 检查必要命令
for cmd in shuf curl nc; do
    if ! command -v $cmd >/dev/null 2>&1; then
        echo "ERROR: $cmd not found. Please check Dockerfile."
        exit 1
    fi
done

# ------------------------------
# 2. 准备 suoha 隧道
# ------------------------------
IP_VERSION=${IP_VERSION:-4}
XTUNNEL_TOKEN=${XTUNNEL_TOKEN:-""}

# 获取两个随机端口
WS_PORT=$(shuf -i 10000-60000 -n 1)
METRICS_PORT=$(shuf -i 10000-60000 -n 1)

echo "==> Using WS_PORT=$WS_PORT, METRICS_PORT=$METRICS_PORT"

# 下载 xtunnel 和 cloudflared
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64)
        XTUNNEL_URL="https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-amd64"
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
        ;;
    aarch64|arm64)
        XTUNNEL_URL="https://www.baipiao.eu.org/xtunnel/x-tunnel-linux-arm64"
        CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

echo "==> Downloading xtunnel from $XTUNNEL_URL"
curl -L -o /usr/local/bin/xtunnel "$XTUNNEL_URL" || { echo "Failed to download xtunnel"; exit 1; }
chmod +x /usr/local/bin/xtunnel

echo "==> Downloading cloudflared from $CLOUDFLARED_URL"
curl -L -o /usr/local/bin/cloudflared "$CLOUDFLARED_URL" || { echo "Failed to download cloudflared"; exit 1; }
chmod +x /usr/local/bin/cloudflared

# 启动 xtunnel
echo "==> Starting xtunnel on ws://127.0.0.1:$WS_PORT"
if [ -z "$XTUNNEL_TOKEN" ]; then
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" &
else
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" -token "$XTUNNEL_TOKEN" &
fi
XTUNNEL_PID=$!
sleep 2

# 启动 cloudflared
echo "==> Starting cloudflared tunnel (IPv$IP_VERSION)"
/usr/local/bin/cloudflared tunnel --edge-ip-version "$IP_VERSION" \
    --protocol http2 \
    --url "http://127.0.0.1:$WS_PORT" \
    --metrics "0.0.0.0:$METRICS_PORT" &
CLOUDFLARED_PID=$!

# 启动 HTTP 健康检查服务
echo "==> Starting health check HTTP server on port 8080"
( while true; do echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | nc -l -p 8080 -q 1; done ) &
HEALTH_PID=$!

# 后台任务获取 Argo 域名并打印
(
    sleep 5
    for i in 1 2 3 4 5 6 7 8 9 10; do
        DOMAIN=$(curl -s "http://127.0.0.1:$METRICS_PORT/metrics" 2>/dev/null | grep -oE 'userHostname="https?://([^"]+)"' | sed 's/userHostname="https\?:\/\///; s/"//')
        if [ -n "$DOMAIN" ]; then
            echo "🎉 Argo tunnel domain: https://$DOMAIN"
            break
        fi
        sleep 3
    done
) &

echo "==> All services started. Waiting for processes to exit..."
wait $XTUNNEL_PID $CLOUDFLARED_PID $HEALTH_PID
