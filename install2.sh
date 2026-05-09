#!/bin/bash
# Alpine → Debian 13 标准迁移（自动网络+静态IP+安全版）
set -euo pipefail

# 1. 安装依赖
if [ ! -x /bin/bash ]; then
    apk update >/dev/null 2>&1
    apk add --no-cache bash iproute2 curl wget ipcalc >/dev/null 2>&1
fi

# 2. Root 校验
[ "$(id -u)" -ne 0 ] && { echo "必须用 root 执行"; exit 1; }

# 3. 交互配置
clear
echo "=== Alpine → Debian 13 标准版 ==="
read -p "SSH端口 [默认22]: " PORT
PORT=${PORT:-22}
read -p "Root密码 [默认 yiwan123]: " PWD
PWD=${PWD:-yiwan123}

# 4. 提取网络（自动适配当前IP/网关）
IFACE=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1 | tr -d ' ')
IP=$(ip -4 addr show $IFACE | awk '/inet /{print $2}' | cut -d/ -f1 | head -1)
GATE=$(ip route show default | awk '/default/{print $3}' | head -1)
CIDR=$(ip -4 addr show $IFACE | awk '/inet /{print $2}' | cut -d/ -f2 | head -1)
NETMASK=$(ipcalc -m $IP/$CIDR | awk '/Netmask/{print $2}')

# 5. 校验
[ -z "$IP" ] || [ -z "$GATE" ] || [ -z "$NETMASK" ] && { echo "网络提取失败"; exit 1; }
echo "网络：$IP $NETMASK 网关 $GATE"
sleep 3

# 6. 下载官方安装脚本
rm -f InstallNET.sh
wget -qO InstallNET.sh https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh
chmod +x InstallNET.sh

# 7. 执行重装（Debian 13 + 静态IP）
bash InstallNET.sh \
  -debian 13 \
  -port $PORT \
  -pwd $PWD \
  --ip-addr $IP \
  --ip-gate $GATE \
  --ip-mask $NETMASK \
  -swap 512 \
  --bbr --motd
