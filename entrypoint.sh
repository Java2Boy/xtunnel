#!/bin/bash
set -e

WS_PORT=$(shuf -i 10000-60000 -n 1)
METRICS_PORT=$(shuf -i 10000-60000 -n 1)

echo "Starting xtunnel on ws://127.0.0.1:$WS_PORT"
if [ -z "$XTUNNEL_TOKEN" ]; then
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" &
else
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" -token "$XTUNNEL_TOKEN" &
fi
XTUNNEL_PID=$!

echo "Starting cloudflared (IP version: ${EDGE_IP_VERSION:-4})"
/usr/local/bin/cloudflared tunnel --edge-ip-version "${EDGE_IP_VERSION:-4}" \
    --protocol http2 \
    --url "http://127.0.0.1:$WS_PORT" \
    --metrics "0.0.0.0:$METRICS_PORT" &
CLOUDFLARED_PID=$()

# 等待任意进程退出（容器会重启）
wait $XTUNNEL_PID $CLOUDFLARED_PID
