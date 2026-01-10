#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# 版本信息
SCRIPT_VERSION="2.0.0"
INSTALL_DIR="/usr/local/frp"
CONFIG_DIR="/etc/frp"
LOG_DIR="/var/log/frp"
SERVICE_NAME="frps"
BINARY_NAME="frps"

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误：必须使用root权限运行此脚本！${NC}" >&2
        exit 1
    fi
}

# 显示横幅
show_banner() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                   Frp 服务端安装脚本 v${SCRIPT_VERSION}            ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                   支持自动架构检测与卸载功能                ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                     https://gofrp.org/                      ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# 识别系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_NAME=$NAME
    elif [ -f /etc/centos-release ]; then
        OS="centos"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/centos-release | head -1)
        OS_NAME="CentOS"
    elif [ -f /etc/redhat-release ]; then
        OS="rhel"
        OS_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
        OS_NAME="RedHat"
    else
        OS=$(uname -s | tr '[:upper:]' '[:lower:]')
        OS_VERSION=$(uname -r)
        OS_NAME=$OS
    fi
    
    echo -e "${GREEN}[系统信息]${NC} ${OS_NAME} ${OS_VERSION} (${OS})"
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64|x86-64|amd64)
            FRP_ARCH="amd64"
            ARCH_NAME="64位 x86"
            ;;
        aarch64|arm64)
            FRP_ARCH="arm64"
            ARCH_NAME="64位 ARM"
            ;;
        armv7l|armv8l)
            FRP_ARCH="arm"
            ARCH_NAME="32位 ARM"
            ;;
        armv6l|armv5l)
            FRP_ARCH="arm"
            ARCH_NAME="ARMv6/ARMv5"
            ;;
        i386|i686)
            FRP_ARCH="386"
            ARCH_NAME="32位 x86"
            ;;
        mips)
            FRP_ARCH="mips"
            ARCH_NAME="MIPS"
            ;;
        mips64)
            FRP_ARCH="mips64"
            ARCH_NAME="64位 MIPS"
            ;;
        mips64el)
            FRP_ARCH="mips64le"
            ARCH_NAME="64位 MIPS (小端)"
            ;;
        mipsel)
            FRP_ARCH="mipsle"
            ARCH_NAME="MIPS (小端)"
            ;;
        s390x)
            FRP_ARCH="s390x"
            ARCH_NAME="IBM S/390"
            ;;
        ppc64le)
            FRP_ARCH="ppc64le"
            ARCH_NAME="PowerPC 64位 (小端)"
            ;;
        riscv64)
            FRP_ARCH="riscv64"
            ARCH_NAME="RISC-V 64位"
            ;;
        *)
            echo -e "${RED}不支持的架构: $ARCH${NC}"
            echo -e "${YELLOW}尝试使用通用架构...${NC}"
            FRP_ARCH="amd64"  # 默认尝试amd64
            ARCH_NAME="未知 (使用默认)"
            ;;
    esac
    echo -e "${GREEN}[系统架构]${NC} $ARCH ($ARCH_NAME) -> frp架构: $FRP_ARCH"
}

# 检查frp是否已安装
check_installed() {
    if [ -f /usr/local/bin/$BINARY_NAME ] || [ -f /etc/systemd/system/$SERVICE_NAME.service ]; then
        return 0
    else
        return 1
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "\n${YELLOW}[1/7]${NC} 正在安装依赖..."
    
    case $OS in
        debian|ubuntu|raspbian|deepin)
            apt-get update
            apt-get install -y wget tar curl openssl
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y wget tar curl openssl
            elif command -v yum >/dev/null 2>&1; then
                yum install -y wget tar curl openssl
            fi
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm wget tar curl openssl
            ;;
        alpine)
            apk add wget tar curl openssl
            ;;
        opensuse*|sles)
            zypper install -y wget tar curl openssl
            ;;
        *)
            echo -e "${YELLOW}未知系统，尝试安装wget、tar、curl和openssl...${NC}"
            if command -v apt-get >/dev/null 2>&1; then
                apt-get install -y wget tar curl openssl
            elif command -v yum >/dev/null 2>&1; then
                yum install -y wget tar curl openssl
            elif command -v pacman >/dev/null 2>&1; then
                pacman -Syu --noconfirm wget tar curl openssl
            else
                echo -e "${RED}无法自动安装依赖，请手动安装: wget tar curl openssl${NC}"
                read -p "按回车键继续（可能会失败）..." -n1
            fi
            ;;
    esac
    echo -e "${GREEN}✓ 依赖安装完成${NC}"
}

