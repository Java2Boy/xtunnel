#!/bin/bash
set -e

# 生成随机本地端口（避免冲突）
WS_PORT=$(shuf -i 10000-60000 -n 1)
METRICS_PORT=$(shuf -i 10000-60000 -n 1)

# 启动一个微型 HTTP 服务器用于健康检查（占用端口 8080）
echo "启动健康检查服务，监听端口 8080"
(
  while true; do
    echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK" | nc -l -p 8080 -q 1
  done
) &
HEALTH_PID=$!

# 启动 xtunnel
echo "启动 xtunnel 监听 ws://127.0.0.1:$WS_PORT"
if [ -z "$XTUNNEL_TOKEN" ]; then
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" &
else
    /usr/local/bin/xtunnel -l "ws://127.0.0.1:$WS_PORT" -token "$XTUNNEL_TOKEN" &
fi
XTUNNEL_PID=$!

sleep 2

# 启动 cloudflared
echo "启动 cloudflared 隧道 (IP版本: ${EDGE_IP_VERSION:-4})"
/usr/local/bin/cloudflared tunnel --edge-ip-version "${EDGE_IP_VERSION:-4}" \
    --protocol http2 \
    --url "http://127.0.0.1:$WS_PORT" \
    --metrics "0.0.0.0:$METRICS_PORT" &
CLOUDFLARED_PID=$!

# 等待任意子进程退出（便于平台自动重启）
wait $XTUNNEL_PID $CLOUDFLARED_PID $HEALTH_PID
