#!/bin/bash
set -e

# 生成随机本地端口（避免冲突）
WS_PORT=$(shuf -i 10000-60000 -n 1)
METRICS_PORT=$(shuf -i 10000-60000 -n 1)

echo "启动 xtunnel 监听 ws://127.0.0.1:$WS_PORT"
if [ -z "$XTUNNEL_TOKEN" ]; then
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" &
else
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" -token "$XTUNNEL_TOKEN" &
fi
XTUNNEL_PID=$!

sleep 2

echo "启动 cloudflared 隧道 (IP版本: ${EDGE_IP_VERSION})"
/usr/local/bin/cloudflared tunnel --edge-ip-version "$EDGE_IP_VERSION" \
    --protocol http2 \
    --url "http://127.0.0.1:$WS_PORT" \
    --metrics "0.0.0.0:$METRICS_PORT" &
CLOUDFLARED_PID=$!

# 等待并捕获退出信号
wait $XTUNNEL_PID $CLOUDFLARED_PID