# 下载并安装frp
install_frp() {
    echo -e "\n${YELLOW}[2/7]${NC} 正在下载并安装frp..."
    
    # 获取最新版本
    if [ -z "$FRP_VERSION" ]; then
        echo -e "${BLUE}正在获取最新版本...${NC}"
        FRP_VERSION=$(curl -s https://api.github.com/repos/fatedier/frp/releases/latest | grep -o '"tag_name": "[^"]*' | grep -o '[^v]*$' || echo "0.43.0")
    fi
    
    FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
    
    echo -e "${BLUE}下载版本: v${FRP_VERSION}${NC}"
    echo -e "${BLUE}系统架构: ${FRP_ARCH}${NC}"
    
    # 创建目录
    mkdir -p $INSTALL_DIR $CONFIG_DIR $LOG_DIR
    
    # 下载frp
    echo -e "${BLUE}正在下载 frp v${FRP_VERSION}...${NC}"
    if wget  /tmp/frp.tar.gz "$FRP_URL"; then
        echo -e "${GREEN}✓ 下载成功${NC}"
    else
        echo -e "${RED}✗ 主下载源失败，尝试备用源...${NC}"
        
        # 备用源
        FRP_URL="https://ghproxy.com/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
        if ! wget --show-progress -q -O /tmp/frp.tar.gz "$FRP_URL"; then
            echo -e "${RED}✗ 备用下载也失败，请检查网络和架构支持！${NC}"
            echo -e "${YELLOW}手动下载链接:${NC}"
            echo "https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
            exit 1
        fi
    fi
    
    # 备份旧版本
    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A $INSTALL_DIR 2>/dev/null)" ]; then
        BACKUP_DIR="$INSTALL_DIR.backup.$(date +%Y%m%d%H%M%S)"
        echo -e "${YELLOW}备份旧版本到: $BACKUP_DIR${NC}"
        cp -r $INSTALL_DIR $BACKUP_DIR
    fi
    
    # 解压文件
    echo -e "${BLUE}正在解压文件...${NC}"
    tar -zxvf /tmp/frp.tar.gz -C $INSTALL_DIR --strip-components=1
    
    # 复制二进制文件
    if [ -f $INSTALL_DIR/$BINARY_NAME ]; then
        cp $INSTALL_DIR/$BINARY_NAME /usr/local/bin/
        chmod +x /usr/local/bin/$BINARY_NAME
        echo -e "${GREEN}✓ $BINARY_NAME 安装完成${NC}"
    else
        echo -e "${RED}✗ $BINARY_NAME 文件不存在，解压可能失败！${NC}"
        exit 1
    fi
    
    # 清理临时文件
    rm -f /tmp/frp.tar.gz
}

# 创建配置文件
create_config() {
    echo -e "\n${YELLOW}[3/7]${NC} 正在创建配置文件..."
    
    # 生成随机token
    RANDOM_TOKEN=$(openssl rand -hex 16 2>/dev/null || echo "frp_$(date +%s%N)")
    DASHBOARD_PWD=$(openssl rand -hex 8 2>/dev/null || echo "admin$(date +%s)")
    
    # 获取IP地址
    get_ip() {
        local ip
        ip=$(curl -s -4 icanhazip.com 2>/dev/null || curl -s -4 ifconfig.me 2>/dev/null || curl -s -4 ipinfo.io/ip 2>/dev/null || echo "0.0.0.0")
        echo "$ip"
    }
    
    SERVER_IP=$(get_ip)
    
    # 创建默认配置文件
    cat > $CONFIG_DIR/frps.ini << EOF
[common]
# 服务监听端口
bind_port = 7000
bind_addr = 0.0.0.0
kcp_bind_port = 7000

# 认证配置
token = $RANDOM_TOKEN
authentication_method = token

# 管理面板
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = $DASHBOARD_PWD
enable_prometheus = true

# 日志配置
log_file = $LOG_DIR/frps.log
log_level = info
log_max_days = 7

# 高级配置
max_pool_count = 5
max_ports_per_client = 0
tls_only = false
EOF
    
    # 创建额外的配置示例
    cat > $CONFIG_DIR/frps_full.ini.example << EOF
# 完整配置示例
[common]
# 基本绑定端口
bind_port = 7000
bind_addr = 0.0.0.0
kcp_bind_port = 7000
quic_bind_port = 7000

# 认证和安全
token = your_token_here
authentication_method = token
authenticate_heartbeats = false
authenticate_new_work_conns = false

# TLS配置
tls_enable = true
tls_cert_file =
tls_key_file =
tls_trusted_ca_file =

# 管理面板
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin
enable_prometheus = true
dashboard_tls_mode = false
dashboard_tls_cert_file =
dashboard_tls_key_file =

# 日志配置
log_file = $LOG_DIR/frps.log
log_level = info
log_max_days = 3
disable_log_color = false

# 高级选项
#allow_ports = 2000-3000,3001,3003,4000-50000
max_pool_count = 5
max_ports_per_client = 0
tcp_mux = true
proxy_protocol_version = v2
EOF
    
    echo -e "${GREEN}✓ 配置文件已创建${NC}"
    echo -e "${BLUE}配置文件位置:${NC} $CONFIG_DIR/frps.ini"
    echo -e "${BLUE}示例配置:${NC} $CONFIG_DIR/frps_full.ini.example"
}

