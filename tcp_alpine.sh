#!/bin/sh

# 1. 权限检查
if [ "$(id -u)" -ne 0 ]; then
   echo "Error: Please run as root!"
   exit 1
fi

# 2. 交互输入
echo "请输入 TCP 最大发送缓存 (MB, 支持小数):"
read MB_INPUT

# 3. 换算 (使用 Alpine 自带的 awk)
MAX_WMEM=$(echo "$MB_INPUT" | awk '{printf "%.0f", $1 * 1048576}')

# 验证换算是否成功
if [ -z "$MAX_WMEM" ] || [ "$MAX_WMEM" -le 0 ]; then
    echo "错误: 输入数值无效"
    exit 1
fi

# 4. 写入配置 (使用 /etc/sysctl.conf)
# 先清理旧的同名参数防止冲突
sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_wmem/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_slow_start_after_idle/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_notsent_lowat/d' /etc/sysctl.conf
sed -i '/net.ipv4.tcp_fastopen/d' /etc/sysctl.conf

cat << EOF >> /etc/sysctl.conf
net.ipv4.tcp_congestion_control=bbr
net.core.default_qdisc=fq
net.ipv4.tcp_wmem = 4096 131072 $MAX_WMEM
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_notsent_lowat=131072
net.ipv4.tcp_fastopen=0
EOF

# 5. 生效并显示结果
sysctl -p > /dev/null
echo "---------------------------------------"
echo "优化完成！"
echo "已设置 tcp_wmem 为: $MAX_WMEM 字节"
sysctl net.ipv4.tcp_congestion_control net.core.default_qdisc net.ipv4.tcp_wmem

# 6. 最后输出指定的命令
echo "---------------------------------------"
echo "sh tcp_alpine.sh"