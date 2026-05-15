#!/bin/sh
set -e

# 生成随机本地端口（供 xtunnel 和 cloudflared 内部使用）
WS_PORT=$(shuf -i 10000-60000 -n 1)
METRICS_PORT=$(shuf -i 10000-60000 -n 1)

# 启动一个简单的 HTTP 服务器，监听 8080 用于健康检查
( while true; do echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | nc -l -p 8080 -q 1; done ) &
HEALTH_PID=$!

# 启动 xtunnel 作为服务端（监听本地 WebSocket）
echo "Starting xtunnel on ws://127.0.0.1:$WS_PORT"
if [ -z "$XTUNNEL_TOKEN" ]; then
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" &
else
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" -token "$XTUNNEL_TOKEN" &
fi
XTUNNEL_PID=$!

sleep 2

# 启动 cloudflared 隧道，将外部流量转发到 xtunnel 的 WebSocket 端口
echo "Starting cloudflared tunnel (IP version: ${EDGE_IP_VERSION:-4})"
/usr/local/bin/cloudflared tunnel --edge-ip-version "${EDGE_IP_VERSION:-4}" \
    --protocol http2 \
    --url "http://127.0.0.1:$WS_PORT" \
    --metrics "0.0.0.0:$METRICS_PORT" &
CLOUDFLARED_PID=$!

# 等待任意进程退出（容器会重启）
wait $XTUNNEL_PID $CLOUDFLARED_PID $HEALTH_PID