# 创建systemd服务
create_service() {
    echo -e "\n${YELLOW}[4/7]${NC} 正在创建systemd服务..."
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/$SERVICE_NAME.service << EOF
[Unit]
Description=Frp Server Service
Documentation=https://gofrp.org/docs/
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=/usr/local/bin/$BINARY_NAME -c $CONFIG_DIR/frps.ini
ExecReload=/usr/local/bin/$BINARY_NAME reload -c $CONFIG_DIR/frps.ini
LimitNOFILE=1048576
LimitNPROC=512
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$LOG_DIR
NoNewPrivileges=true
StandardOutput=journal
StandardError=journal
SyslogIdentifier=$SERVICE_NAME

# 安全加固
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ProtectSystem=strict
ReadWriteDirectories=$LOG_DIR
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=yes
RestrictRealtime=yes
SystemCallFilter=@system-service
SystemCallErrorNumber=EPERM
MemoryDenyWriteExecute=yes
LockPersonality=yes
RestrictSUIDSGID=yes
PrivateMounts=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置日志目录权限
    chown -R nobody:nogroup $LOG_DIR
    chmod 755 $LOG_DIR
    
    # 重载systemd
    systemctl daemon-reload
    systemctl enable $SERVICE_NAME
    
    echo -e "${GREEN}✓ systemd服务已创建${NC}"
}

# 创建管理脚本
create_management_script() {
    echo -e "\n${YELLOW}[5/7]${NC} 正在创建管理脚本..."
    
    cat > /usr/local/bin/frp << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# 检测活动服务
detect_active_service() {
    if systemctl is-active --quiet frps 2>/dev/null; then
        SERVICE_NAME="frps"
        BINARY_NAME="frps"
        CONFIG_FILE="/etc/frp/frps.ini"
    elif systemctl is-active --quiet frpc 2>/dev/null; then
        SERVICE_NAME="frpc"
        BINARY_NAME="frpc"
        CONFIG_FILE="/etc/frp/frpc.ini"
    elif [ -f /etc/systemd/system/frps.service ]; then
        SERVICE_NAME="frps"
        BINARY_NAME="frps"
        CONFIG_FILE="/etc/frp/frps.ini"
    elif [ -f /etc/systemd/system/frpc.service ]; then
        SERVICE_NAME="frpc"
        BINARY_NAME="frpc"
        CONFIG_FILE="/etc/frp/frpc.ini"
    else
        echo -e "${RED}未找到frp服务${NC}"
        echo -e "${YELLOW}请先安装frp服务端或客户端${NC}"
        exit 1
    fi
}

# 显示状态
show_status() {
    clear
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                     Frp 服务管理                       ${BLUE}║${NC}"
    echo -e "${BLUE}║${NC}${BOLD}                    版本 2.0.0                        ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    detect_active_service
    
    # 获取服务状态
    SERVICE_STATUS=$(systemctl is-active $SERVICE_NAME 2>/dev/null || echo "inactive")
    SERVICE_ENABLED=$(systemctl is-enabled $SERVICE_NAME 2>/dev/null || echo "unknown")
    
    # 状态颜色
    if [ "$SERVICE_STATUS" = "active" ]; then
        STATUS_COLOR="${GREEN}"
    elif [ "$SERVICE_STATUS" = "failed" ]; then
        STATUS_COLOR="${RED}"
    else
        STATUS_COLOR="${YELLOW}"
    fi
    
    if [ "$SERVICE_ENABLED" = "enabled" ]; then
        ENABLED_COLOR="${GREEN}"
    else
        ENABLED_COLOR="${YELLOW}"
    fi
    
    # 显示服务信息
    echo -e "${CYAN}┌────────────────── 服务信息 ──────────────────${NC}"
    echo -e "${CYAN}│${NC} 服务名称: ${BOLD}$SERVICE_NAME${NC}"
    echo -e "${CYAN}│${NC} 运行状态: ${STATUS_COLOR}$SERVICE_STATUS${NC}"
    echo -e "${CYAN}│${NC} 开机自启: ${ENABLED_COLOR}$SERVICE_ENABLED${NC}"
    echo -e "${CYAN}│${NC} 配置文件: ${YELLOW}$CONFIG_FILE${NC}"
    echo -e "${CYAN}│${NC} 执行文件: ${YELLOW}/usr/local/bin/$BINARY_NAME${NC}"
    echo -e "${CYAN}└───────────────────────────────────────────────${NC}"
    echo ""
}

# 显示菜单
show_menu() {
    echo -e "${BLUE}════════════════════ 菜单 ═════════════════════${NC}"
    echo -e "1. ${GREEN}启动服务${NC}"
    echo -e "2. ${RED}停止服务${NC}"
    echo -e "3. ${YELLOW}重启服务${NC}"
    echo -e "4. ${PURPLE}重载配置${NC}"
    echo -e "5. ${CYAN}查看状态${NC}"
    echo -e "6. ${BLUE}查看日志${NC}"
    echo -e "7. ${GREEN}编辑配置${NC}"
    echo -e "8. ${YELLOW}配置文件${NC}"
    echo -e "9. ${PURPLE}服务管理${NC}"
    echo -e "0. ${RED}退出${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
    
    # 添加快捷命令提示
    echo -e "\n${YELLOW}快捷命令:${NC}"
    echo -e "  frp start    - 启动服务"
    echo -e "  frp stop     - 停止服务"
    echo -e "  frp restart  - 重启服务"
    echo -e "  frp status   - 查看状态"
    echo -e "  frp reload   - 重载配置"
    echo -e "  frp log      - 查看日志"
    echo -e "  frp edit     - 编辑配置"
    echo -e "  frp uninstall - 卸载服务"
    echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
}

# 查看日志
view_log() {
    echo -e "\n${YELLOW}选择日志查看方式:${NC}"
    echo -e "1. 实时查看日志 (tail -f)"
    echo -e "2. 查看最近100行"
    echo -e "3. 查看完整日志"
    echo -e "4. 查看错误日志"
    echo -e "5. 返回"
    
    read -p "请选择 (1-5): " log_choice
    
    case $log_choice in
        1)
            journalctl -u $SERVICE_NAME -f
            ;;
        2)
            journalctl -u $SERVICE_NAME -n 100
            ;;
        3)
            journalctl -u $SERVICE_NAME
            ;;
        4)
            journalctl -u $SERVICE_NAME -p err
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 配置文件操作
config_operations() {
    echo -e "\n${YELLOW}配置文件操作:${NC}"
    echo -e "1. 查看当前配置"
    echo -e "2. 备份当前配置"
    echo -e "3. 恢复备份配置"
    echo -e "4. 检查配置语法"
    echo -e "5. 返回"
    
    read -p "请选择 (1-5): " config_choice
    
    case $config_choice in
        1)
            echo -e "\n${CYAN}当前配置文件内容:${NC}"
            echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
            cat $CONFIG_FILE
            echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
            ;;
        2)
            BACKUP_FILE="$CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"
            cp $CONFIG_FILE $BACKUP_FILE
            echo -e "${GREEN}✓ 配置已备份到: $BACKUP_FILE${NC}"
            ;;
        3)
            echo -e "${YELLOW}可用的备份文件:${NC}"
            ls -la $CONFIG_FILE.backup.* 2>/dev/null || echo "暂无备份文件"
            read -p "输入要恢复的备份文件: " backup_file
            if [ -f "$backup_file" ]; then
                cp $backup_file $CONFIG_FILE
                echo -e "${GREEN}✓ 配置已恢复${NC}"
            else
                echo -e "${RED}文件不存在${NC}"
            fi
            ;;
        4)
            echo -e "${YELLOW}检查配置语法...${NC}"
            if /usr/local/bin/$BINARY_NAME verify -c $CONFIG_FILE; then
                echo -e "${GREEN}✓ 配置语法正确${NC}"
            else
                echo -e "${RED}✗ 配置语法错误${NC}"
            fi
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 服务管理
service_operations() {
    echo -e "\n${YELLOW}服务管理:${NC}"
    echo -e "1. 启用开机自启"
    echo -e "2. 禁用开机自启"
    echo -e "3. 重载systemd配置"
    echo -e "4. 查看服务详情"
    echo -e "5. 返回"
    
    read -p "请选择 (1-5): " service_choice
    
    case $service_choice in
        1)
            systemctl enable $SERVICE_NAME
            echo -e "${GREEN}✓ 已启用开机自启${NC}"
            ;;
        2)
            systemctl disable $SERVICE_NAME
            echo -e "${YELLOW}已禁用开机自启${NC}"
            ;;
        3)
            systemctl daemon-reload
            echo -e "${GREEN}✓ systemd配置已重载${NC}"
            ;;
        4)
            systemctl status $SERVICE_NAME --no-pager -l
            ;;
        5)
            return
            ;;
        *)
            echo -e "${RED}无效选择${NC}"
            ;;
    esac
}

