# 使用 Alpine 作为基础镜像（体积小）
FROM alpine:latest

# 安装运行时依赖：bash, curl, screen, coreutils, netcat-openbsd, ca-certificates
RUN apk add --no-cache bash curl screen coreutils netcat-openbsd ca-certificates

# 创建工作目录
WORKDIR /app

# 复制入口脚本
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# 暴露健康检查端口（apply.build 要求）
EXPOSE 8080

# 容器启动命令
CMD ["/entrypoint.sh"]
