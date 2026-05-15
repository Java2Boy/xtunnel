# 运行阶段
FROM alpine:3.19

RUN apk add --no-cache ca-certificates bash curl coreutils netcat-openbsd

# 下载 cloudflared
ADD https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 /usr/local/bin/cloudflared
RUN chmod +x /usr/local/bin/cloudflared

COPY --from=builder /build/xtunnel /usr/local/bin/xtunnel
RUN chmod +x /usr/local/bin/xtunnel

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENV XTUNNEL_TOKEN=""
ENV EDGE_IP_VERSION="4"

# 占位端口，apply.build 要求暴露至少一个端口
EXPOSE 8080

CMD ["/entrypoint.sh"]