# 主函数
main_menu() {
    while true; do
        show_status
        show_menu
        read -p "请选择操作 (0-9): " choice
        
        case $choice in
            1)
                echo -e "\n${GREEN}启动 $SERVICE_NAME...${NC}"
                systemctl start $SERVICE_NAME
                sleep 2
                systemctl status $SERVICE_NAME --no-pager
                ;;
            2)
                echo -e "\n${RED}停止 $SERVICE_NAME...${NC}"
                systemctl stop $SERVICE_NAME
                sleep 1
                systemctl status $SERVICE_NAME --no-pager
                ;;
            3)
                echo -e "\n${YELLOW}重启 $SERVICE_NAME...${NC}"
                systemctl restart $SERVICE_NAME
                sleep 2
                systemctl status $SERVICE_NAME --no-pager
                ;;
            4)
                echo -e "\n${PURPLE}重载 $SERVICE_NAME 配置...${NC}"
                systemctl reload $SERVICE_NAME
                sleep 1
                systemctl status $SERVICE_NAME --no-pager
                ;;
            5)
                echo -e "\n${CYAN}查看 $SERVICE_NAME 状态...${NC}"
                systemctl status $SERVICE_NAME --no-pager -l
                ;;
            6)
                view_log
                ;;
            7)
                ${EDITOR:-vi} $CONFIG_FILE
                echo -e "\n${YELLOW}配置已修改，需要重启服务使更改生效${NC}"
                ;;
            8)
                config_operations
                ;;
            9)
                service_operations
                ;;
            0)
                echo -e "\n${BLUE}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}无效选择，请重新输入${NC}"
                ;;
        esac
        
        if [ "$choice" != "0" ]; then
            echo ""
            read -p "按回车键返回主菜单..."
        fi
    done
}

