#!/bin/sh

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

CONF_PATH="/etc/xray/config.json"
XRAY_BIN="/usr/local/bin/xray"
LOG_PATH="/var/log/xray.log"

# 获取架构
ARCH=$(uname -m)
case ${ARCH} in
    x86_64)  X_ARCH="64" ;;
    aarch64) X_ARCH="arm64-v8a" ;;
    *) echo "不支持的架构"; exit 1 ;;
esac

# 1. 强效清理函数
do_cleanup() {
    echo -e "${BLUE}正在清理旧环境...${NC}"
    [ -f /etc/init.d/xray ] && rc-service xray stop 2>/dev/null && rc-update del xray default 2>/dev/null
    rm -rf /etc/xray /usr/local/share/xray ${XRAY_BIN} ${LOG_PATH} /etc/init.d/xray
}

# 2. 下载并解压 Xray (增强版)
download_xray() {
    echo -e "${BLUE}检查必要依赖...${NC}"
    apk add curl unzip openssl ca-certificates uuidgen tar gcompat > /dev/null 2>&1

    echo -e "${BLUE}正在获取最新版本号...${NC}"
    # 使用更严谨的正则匹配版本号
    NEW_VER=$(curl -sL https://api.github.com/repos/XTLS/Xray-core/releases/latest | grep '"tag_name":' | head -n 1 | cut -d'"' -f4)
    
    # 容错处理：如果获取失败，使用手动指定的稳定版
    if [ -z "$NEW_VER" ] || [ "$(echo $NEW_VER | cut -c1)" != "v" ]; then
        echo -e "${RED}GitHub API 获取失败，使用预设版本 v24.12.31${NC}"
        NEW_VER="v24.12.31"
    fi
    
    echo -e "${GREEN}目标安装版本: ${NEW_VER}${NC}"
    
    # 尝试下载
    DOWNLOAD_URL="https://github.com/XTLS/Xray-core/releases/download/${NEW_VER}/Xray-linux-${X_ARCH}.zip"
    curl -L -o /tmp/xray.zip "${DOWNLOAD_URL}"
    
    # 严格检查下载文件大小 (小于 10KB 肯定不对)
    FILE_SIZE=$(wc -c < "/tmp/xray.zip")
    if [ "$FILE_SIZE" -lt 10240 ]; then
        echo -e "${RED}下载失败：文件损坏或网络被拦截。请检查与 GitHub 的连接。${NC}"
        exit 1
    fi

    mkdir -p /etc/xray /usr/local/share/xray /tmp/xray_tmp
    unzip -o /tmp/xray.zip -d /tmp/xray_tmp
    
    if [ ! -f "/tmp/xray_tmp/xray" ]; then
        echo -e "${RED}解压失败：压缩包内未找到二进制文件！${NC}"
        exit 1
    fi

    mv -f /tmp/xray_tmp/xray ${XRAY_BIN}
    mv -f /tmp/xray_tmp/*.dat /usr/local/share/xray/
    chmod +x ${XRAY_BIN}
    rm -rf /tmp/xray.zip /tmp/xray_tmp
}

# 3. 更新功能
do_update() {
    if [ ! -f "${XRAY_BIN}" ]; then
        echo -e "${RED}未检测到已安装的 Xray。${NC}"
        exit 1
    fi
    echo -e "${BLUE}开始保留配置更新...${NC}"
    rc-service xray stop
    download_xray
    rc-service xray start
    echo -e "${GREEN}Xray 二进制文件已更新。${NC}"
    exit 0
}

# 指令处理
if [ "$1" = "uninstall" ]; then
    do_cleanup
    echo -e "${GREEN}卸载完成。${NC}"
    exit 0
fi

if [ "$1" = "update" ]; then
    do_update
fi

# 默认覆盖安装流程
do_cleanup
download_xray

# 4. 密钥生成 (增加成功检查)
echo -e "${BLUE}生成 Reality 密钥对...${NC}"
X_KEYS=$(${XRAY_BIN} x25519)
UUID=$(${XRAY_BIN} uuid)

PRIVATE_KEY=$(echo "${X_KEYS}" | grep "Private key" | awk '{print $NF}')
PUBLIC_KEY=$(echo "${X_KEYS}" | grep "Public key" | awk '{print $NF}')
SHORT_ID=$(openssl rand -hex 4)
DEST_DOMAIN="speed.cloudflare.com"

# 如果密钥获取失败则报错
if [ -z "$PRIVATE_KEY" ]; then
    echo -e "${RED}错误：无法通过 Xray 生成密钥。${NC}"
    exit 1
fi

# 5. 写入配置
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

# 7. 输出
sleep 2
PID=$(pidof xray)
IP=$(curl -s ifconfig.me)
COMMON_PARAM="encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DEST_DOMAIN}&fp=random&pbk=${PUBLIC_KEY}&sid=${SHORT_ID}&type=tcp&headerType=none"

echo ""
echo -e "${GREEN}================ 安装完成 ===================${NC}"
[ -n "$PID" ] && echo -e "运行状态: ${GREEN}运行中 (PID: $PID)${NC}" || echo -e "运行状态: ${RED}启动失败${NC}"
echo -e "配置文件路径: ${BLUE}${CONF_PATH}${NC}"
echo -e "客户端公钥: ${GREEN}${PUBLIC_KEY}${NC}"
echo "------------------------------------------------"
echo -e "${BLUE}[v2RayN / Nekobox 链接]:${NC}"
echo -e "vless://${UUID}@${IP}:443?${COMMON_PARAM}#Alpine_Reality"
echo ""
echo -e "${BLUE}[实时日志]:${NC} tail -f ${LOG_PATH}"
echo -e "${GREEN}[更新命令]:${NC} sh $0 update"
echo -e "${RED}[卸载指令]:${NC} sh $0 uninstall"
echo -e "${GREEN}=============================================${NC}"
