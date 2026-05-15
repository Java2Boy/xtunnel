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
RUN apk add --no-cache ca-certificates
COPY --from=builder /app/xtunnel /usr/local/bin/xtunnel
ENTRYPOINT ["/usr/local/bin/xtunnel"]