# 命令行参数处理
case "$1" in
    start)
        detect_active_service
        systemctl start $SERVICE_NAME
        systemctl status $SERVICE_NAME --no-pager
        ;;
    stop)
        detect_active_service
        systemctl stop $SERVICE_NAME
        systemctl status $SERVICE_NAME --no-pager
        ;;
    restart)
        detect_active_service
        systemctl restart $SERVICE_NAME
        systemctl status $SERVICE_NAME --no-pager
        ;;
    status)
        detect_active_service
        systemctl status $SERVICE_NAME --no-pager -l
        ;;
    reload)
        detect_active_service
        systemctl reload $SERVICE_NAME
        systemctl status $SERVICE_NAME --no-pager
        ;;
    log)
        detect_active_service
        journalctl -u $SERVICE_NAME -f
        ;;
    edit)
        detect_active_service
        ${EDITOR:-vi} $CONFIG_FILE
        ;;
    enable)
        detect_active_service
        systemctl enable $SERVICE_NAME
        echo -e "${GREEN}✓ 已启用开机自启${NC}"
        ;;
    disable)
        detect_active_service
        systemctl disable $SERVICE_NAME
        echo -e "${YELLOW}已禁用开机自启${NC}"
        ;;
    config)
        detect_active_service
        echo -e "${CYAN}配置文件路径:${NC} $CONFIG_FILE"
        echo -e "${CYAN}配置文件内容:${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        cat $CONFIG_FILE
        echo -e "${BLUE}═══════════════════════════════════════════════${NC}"
        ;;
    uninstall)
        detect_active_service
        echo -e "${RED}⚠ 警告：您将要卸载 $SERVICE_NAME${NC}"
        read -p "确定要卸载吗？(y/N): " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}正在卸载 $SERVICE_NAME...${NC}"
            systemctl stop $SERVICE_NAME
            systemctl disable $SERVICE_NAME
            rm -f /etc/systemd/system/$SERVICE_NAME.service
            rm -f /usr/local/bin/$BINARY_NAME
            systemctl daemon-reload
            
            # 询问是否删除配置和日志
            read -p "是否删除配置文件？(y/N): " del_conf
            if [[ $del_conf =~ ^[Yy]$ ]]; then
                rm -rf $CONFIG_DIR
            fi
            
            read -p "是否删除日志文件？(y/N): " del_log
            if [[ $del_log =~ ^[Yy]$ ]]; then
                rm -rf $LOG_DIR
            fi
            
            read -p "是否删除安装目录？(y/N): " del_install
            if [[ $del_install =~ ^[Yy]$ ]]; then
                rm -rf $INSTALL_DIR
            fi
            
            # 检查是否还有另一个服务
            if [ "$SERVICE_NAME" = "frps" ] && [ ! -f /etc/systemd/system/frpc.service ]; then
                read -p "是否删除管理脚本？(y/N): " del_script
                if [[ $del_script =~ ^[Yy]$ ]]; then
                    rm -f /usr/local/bin/frp
                fi
            elif [ "$SERVICE_NAME" = "frpc" ] && [ ! -f /etc/systemd/system/frps.service ]; then
                read -p "是否删除管理脚本？(y/N): " del_script
                if [[ $del_script =~ ^[Yy]$ ]]; then
                    rm -f /usr/local/bin/frp
                fi
            fi
            
            echo -e "${GREEN}✓ $SERVICE_NAME 已卸载${NC}"
        else
            echo -e "${YELLOW}取消卸载${NC}"
        fi
        exit 0
        ;;
    help|--help|-h)
        echo -e "${CYAN}Frp 管理工具${NC}"
        echo -e "用法: frp [命令]"
        echo -e ""
        echo -e "命令:"
        echo -e "  (无参数)     交互式菜单"
        echo -e "  start        启动服务"
        echo -e "  stop         停止服务"
        echo -e "  restart      重启服务"
        echo -e "  status       查看状态"
        echo -e "  reload       重载配置"
        echo -e "  log          查看日志"
        echo -e "  edit         编辑配置"
        echo -e "  enable       启用开机自启"
        echo -e "  disable      禁用开机自启"
        echo -e "  config       查看配置"
        echo -e "  uninstall    卸载服务"
        echo -e "  help         显示此帮助"
        exit 0
        ;;
    *)
        main_menu
        ;;
esac
EOF
    
    chmod +x /usr/local/bin/frp
    echo -e "${GREEN}✓ 管理脚本已创建: /usr/local/bin/frp${NC}"
}

# 创建卸载脚本
create_uninstall_script() {
    echo -e "\n${YELLOW}[6/7]${NC} 正在创建卸载脚本..."
    
    cat > /usr/local/bin/uninstall_frp << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}错误：必须使用root权限运行此脚本！${NC}" >&2
    exit 1
fi

