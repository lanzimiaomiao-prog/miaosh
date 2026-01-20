#!/bin/sh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

CONF_PATH="/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
LOG_PATH="/var/log/xray.log"

# 1. 强效清理函数 (检测并清空旧文件)
do_cleanup() {
    echo -e "${BLUE}正在检测并清理旧环境...${NC}"
    [ -f /etc/init.d/xray ] && rc-service xray stop 2>/dev/null && rc-update del xray default 2>/dev/null
    
    # 彻底删除相关路径和文件
    paths="/etc/xray /usr/local/share/xray /usr/local/bin/xray ${LOG_PATH} /etc/init.d/xray"
    for p in $paths; do
        if [ -e "$p" ]; then
            echo -e "${RED}删除已存在路径: $p${NC}"
            rm -rf "$p"
        fi
    done
}

# 卸载逻辑
if [ "$1" = "uninstall" ]; then
    do_cleanup
    echo -e "${GREEN}卸载完成，环境已清空。${NC}"
    exit 0
fi

# 执行清理动作
do_cleanup

# 2. 环境准备
echo -e "${BLUE}安装基础依赖...${NC}"
apk update
apk add curl openssl ca-certificates uuidgen tar gcompat

# 3. 下载 Xray
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)  X_ARCH="64" ;;
    aarch64) X_ARCH="arm64-v8a" ;;
    *) echo "不支持的架构"; exit 1 ;;
esac

echo -e "${BLUE}下载最新 Xray (musl)...${NC}"
NEW_VER=$(curl -s https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep 'tag_name' | cut -d\" -f4)
curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${NEW_VER}/Xray-linux-${X_ARCH}.zip"

mkdir -p /etc/xray /usr/local/share/xray
unzip -o /tmp/xray.zip -d /tmp/xray_tmp
mv /tmp/xray_tmp/xray ${XRAY_BIN}
mv /tmp/xray_tmp/*.dat /usr/local/share/xray/
chmod +x ${XRAY_BIN}
rm -rf /tmp/xray.zip /tmp/xray_tmp

# 4. 密钥生成 (保持安装过程输出，不使用 clear)
echo -e "${BLUE}生成 Reality 配置信息...${NC}"
X_KEYS=$(${XRAY_BIN} x25519)
UUID=$(${XRAY_BIN} uuid)

echo "--------------------------------"
echo "Xray 密钥对生成回显:"
echo "${X_KEYS}"
echo "--------------------------------"

# 提取 PrivateKey 和 PublicKey
PRIVATE_KEY=$(echo "${X_KEYS}" | grep "Private" | awk -F': ' '{print $2}' | tr -d '[:space:]')
PUBLIC_KEY=$(echo "${X_KEYS}" | grep "Public" | awk -F': ' '{print $2}' | tr -d '[:space:]')
SHORT_ID=$(openssl rand -hex 4)
DEST_DOMAIN="speed.cloudflare.com"

if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo -e "${RED}提取失败，尝试后备方案提取...${NC}"
    PRIVATE_KEY=$(echo "${X_KEYS}" | sed -n '1p' | awk '{print $NF}')
    PUBLIC_KEY=$(echo "${X_KEYS}" | sed -n '2p' | awk '{print $NF}')
fi

# 5. 写入配置 (指纹: random)
cat << CONF > ${CONF_PATH}
{
    "log": { "access": "${LOG_PATH}", "loglevel": "info" },
    "inbounds": [
        {
            "tag": "dokodemo-in",
            "port": 4431,
            "protocol": "dokodemo-door",
            "settings": { "address": "${DEST_DOMAIN}", "port": 443, "network": "tcp" },
            "sniffing": { "enabled": true, "destOverride": ["tls"], "routeOnly": true }
        },
        {
            "listen": "0.0.0.0",
            "port": 443,
            "protocol": "vless",
            "settings": {
                "clients": [{ "id": "${UUID}", "flow": "xtls-rprx-vision" }],
                "decryption": "none"
            },
            "streamSettings": {
                "network": "tcp",
                "security": "reality",
                "realitySettings": {
                    "dest": "127.0.0.1:4431",
                    "serverNames": ["${DEST_DOMAIN}"],
                    "privateKey": "${PRIVATE_KEY}",
                    "shortIds": ["${SHORT_ID}"],
                    "fingerprint": "random"
                }
            },
            "sniffing": { "enabled": true, "destOverride": ["http", "tls", "quic"], "routeOnly": true }
        }
    ],
    "outbounds": [
        { "protocol": "freedom", "settings": { "domainStrategy": "UseIPv4" }, "tag": "direct" },
        { "protocol": "blackhole", "tag": "block" }
    ],
    "routing": {
        "rules": [
            { "inboundTag": ["dokodemo-in"], "domain": ["${DEST_DOMAIN}"], "outboundTag": "direct" },
            { "inboundTag": ["dokodemo-in"], "outboundTag": "block" }
        ]
    }
}
CONF

# 6. 服务配置
cat << 'SERVICE' > /etc/init.d/xray
#!/sbin/openrc-run
description="Xray Reality Service"
command="/usr/local/bin/xray"
command_args="run -c /etc/xray/config.json"
command_background="yes"
pidfile="/run/${RC_SVCNAME}.pid"
depend() { need net; after firewall; }
SERVICE
chmod +x /etc/init.d/xray
rc-update add xray default
rc-service xray restart

# 7. 生成结果
sleep 2
PID=$(pidof xray)
IP=$(curl -s ifconfig.me)
COMMON_PARAM="encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST_DOMAIN}&fp=random&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none"

VLESS_LINK="vless://${UUID}@${IP}:443?${COMMON_PARAM}#Alpine_Reality"
CLASH_CONFIG="- {name: Alpine_Reality, type: vless, server: ${IP}, port: 443, uuid: ${UUID}, udp: true, tls: true, flow: xtls-rprx-vision, servername: ${DEST_DOMAIN}, network: tcp, reality-opts: {public-key: ${PUBLIC_KEY}, short-id: ${SHORT_ID}}, client-fingerprint: random}"

echo ""
echo -e "${GREEN}================ 安装与配置完成 ===================${NC}"
[ -n "$PID" ] && echo -e "运行状态: ${GREEN}运行中 (PID: $PID)${NC}" || echo -e "运行状态: ${RED}启动失败${NC}"
echo -e "配置文件: ${BLUE}${CONF_PATH}${NC}"
echo -e "客户端公钥: ${GREEN}${PUBLIC_KEY}${NC}"
echo "------------------------------------------------"
echo -e "${BLUE}[v2RayN / Nekobox 链接]:${NC}"
echo -e "${VLESS_LINK}"
echo ""
echo -e "${BLUE}[Shadowrocket 链接]:${NC}"
echo -e "${VLESS_LINK}&tfo=1"
echo ""
echo -e "${BLUE}[Clash Meta 节点]:${NC}"
echo -e "${CLASH_CONFIG}"
echo "------------------------------------------------"
echo -e "${GREEN}[实时日志查看]:${NC} tail -f ${LOG_PATH}"
echo -e "${RED}[卸载与清理]:${NC} sh $0 uninstall"
echo -e "${GREEN}=============================================${NC}"
