#!/bin/bash
set -e

# ------------------------------
# 1. 安装 komari-agent
# ------------------------------
echo "==> Installing komari-agent..."
curl -fsSL https://raw.githubusercontent.com/luodaoyi/komari-zig-agent/main/install.sh | sh -s -- \
    --endpoint ${KOMARI_ENDPOINT:-https://ping.25t.de5.net} \
    --token ${KOMARI_TOKEN}

# ------------------------------
# 2. 准备 suoha 隧道（非交互式）
# ------------------------------
# 定义要运行的 xtunnel + cloudflared 参数
# 从环境变量读取配置
IP_VERSION=${IP_VERSION:-4}
XTUNNEL_TOKEN=${XTUNNEL_TOKEN:-""}

# 获取两个随机端口
WS_PORT=$(shuf -i 10000-60000 -n 1)
METRICS_PORT=$(shuf -i 10000-60000 -n 1)

# 下载 xtunnel 和 cloudflared（根据架构）
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

echo "==> Downloading xtunnel..."
curl -L -o /usr/local/bin/xtunnel "$XTUNNEL_URL"
chmod +x /usr/local/bin/xtunnel

echo "==> Downloading cloudflared..."
curl -L -o /usr/local/bin/cloudflared "$CLOUDFLARED_URL"
chmod +x /usr/local/bin/cloudflared

# 启动 xtunnel 服务端
echo "==> Starting xtunnel on ws://127.0.0.1:$WS_PORT"
if [ -z "$XTUNNEL_TOKEN" ]; then
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" &
else
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" -token "$XTUNNEL_TOKEN" &
fi
XTUNNEL_PID=$!

sleep 2

# 启动 cloudflared 隧道
echo "==> Starting cloudflared tunnel (IPv$IP_VERSION)"
/usr/local/bin/cloudflared tunnel --edge-ip-version "$IP_VERSION" \
    --protocol http2 \
    --url "http://127.0.0.1:$WS_PORT" \
    --metrics "0.0.0.0:$METRICS_PORT" &
CLOUDFLARED_PID=$!

# ------------------------------
# 3. 启动 HTTP 健康检查服务（前台运行，保持容器存活）
# ------------------------------
echo "==> Starting health check HTTP server on port 8080"
# 使用 netcat 创建一个简单的 HTTP 服务器
( while true; do echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | nc -l -p 8080 -q 1; done ) &
HEALTH_PID=$!

# ------------------------------
# 4. 等待所有后台进程，并打印隧道域名
# ------------------------------
# 尝试从 cloudflared metrics 获取 argo 域名（可选）
(
    sleep 5
    for i in {1..20}; do
        DOMAIN=$(curl -s "http://127.0.0.1:$METRICS_PORT/metrics" 2>/dev/null | grep -oP 'userHostname="\K[^"]+' | head -1)
        if [ -n "$DOMAIN" ]; then
            echo "🎉 Argo tunnel domain: https://$DOMAIN"
            break
        fi
        sleep 2
    done
) &

# 等待任意子进程退出（容器会重启）
wait $XTUNNEL_PID $CLOUDFLARED_PID $HEALTH_PID
