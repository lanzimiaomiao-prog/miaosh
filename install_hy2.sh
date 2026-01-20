#!/bin/sh

# 定义卸载函数
uninstall_hy2() {
    echo "正在卸载 Hysteria2..."
    rc-service hysteria stop 2>/dev/null
    rc-update del hysteria default 2>/dev/null
    rm -f /etc/init.d/hysteria
    rm -f /usr/local/bin/hysteria
    rm -rf /etc/hysteria
    rm -f /var/log/hysteria.log /var/log/hysteria.err
    echo "卸载完成！"
    exit 0
}

if [ "$1" = "uninstall" ]; then
    uninstall_hy2
fi

# 1. 环境准备
apk update
apk add curl ca-certificates openssl openrc

# 2. 识别架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)  BIN_ARCH="amd64" ;;
    aarch64) BIN_ARCH="arm64" ;;
    armv7l)  BIN_ARCH="arm" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

# 3. 版本检查与更新
REMOTE_VERSION=$(curl -sSL https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
LOCAL_VERSION=$(/usr/local/bin/hysteria -v 2>/dev/null | awk 'NR==1{print $3}')

if [ "$LOCAL_VERSION" = "$REMOTE_VERSION" ]; then
    echo "当前已是最新版本 ($LOCAL_VERSION)。"
else
    echo "正在下载/更新 Hysteria2 到 $REMOTE_VERSION..."
    curl -fSL "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-$BIN_ARCH" -o /usr/local/bin/hysteria.new
    rc-service hysteria stop 2>/dev/null
    mv /usr/local/bin/hysteria.new /usr/local/bin/hysteria
    chmod +x /usr/local/bin/hysteria
fi

# 4. 目录与证书初始化
mkdir -p /etc/hysteria
if [ ! -f "/etc/hysteria/server.crt" ]; then
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=www.bing.com" -days 3650
fi

# 5. 生成/读取 25位随机密码
if [ -f "/etc/hysteria/config.yaml" ]; then
    HY_PASSWORD=$(grep 'password:' /etc/hysteria/config.yaml | awk '{print $2}')
else
    HY_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 25)
fi

# 6. 写入服务端配置
cat << EOC > /etc/hysteria/config.yaml
listen: :443
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
auth:
  type: password
  password: $HY_PASSWORD
masquerade:
  type: proxy
  proxy:
    url: https://bing.com/
    rewriteHost: true
EOC

# 7. 配置 OpenRC 服务
cat << EOS > /etc/init.d/hysteria
#!/sbin/openrc-run
name="hysteria2"
description="Hysteria 2 Proxy Server"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/hysteria.log"
error_log="/var/log/hysteria.err"
depend() {
    need net
}
EOS
chmod +x /etc/init.d/hysteria

# 8. 设置启动与自启
rc-update add hysteria default 2>/dev/null
rc-service hysteria restart

# 9. 获取公网 IP
SERVER_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")

# 10. 输出结果
echo "------------------------------------------------"
echo "Hysteria2 安装/更新成功！"
echo "------------------------------------------------"
echo ""
echo "==== 1. v2rayN / Nekobox / Shadowrocket 分享链接 ===="
echo "hysteria2://$HY_PASSWORD@$SERVER_IP:443/?insecure=1&sni=www.bing.com#Alpine_Hy2"
echo ""
echo "==== 2. Clash Meta (Mihomo) 单行格式 ===="
echo "{ name: Alpine_Hy2, type: hysteria2, server: $SERVER_IP, port: 443, password: $HY_PASSWORD, sni: www.bing.com, skip-cert-verify: true }"
echo ""
echo "==== 3. Surge 5 节点格式 ===="
echo "Alpine_Hy2 = hysteria2, $SERVER_IP, 443, password=$HY_PASSWORD, sni=www.bing.com, skip-cert-verify=true"
echo ""
echo "------------------------------------------------"
echo "配置详情:"
echo "  密码: $HY_PASSWORD"
echo "  端口: 443 (UDP)"
echo "  伪装: https://bing.com/"
echo "------------------------------------------------"
echo "管理命令:"
echo "  更新/安装: sh install_hy2.sh"
echo "  卸载程序: sh install_hy2.sh uninstall"
echo "  查看日志: tail -f /var/log/hysteria.log"
echo "------------------------------------------------"