# 检测已安装的服务
detect_installed_services() {
    SERVICES=()
    
    if [ -f /etc/systemd/system/frps.service ] || [ -f /usr/local/bin/frps ]; then
        SERVICES+=("frps")
    fi
    
    if [ -f /etc/systemd/system/frpc.service ] || [ -f /usr/local/bin/frpc ]; then
        SERVICES+=("frpc")
    fi
    
    if [ ${#SERVICES[@]} -eq 0 ]; then
        echo -e "${YELLOW}未找到已安装的frp服务${NC}"
        return 1
    fi
    
    return 0
}

# 显示卸载选项
show_menu() {
    echo -e "${YELLOW}检测到以下frp服务:${NC}"
    for i in "${!SERVICES[@]}"; do
        echo -e "  $((i+1)). ${SERVICES[$i]}"
    done
    echo -e "  $(( ${#SERVICES[@]} + 1 )). 卸载全部"
    echo -e "  0. 取消"
}

# 卸载服务
uninstall_service() {
    local SERVICE_NAME=$1
    
    echo -e "\n${RED}⚠ 警告：您将要卸载 $SERVICE_NAME${NC}"
    echo -e "${YELLOW}这将执行以下操作:${NC}"
    echo -e "  1. 停止 $SERVICE_NAME 服务"
    echo -e "  2. 禁用开机自启"
    echo -e "  3. 删除systemd服务文件"
    echo -e "  4. 删除二进制文件"
    echo ""
    
    read -p "确定要卸载 $SERVICE_NAME 吗？(y/N): " confirm
    if [[ ! $confirm =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}取消卸载 $SERVICE_NAME${NC}"
        return
    fi
    
    # 停止服务
    echo -e "${YELLOW}[1/5] 停止 $SERVICE_NAME 服务...${NC}"
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    
    # 禁用开机自启
    echo -e "${YELLOW}[2/5] 禁用开机自启...${NC}"
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    
    # 删除systemd服务文件
    echo -e "${YELLOW}[3/5] 删除systemd服务文件...${NC}"
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    
    # 删除二进制文件
    echo -e "${YELLOW}[4/5] 删除二进制文件...${NC}"
    rm -f /usr/local/bin/$SERVICE_NAME
    
    # 询问是否删除其他文件
    echo -e "\n${BLUE}是否删除以下文件？${NC}"
    
    # 配置文件
    if [ -d "/etc/frp" ]; then
        read -p "  删除配置文件目录 (/etc/frp)？(y/N): " del_conf
        if [[ $del_conf =~ ^[Yy]$ ]]; then
            rm -rf /etc/frp
            echo -e "  ${GREEN}✓ 配置文件已删除${NC}"
        fi
    fi
    
    # 日志文件
    if [ -d "/var/log/frp" ]; then
        read -p "  删除日志文件目录 (/var/log/frp)？(y/N): " del_log
        if [[ $del_log =~ ^[Yy]$ ]]; then
            rm -rf /var/log/frp
            echo -e "  ${GREEN}✓ 日志文件已删除${NC}"
        fi
    fi
    
    # 安装目录
    if [ -d "/usr/local/frp" ]; then
        read -p "  删除安装目录 (/usr/local/frp)？(y/N): " del_install
        if [[ $del_install =~ ^[Yy]$ ]]; then
            rm -rf /usr/local/frp
            echo -e "  ${GREEN}✓ 安装目录已删除${NC}"
        fi
    fi
    
    echo -e "${YELLOW}[5/5] 清理完成${NC}"
    echo -e "${GREEN}✓ $SERVICE_NAME 已成功卸载${NC}"
}

# 主卸载函数
main_uninstall() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}                  Frp 卸载工具                            ${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    
    # 检测已安装的服务
    if ! detect_installed_services; then
        exit 1
    fi
    
    # 显示菜单
    while true; do
        echo ""
        show_menu
        read -p "请选择要卸载的服务 (0-$((${#SERVICES[@]}+1))): " choice
        
        case $choice in
            0)
                echo -e "${YELLOW}取消卸载${NC}"
                exit 0
                ;;
            $(( ${#SERVICES[@]} + 1 )))
                # 卸载全部
                echo -e "${RED}⚠ 警告：将要卸载所有frp服务${NC}"
                read -p "确定要卸载全部吗？(y/N): " confirm_all
                if [[ $confirm_all =~ ^[Yy]$ ]]; then
                    for service in "${SERVICES[@]}"; do
                        uninstall_service $service
                    done
                    
                    # 删除管理脚本
                    if [ -f "/usr/local/bin/frp" ]; then
                        read -p "删除管理脚本 (/usr/local/bin/frp)？(y/N): " del_script
                        if [[ $del_script =~ ^[Yy]$ ]]; then
                            rm -f /usr/local/bin/frp
                            echo -e "${GREEN}✓ 管理脚本已删除${NC}"
                        fi
                    fi
                    
                    echo -e "\n${GREEN}✓ 所有frp服务已卸载${NC}"
                else
                    echo -e "${YELLOW}取消卸载全部${NC}"
                fi
                exit 0
                ;;
            *)
                if [ $choice -ge 1 ] && [ $choice -le ${#SERVICES[@]} ]; then
                    SERVICE_NAME=${SERVICES[$((choice-1))]}
                    uninstall_service $SERVICE_NAME
                    
                    # 如果卸载了所有服务，询问是否删除管理脚本
                    remaining_services=0
                    for service in "${SERVICES[@]}"; do
                        if [ "$service" != "$SERVICE_NAME" ] && { [ -f "/etc/systemd/system/$service.service" ] || [ -f "/usr/local/bin/$service" ]; }; then
                            remaining_services=$((remaining_services+1))
                        fi
                    done
                    
                    if [ $remaining_services -eq 0 ] && [ -f "/usr/local/bin/frp" ]; then
                        read -p "删除管理脚本 (/usr/local/bin/frp)？(y/N): " del_script
                        if [[ $del_script =~ ^[Yy]$ ]]; then
                            rm -f /usr/local/bin/frp
                            echo -e "${GREEN}✓ 管理脚本已删除${NC}"
                        fi
                    fi
                    
                    exit 0
                else
                    echo -e "${RED}无效选择，请重新输入${NC}"
                fi
                ;;
        esac
    done
}

# 执行主函数
main_uninstall
EOF
    
    chmod +x /usr/local/bin/uninstall_frp
    echo -e "${GREEN}✓ 卸载脚本已创建: /usr/local/bin/uninstall_frp${NC}"
}

# 显示安装完成信息
show_completion_info() {
    echo -e "\n${YELLOW}[7/7]${NC} 安装完成！"
    
    # 获取服务信息
    SERVICE_STATUS=$(systemctl is-active $SERVICE_NAME 2>/dev/null || echo "inactive")
    
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                  Frps 安装完成！                          ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}服务信息:${NC}"
    echo -e "  ${BOLD}服务状态:${NC} $(if [ "$SERVICE_STATUS" = "active" ]; then echo -e "${GREEN}运行中${NC}"; else echo -e "${YELLOW}未运行${NC}"; fi)"
    echo -e "  ${BOLD}服务名称:${NC} $SERVICE_NAME"
    echo -e "  ${BOLD}配置文件:${NC} $CONFIG_DIR/frps.ini"
    echo -e "  ${BOLD}安装目录:${NC} $INSTALL_DIR"
    echo -e "  ${BOLD}日志目录:${NC} $LOG_DIR"
    echo ""
    echo -e "${CYAN}管理命令:${NC}"
    echo -e "  ${BOLD}交互式管理:${NC} ${GREEN}frp${NC}"
    echo -e "  ${BOLD}启动服务:${NC}    systemctl start $SERVICE_NAME"
    echo -e "  ${BOLD}停止服务:${NC}    systemctl stop $SERVICE_NAME"
    echo -e "  ${BOLD}重启服务:${NC}    systemctl restart $SERVICE_NAME"
    echo -e "  ${BOLD}查看状态:${NC}    systemctl status $SERVICE_NAME"
    echo -e "  ${BOLD}查看日志:${NC}    journalctl -u $SERVICE_NAME -f"
    echo ""
    echo -e "${CYAN}快速命令:${NC}"
    echo -e "  frp start      # 启动服务"
    echo -e "  frp stop       # 停止服务"
    echo -e "  frp restart    # 重启服务"
    echo -e "  frp status     # 查看状态"
    echo -e "  frp reload     # 重载配置"
    echo -e "  frp log        # 查看日志"
    echo -e "  frp edit       # 编辑配置"
    echo -e "  frp uninstall  # 卸载服务"
    echo ""
    echo -e "${CYAN}管理面板:${NC}"
    echo -e "  ${BOLD}地址:${NC} http://$(curl -s icanhazip.com || echo "服务器IP"):7500"
    echo -e "  ${BOLD}用户:${NC} admin"
    echo -e "  ${BOLD}密码:${NC} 查看 $CONFIG_DIR/frps.ini 中的 dashboard_pwd"
    echo ""
    echo -e "${RED}重要提示:${NC}"
    echo -e "  1. 请编辑 $CONFIG_DIR/frps.ini 修改默认配置"
    echo -e "  2. 确保防火墙开放了相应端口 (7000, 7500)"
    echo -e "  3. 建议修改默认的 token 和 dashboard_pwd"
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
}

# 安装完成后的配置
post_install_config() {
    # 设置文件权限
    chmod 600 $CONFIG_DIR/frps.ini
    chmod 644 $CONFIG_DIR/frps_full.ini.example
    
    # 启动服务
    echo -e "\n${YELLOW}启动 $SERVICE_NAME 服务...${NC}"
    systemctl start $SERVICE_NAME
    sleep 2
    
    # 检查服务状态
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✓ $SERVICE_NAME 服务启动成功${NC}"
    else
        echo -e "${RED}✗ $SERVICE_NAME 服务启动失败，请检查日志${NC}"
        journalctl -u $SERVICE_NAME --no-pager -n 20
    fi
}

# 主安装函数
main_install() {
    show_banner
    echo -e "${GREEN}开始安装 Frp 服务端...${NC}\n"
    
    # 检查是否已安装
    if check_installed; then
        echo -e "${YELLOW}检测到已安装 $SERVICE_NAME${NC}"
        read -p "是否重新安装？(y/N): " reinstall
        if [[ ! $reinstall =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}取消安装${NC}"
            exit 0
        fi
        echo -e "${YELLOW}开始重新安装...${NC}"
    fi
    
    detect_os
    detect_arch
    
    install_dependencies
    install_frp
    create_config
    create_service
    create_management_script
    create_uninstall_script
    post_install_config
    show_completion_info
}

# 卸载函数
uninstall_frp() {
    show_banner
    echo -e "${RED}开始卸载 Frp 服务端...${NC}\n"
    
    if ! check_installed; then
        echo -e "${YELLOW}未检测到 $SERVICE_NAME 安装${NC}"
        exit 1
    fi
    
    # 停止服务
    echo -e "${YELLOW}[1/5] 停止 $SERVICE_NAME 服务...${NC}"
    systemctl stop $SERVICE_NAME 2>/dev/null || true
    
    # 禁用开机自启
    echo -e "${YELLOW}[2/5] 禁用开机自启...${NC}"
    systemctl disable $SERVICE_NAME 2>/dev/null || true
    
    # 删除systemd服务
    echo -e "${YELLOW}[3/5] 删除systemd服务...${NC}"
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    systemctl daemon-reload
    systemctl reset-failed
    
    # 删除二进制文件
    echo -e "${YELLOW}[4/5] 删除二进制文件...${NC}"
    rm -f /usr/local/bin/$BINARY_NAME
    rm -f /usr/local/bin/frps
    rm -f /usr/local/bin/frpc
    
    # 询问是否删除其他文件
    echo -e "${YELLOW}[5/5] 清理文件...${NC}"
    
    echo -e "\n${BLUE}是否删除以下文件？${NC}"
    
    read -p "删除配置文件目录 ($CONFIG_DIR)？(y/N): " del_conf
    if [[ $del_conf =~ ^[Yy]$ ]]; then
        rm -rf $CONFIG_DIR
        echo -e "${GREEN}✓ 配置文件已删除${NC}"
    fi
    
    read -p "删除日志文件目录 ($LOG_DIR)？(y/N): " del_log
    if [[ $del_log =~ ^[Yy]$ ]]; then
        rm -rf $LOG_DIR
        echo -e "${GREEN}✓ 日志文件已删除${NC}"
    fi
    
    read -p "删除安装目录 ($INSTALL_DIR)？(y/N): " del_install
    if [[ $del_install =~ ^[Yy]$ ]]; then
        rm -rf $INSTALL_DIR
        echo -e "${GREEN}✓ 安装目录已删除${NC}"
    fi
    
    read -p "删除管理脚本 (/usr/local/bin/frp)？(y/N): " del_script
    if [[ $del_script =~ ^[Yy]$ ]]; then
        rm -f /usr/local/bin/frp
        echo -e "${GREEN}✓ 管理脚本已删除${NC}"
    fi
    
    read -p "删除卸载脚本 (/usr/local/bin/uninstall_frp)？(y/N): " del_uninstall
    if [[ $del_uninstall =~ ^[Yy]$ ]]; then
        rm -f /usr/local/bin/uninstall_frp
        echo -e "${GREEN}✓ 卸载脚本已删除${NC}"
    fi
    
    echo -e "\n${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}                  Frps 卸载完成！                          ${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${YELLOW}注意:${NC}"
    echo -e "  1. 用户数据（如有）可能需要手动备份"
    echo -e "  2. 防火墙规则可能需要手动清理"
    echo -e "  3. 如果使用Docker，请检查相关容器"
    echo ""
    echo -e "${GREEN}感谢使用，再见！${NC}"
}

# 显示帮助
show_help() {
    echo -e "${BLUE}Frp 服务端安装脚本 v${SCRIPT_VERSION}${NC}"
    echo -e "用法: $0 [选项]"
    echo ""
    echo -e "选项:"
    echo -e "  install        安装 Frp 服务端 (默认)"
    echo -e "  uninstall      卸载 Frp 服务端"
    echo -e "  help           显示此帮助信息"
    echo -e "  version        显示版本信息"
    echo ""
    echo -e "示例:"
    echo -e "  $0              # 安装 Frp 服务端"
    echo -e "  $0 install      # 安装 Frp 服务端"
    echo -e "  $0 uninstall    # 卸载 Frp 服务端"
    echo -e "  $0 help         # 显示帮助"
    exit 0
}

# 显示版本
show_version() {
    echo -e "${BLUE}Frp 服务端安装脚本${NC}"
    echo -e "版本: ${GREEN}v${SCRIPT_VERSION}${NC}"
    echo -e "支持系统: Debian, Ubuntu, CentOS, RHEL, Fedora, Arch, Alpine 等"
    echo -e "支持架构: x86_64, arm64, arm, 386, mips, s390x, ppc64le, riscv64 等"
    exit 0
}

# 主入口
case "$1" in
    install|"")
        check_root
        main_install
        ;;
    uninstall|remove)
        check_root
        uninstall_frp
        ;;
    help|--help|-h)
        show_help
        ;;
    version|--version|-v)
        show_version
        ;;
    *)
        echo -e "${RED}未知选项: $1${NC}"
        echo -e "使用 '$0 help' 查看帮助"
        exit 1
        ;;
esac