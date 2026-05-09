#!/bin/bash
# Alpine to Debian 13 Auto Install Script (Optimized & Safe Version)
# 功能：自动提取当前网络配置 → 静态IP安装Debian 13 → 防止重启断网
# 增强点：错误处理、依赖检查、输入校验、日志输出、安全加固

# ===================== 基础设置 =====================
set -euo pipefail
trap 'echo -e "\n脚本被中断！请检查日志排查问题。"; exit 1' SIGINT SIGTERM

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info() { echo -e "${GREEN}[INFO] $*${NC}"; }
warn() { echo -e "${YELLOW}[WARN] $*${NC}"; }
error() { echo -e "${RED}[ERROR] $*${NC}"; exit 1; }

# ===================== 1. 依赖安装 =====================
info "1/6 安装依赖组件..."
if ! apk info bash iproute2 grep gawk ipcalc curl wget >/dev/null 2>&1; then
    apk update >/dev/null 2>&1 || error "apk update 失败，请检查网络"
    apk add --no-cache bash iproute2 grep gawk ipcalc curl wget >/dev/null 2>&1 || error "依赖安装失败"
fi

# ===================== 2. Root权限检查 =====================
if [ "$(id -u)" -ne 0 ]; then
    error "必须使用 root 用户运行此脚本！"
fi

# ===================== 3. 交互式配置（增加输入校验） =====================
clear
echo "============================================="
echo "   Alpine → Debian 13 自动重装脚本（优化版）"
echo "============================================="
echo "⚠️  警告：此操作会重装系统，所有数据将被清空！"
echo "    请确认当前网络配置已稳定，否则重启后可能失联。"
echo ""

# SSH端口校验（必须是1-65535之间的数字）
if [ -z "${PORT:-}" ]; then
    while true; do
        read -p "请输入 SSH 端口 [默认 22]: " PORT
        PORT=${PORT:-22}
        if [[ "$PORT" =~ ^[0-9]+$ ]] && [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
            break
        fi
        warn "端口必须是 1-65535 之间的数字，请重新输入"
    done
fi

# 密码校验（禁止空密码，简单判断复杂度）
if [ -z "${PASSWORD:-}" ]; then
    while true; do
        read -p "请输入 Root 密码（避免特殊字符，建议至少8位）[默认 yiwan123]: " PASSWORD
        PASSWORD=${PASSWORD:-yiwan123}
        if [ -n "$PASSWORD" ] && [ ${#PASSWORD} -ge 6 ]; then
            break
        fi
        warn "密码不能为空，且建议至少6位，请重新输入"
    done
fi

echo ""
info "配置确认："
echo "  - SSH 端口: $PORT"
echo "  - Root 密码: 已设置（不显示明文）"
echo ""
warn "将在 5 秒后开始安装，按 Ctrl+C 可中止..."
sleep 5

# ===================== 4. 提取并验证网络配置（核心优化） =====================
info "2/6 提取当前网络配置..."

# 获取主网卡（处理多网卡场景）
MAIN_IFace=$(ip route show default | awk '{print $5}' | head -n1 | tr -d '[:space:]')
if [ -z "$MAIN_IFace" ]; then
    error "无法获取默认路由网卡，请手动指定网卡（例如 eth0）"
fi

# 获取IP地址（处理多IP场景）
MAIN_IP=$(ip -4 addr show "$MAIN_IFace" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1 | tr -d '[:space:]')
# 获取网关
MAIN_GATE=$(ip route show default | awk '/default/ {print $3}' | head -n1 | tr -d '[:space:]')
# 获取CIDR前缀
CIDR_NUM=$(ip -4 addr show "$MAIN_IFace" | awk '/inet / {print $2}' | cut -d/ -f2 | head -n1 | tr -d '[:space:]')

# 打印并验证配置
echo "----------------------------------------"
echo "网卡: $MAIN_IFace"
echo "IP地址: $MAIN_IP"
echo "网关: $MAIN_GATE"
echo "子网前缀: /$CIDR_NUM"
echo "----------------------------------------"

# 关键配置非空校验
if [ -z "$MAIN_IP" ] || [ -z "$MAIN_GATE" ] || [ -z "$CIDR_NUM" ]; then
    error "网络配置提取失败，请手动检查网卡和IP设置！"
fi

# IP地址格式校验（基础校验）
if ! [[ "$MAIN_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "提取的IP地址格式错误：$MAIN_IP"
fi
if ! [[ "$MAIN_GATE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    error "提取的网关格式错误：$MAIN_GATE"
fi
if ! [[ "$CIDR_NUM" =~ ^[0-9]+$ ]] || [ "$CIDR_NUM" -lt 0 ] || [ "$CIDR_NUM" -gt 32 ]; then
    error "提取的子网前缀错误：/$CIDR_NUM"
fi

info "网络配置验证通过"

# ===================== 5. 下载安装脚本（增加重试和校验） =====================
info "3/6 下载安装脚本..."
rm -f InstallNET.sh # 清理旧文件

# 增加下载重试
RETRY=3
for ((i=1; i<=RETRY; i++)); do
    if wget --no-check-certificate -qO InstallNET.sh 'https://raw.githubusercontent.com/leitbogioro/Tools/master/Linux_reinstall/InstallNET.sh'; then
        break
    fi
    warn "下载失败，第 $i/$RETRY 次重试..."
    sleep 2
done

if [ ! -f InstallNET.sh ] || [ ! -s InstallNET.sh ]; then
    error "安装脚本下载失败，请检查网络连接或访问GitHub是否正常"
fi

chmod a+x InstallNET.sh || error "脚本添加执行权限失败"
info "脚本下载完成"

# ===================== 6. 执行安装（关键参数加固） =====================
info "4/6 准备启动 Debian 13 安装程序..."
warn "⚠️  安装过程中会自动重启，请勿手动中断！"
sleep 3

# 关键参数修正：--ip-mask 应传入子网掩码（如 255.255.240.0），而不是CIDR前缀
# 自动将CIDR前缀转换为子网掩码
CIDR_MASK=$(ipcalc -m "$MAIN_IP"/"$CIDR_NUM" | awk '/Netmask/ {print $2}')
if [ -z "$CIDR_MASK" ]; then
    error "子网掩码转换失败，CIDR前缀 /$CIDR_NUM 无效"
fi
info "已自动将 /$CIDR_NUM 转换为子网掩码: $CIDR_MASK"

# 执行安装脚本（增加日志输出）
info "5/6 开始安装 Debian 13..."
echo "----------------------------------------"
echo "执行命令："
echo "bash InstallNET.sh -debian 13 -port $PORT -pwd ******** --ip-addr $MAIN_IP --ip-gate $MAIN_GATE --ip-mask $CIDR_MASK -swap 512 --cloudkernel 0 --bbr --motd"
echo "----------------------------------------"

# 启动安装（InstallNET 会自动处理重启，无需额外操作）
exec bash InstallNET.sh \
    -debian 13 \
    -port "${PORT}" \
    -pwd "${PASSWORD}" \
    -mirror "http://deb.debian.org/debian/" \
    --ip-addr "${MAIN_IP}" \
    --ip-gate "${MAIN_GATE}" \
    --ip-mask "${CIDR_MASK}" \
    -swap "512" \
    --cloudkernel "0" \
    --bbr \
    --motd

# 理论上不会执行到这里
error "安装脚本意外退出，请检查日志"
