#!/bin/sh

# 定义颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# 卸载函数
uninstall_hy2() {
    echo "正在卸载 Hysteria2..."
    rc-service hysteria stop 2>/dev/null
    rc-update del hysteria default 2>/dev/null
    rm -f /etc/init.d/hysteria /usr/local/bin/hysteria
    rm -rf /etc/hysteria
    rm -f /var/log/hysteria.log /var/log/hysteria.err
    echo "卸载完成！"
    exit 0
}

# 检查参数
ACTION=$1

if [ "$ACTION" = "uninstall" ]; then
    uninstall_hy2
fi

# 1. 环境准备
apk update && apk add curl ca-certificates openssl openrc

# 2. 识别架构
ARCH=$(uname -m)
case $ARCH in
    x86_64)  BIN_ARCH="amd64" ;;
    aarch64) BIN_ARCH="arm64" ;;
    armv7l)  BIN_ARCH="arm" ;;
    *) echo "不支持的架构: $ARCH"; exit 1 ;;
esac

# 3. 版本检查与程序更新
REMOTE_VERSION=$(curl -sSL https://api.github.com/repos/apernet/hysteria/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
echo "正在获取 Hysteria2 最新版本: $REMOTE_VERSION"

curl -fSL "https://github.com/apernet/hysteria/releases/latest/download/hysteria-linux-$BIN_ARCH" -o /usr/local/bin/hysteria.new
if [ $? -eq 0 ]; then
    rc-service hysteria stop 2>/dev/null
    mv /usr/local/bin/hysteria.new /usr/local/bin/hysteria
    chmod +x /usr/local/bin/hysteria
else
    echo "下载失败"; exit 1
fi

# 4. 配置文件处理逻辑
mkdir -p /etc/hysteria

if [ "$ACTION" = "update" ] && [ -f "/etc/hysteria/config.yaml" ]; then
    echo -e "${GREEN}检测到 update 命令，正在保留原配置更新...${NC}"
    HY_PASSWORD=$(grep 'password:' /etc/hysteria/config.yaml | awk '{print $2}')
else
    echo -e "${RED}正在执行覆盖安装/初始化...${NC}"
    # 生成新证书
    openssl req -x509 -nodes -newkey rsa:2048 -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt -subj "/CN=www.bing.com" -days 3650
    # 生成新密码
    HY_PASSWORD=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 25)
    # 写入新配置
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
fi

# 5. 服务与启动
cat << EOS > /etc/init.d/hysteria
#!/sbin/openrc-run
name="hysteria2"
command="/usr/local/bin/hysteria"
command_args="server -c /etc/hysteria/config.yaml"
command_background=true
pidfile="/run/\${RC_SVCNAME}.pid"
output_log="/var/log/hysteria.log"
error_log="/var/log/hysteria.err"
depend() { need net; }
EOS
chmod +x /etc/init.d/hysteria
rc-update add hysteria default 2>/dev/null
rc-service hysteria restart

# 6. 输出结果
SERVER_IP=$(curl -s https://api.ipify.org || echo "YOUR_SERVER_IP")
echo "------------------------------------------------"
echo -e "${GREEN}Hysteria2 操作成功！${NC}"
echo "------------------------------------------------"
echo "==== 1. 通用分享链接 (v2rayN/Nekobox) ===="
echo "hysteria2://$HY_PASSWORD@$SERVER_IP:443/?insecure=1&sni=www.bing.com#Alpine_Hy2"
echo ""
echo "==== 2. Clash Meta (Mihomo) 单行格式 ===="
echo "{ name: Alpine_Hy2, type: hysteria2, server: $SERVER_IP, port: 443, password: $HY_PASSWORD, sni: www.bing.com, skip-cert-verify: true }"
echo ""
echo "==== 3. Surge 5 节点格式 ===="
echo "Alpine_Hy2 = hysteria2, $SERVER_IP, 443, password=$HY_PASSWORD, sni=www.bing.com, skip-cert-verify=true"
echo "------------------------------------------------"
echo "管理命令:"
echo "  覆盖安装: sh install_hy2.sh"
echo "  保留配置更新: sh install_hy2.sh update"
echo "  卸载程序: sh install_hy2.sh uninstall"
echo "------------------------------------------------"
