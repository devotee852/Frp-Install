#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误：必须使用root权限运行此脚本！${NC}" >&2
        exit 1
    fi
}

# 识别系统类型
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/centos-release ]; then
        OS="centos"
        OS_VERSION=$(cat /etc/centos-release | tr -dc '0-9.' | cut -d '.' -f1)
    else
        OS=$(uname -s)
    fi
    
    echo -e "${BLUE}检测到系统: ${OS} ${OS_VERSION}${NC}"
}

# 检测系统架构
detect_arch() {
    ARCH=$(uname -m)
    case $ARCH in
        x86_64)
            FRP_ARCH="amd64"
            ;;
        aarch64|arm64)
            FRP_ARCH="arm64"
            ;;
        armv7l|armv8l)
            FRP_ARCH="arm"
            ;;
        i386|i686)
            FRP_ARCH="386"
            ;;
        mips)
            FRP_ARCH="mips"
            ;;
        mips64)
            FRP_ARCH="mips64"
            ;;
        mips64el)
            FRP_ARCH="mips64le"
            ;;
        mipsel)
            FRP_ARCH="mipsle"
            ;;
        s390x)
            FRP_ARCH="s390x"
            ;;
        *)
            echo -e "${RED}不支持的架构: $ARCH${NC}"
            exit 1
            ;;
    esac
    echo -e "${BLUE}系统架构: $ARCH -> frp架构: $FRP_ARCH${NC}"
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装依赖...${NC}"
    
    case $OS in
        debian|ubuntu|raspbian)
            apt-get update
            apt-get install -y wget tar
            ;;
        centos|rhel|fedora|rocky|almalinux)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y wget tar
            elif command -v yum >/dev/null 2>&1; then
                yum install -y wget tar
            fi
            ;;
        arch|manjaro)
            pacman -Syu --noconfirm wget tar
            ;;
        alpine)
            apk add wget tar
            ;;
        *)
            echo -e "${YELLOW}未知系统，尝试安装wget和tar...${NC}"
            if command -v apt-get >/dev/null 2>&1; then
                apt-get install -y wget tar
            elif command -v yum >/dev/null 2>&1; then
                yum install -y wget tar
            fi
            ;;
    esac
}

# 下载并安装frp
install_frp() {
    FRP_VERSION="0.43.0"
    #FRP_URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
	#这里采用github加速下载FRPC安装包
	FRP_URL="https://gh-proxy.org/https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"

    echo -e "${YELLOW}正在下载 frp v${FRP_VERSION} for ${FRP_ARCH}...${NC}"
    
    # 创建目录
    mkdir -p /etc/frp /var/log/frp /usr/local/frp
    
    # 下载frp
    if wget -O /tmp/frp.tar.gz "$FRP_URL"; then
        echo -e "${GREEN}下载成功！${NC}"
    else
        echo -e "${RED}下载失败，请检查网络和架构支持！${NC}"
        
        # 尝试备用下载
        echo -e "${YELLOW}尝试备用下载源...${NC}"
        FRP_URL="https://cdn.jsdelivr.net/gh/fatedier/frp@v${FRP_VERSION}/frp_${FRP_VERSION}_linux_${FRP_ARCH}.tar.gz"
        if ! wget -O /tmp/frp.tar.gz "$FRP_URL"; then
            echo -e "${RED}备用下载也失败，请手动下载并安装${NC}"
            exit 1
        fi
    fi
    
    # 解压文件
    echo -e "${YELLOW}正在解压文件...${NC}"
    tar -zxvf /tmp/frp.tar.gz -C /usr/local/frp --strip-components=1
    
    # 复制二进制文件
    if [ -f /usr/local/frp/frps ]; then
        cp /usr/local/frp/frps /usr/local/bin/
        chmod +x /usr/local/bin/frps
        echo -e "${GREEN}frps 安装完成${NC}"
    else
        echo -e "${RED}frps 文件不存在，解压可能失败！${NC}"
        exit 1
    fi
}

# 创建配置文件
create_config() {
    echo -e "${YELLOW}正在创建配置文件...${NC}"
    
    # 创建默认配置文件
    cat > /etc/frp/frps.ini << EOF
[common]
bind_port = 7000
bind_addr = 0.0.0.0
token = $(openssl rand -hex 16)

dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = $(openssl rand -hex 8)

# 详细配置请参考: https://gofrp.org/docs/examples/tcp/
# 更多配置选项请参考官方文档

log_file = /var/log/frp/frps.log
log_level = info
log_max_days = 3
EOF
    
    echo -e "${GREEN}配置文件已创建: /etc/frp/frps.ini${NC}"
    echo -e "${YELLOW}请根据需求修改配置文件${NC}"
}

# 创建systemd服务
create_service() {
    echo -e "${YELLOW}正在创建systemd服务...${NC}"
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/frps.service << EOF
[Unit]
Description=Frp Server Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.ini
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576
StandardOutput=syslog
StandardError=syslog
SyslogIdentifier=frps

[Install]
WantedBy=multi-user.target
EOF
    
    # 创建日志配置文件（如果使用syslog）
    if [ -d /etc/rsyslog.d ]; then
        cat > /etc/rsyslog.d/frps.conf << EOF
if \$programname == 'frps' then /var/log/frp/frps.log
& stop
EOF
        systemctl restart rsyslog
    fi
    
    # 重载systemd
    systemctl daemon-reload
    systemctl enable frps
    
    echo -e "${GREEN}systemd服务已创建${NC}"
}

# 创建管理脚本
create_management_script() {
    echo -e "${YELLOW}正在创建管理脚本...${NC}"
    
    cat > /usr/local/bin/frp << 'EOF'
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 检查服务类型
if systemctl is-active --quiet frps 2>/dev/null; then
    SERVICE_NAME="frps"
    CONFIG_FILE="/etc/frp/frps.ini"
elif systemctl is-active --quiet frpc 2>/dev/null; then
    SERVICE_NAME="frpc"
    CONFIG_FILE="/etc/frp/frpc.ini"
elif [ -f /etc/systemd/system/frps.service ]; then
    SERVICE_NAME="frps"
    CONFIG_FILE="/etc/frp/frps.ini"
elif [ -f /etc/systemd/system/frpc.service ]; then
    SERVICE_NAME="frpc"
    CONFIG_FILE="/etc/frp/frpc.ini"
else
    echo -e "${RED}未找到frp服务${NC}"
    exit 1
fi

show_menu() {
    clear
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}      Frp 服务管理脚本         ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "服务: ${GREEN}${SERVICE_NAME}${NC}"
    echo -e "配置文件: ${YELLOW}${CONFIG_FILE}${NC}"
    echo -e "${BLUE}================================${NC}"
    echo -e "1. ${GREEN}启动服务${NC}"
    echo -e "2. ${RED}停止服务${NC}"
    echo -e "3. ${YELLOW}重启服务${NC}"
    echo -e "4. ${BLUE}重载配置并重启${NC}"
    echo -e "5. 查看服务状态"
    echo -e "6. 查看服务日志"
    echo -e "7. 编辑配置文件"
    echo -e "8. 重载systemd配置"
    echo -e "9. 设置开机自启"
    echo -e "10. 禁用开机自启"
	echo -e "11. 卸载 ${GREEN}${SERVICE_NAME}${NC}"
    echo -e "0. 退出"
    echo -e "${BLUE}================================${NC}"
}

# 如果传入参数，直接执行对应操作
if [ $# -gt 0 ]; then
    case $1 in
        1|start)
            echo -e "${GREEN}启动 ${SERVICE_NAME}...${NC}"
            systemctl start ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        2|stop)
            echo -e "${RED}停止 ${SERVICE_NAME}...${NC}"
            systemctl stop ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        3|restart)
            echo -e "${YELLOW}重启 ${SERVICE_NAME}...${NC}"
            systemctl restart ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        4|reload)
            echo -e "${BLUE}重载配置并重启...${NC}"
            systemctl daemon-reload
            systemctl restart ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        5|status)
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        6|log)
            journalctl -u ${SERVICE_NAME} -f
            ;;
        7|edit)
            vi ${CONFIG_FILE}
            ;;
        8|daemon-reload)
            systemctl daemon-reload
            echo -e "${GREEN}systemd配置已重载${NC}"
            ;;
        9|enable)
            systemctl enable ${SERVICE_NAME}
            echo -e "${GREEN}已设置开机自启${NC}"
            ;;
        10|disable)
            systemctl disable ${SERVICE_NAME}
            echo -e "${RED}已禁用开机自启${NC}"
            ;;
        11|uninstall)
			echo -e "${YELLOW}================================${NC}"
			echo -e "${YELLOW}      Frp 卸载程序             ${NC}"
			echo -e "${YELLOW}================================${NC}"
			echo -e "${RED}警告：此操作将完全移除 frp 服务${NC}"
			echo -e ""
			echo -e "将移除以下内容："
			echo -e "1. systemd 服务 (frps)"
			echo -e "2. 二进制文件 (/usr/local/bin/frps)"
			echo -e "3. FRP 程序文件 (/usr/local/frp/)"
			echo -e "4. 配置文件 (/etc/frp/)"
			echo -e "5. 管理脚本 (/usr/local/bin/frp)"
			echo -e "6. 日志文件 (/var/log/frp/)"
			echo -e ""
			
			read -p "您确定要卸载 frp 吗？(y/N): " -n 1 -r
			echo ""
			
			if [[ ! $REPLY =~ ^[Yy]$ ]]; then
				echo -e "${GREEN}卸载已取消${NC}"
				exit 0
			fi
			
			echo -e "${YELLOW}开始卸载 frp...${NC}"
			
			# 停止并禁用服务
			if systemctl is-active --quiet frps 2>/dev/null; then
				echo -e "${YELLOW}停止 frp 服务...${NC}"
				systemctl stop frps
			fi
			
			if systemctl is-enabled --quiet frps 2>/dev/null; then
				echo -e "${YELLOW}禁用 frp 服务自启动...${NC}"
				systemctl disable frps
			fi
			
			# 移除systemd服务文件
			if [ -f /etc/systemd/system/frps.service ]; then
				echo -e "${YELLOW}删除 systemd 服务文件...${NC}"
				rm -f /etc/systemd/system/frps.service
				systemctl daemon-reload
			fi
			
			# 移除rsyslog配置
			if [ -f /etc/rsyslog.d/frps.conf ]; then
				echo -e "${YELLOW}删除 rsyslog 配置...${NC}"
				rm -f /etc/rsyslog.d/frps.conf
				systemctl restart rsyslog 2>/dev/null || true
			fi
			
			# 删除二进制文件
			if [ -f /usr/local/bin/frps ]; then
				echo -e "${YELLOW}删除 frp 二进制文件...${NC}"
				rm -f /usr/local/bin/frps
			fi
			
			# 删除FRP程序目录
			if [ -d /usr/local/frp ]; then
				echo -e "${YELLOW}删除 frp 程序目录...${NC}"
				rm -rf /usr/local/frp
			fi
			
			# 删除配置文件目录
			if [ -d /etc/frp ]; then
				echo -e "${YELLOW}删除配置文件目录...${NC}"
				rm -rf /etc/frp
			fi
			
			# 删除日志目录
			if [ -d /var/log/frp ]; then
				echo -e "${YELLOW}删除日志目录...${NC}"
				rm -rf /var/log/frp
			fi
			
			# 删除管理脚本
			if [ -f /usr/local/bin/frp ]; then
				echo -e "${YELLOW}删除管理脚本...${NC}"
				rm -f /usr/local/bin/frp
			fi
			
			# 删除临时文件
			if [ -f /tmp/frp.tar.gz ]; then
				echo -e "${YELLOW}清理临时文件...${NC}"
				rm -f /tmp/frp.tar.gz
			fi
			
			# 检查是否还有其他frp相关文件
			echo -e "${YELLOW}检查剩余文件...${NC}"
			
			# 检查frpc相关文件（如果存在）
			if [ -f /usr/local/bin/frpc ]; then
				echo -e "${YELLOW}检测到 frpc 客户端文件，是否删除？${NC}"
				read -p "删除 frpc 文件？(y/N): " -n 1 -r
				echo ""
				if [[ $REPLY =~ ^[Yy]$ ]]; then
					rm -f /usr/local/bin/frpc
					echo -e "${GREEN}已删除 frpc 客户端${NC}"
				fi
			fi
			
			if [ -f /etc/systemd/system/frpc.service ]; then
				systemctl stop frpc 2>/dev/null || true
				systemctl disable frpc 2>/dev/null || true
				rm -f /etc/systemd/system/frpc.service
				echo -e "${GREEN}已删除 frpc 服务${NC}"
			fi
			
			echo -e "${GREEN}================================${NC}"
			echo -e "${GREEN}      Frp 卸载完成！           ${NC}"
			echo -e "${GREEN}================================${NC}"
			echo -e ""
			echo -e "建议执行以下命令清理系统："
			echo -e "1. ${BLUE}systemctl daemon-reload${NC}"
			echo -e "2. ${BLUE}systemctl reset-failed${NC}"
			echo -e "3. ${BLUE}journalctl --vacuum-time=1d${NC} (清理旧日志)"
			echo -e ""
			echo -e "${YELLOW}注意：用户配置文件、日志等已永久删除${NC}"
			exit 0
            ;;
        *)
            echo -e "${RED}未知参数: $1${NC}"
            echo -e "可用参数: start, stop, restart, reload, status, log, edit, daemon-reload, enable, disable, uninstall"
            ;;
    esac
    exit 0
fi

# 交互式菜单
while true; do
    show_menu
    read -p "请选择操作 (0-10): " choice
    
    case $choice in
        1)
            echo -e "${GREEN}启动 ${SERVICE_NAME}...${NC}"
            systemctl start ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        2)
            echo -e "${RED}停止 ${SERVICE_NAME}...${NC}"
            systemctl stop ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        3)
            echo -e "${YELLOW}重启 ${SERVICE_NAME}...${NC}"
            systemctl restart ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        4)
            echo -e "${BLUE}重载配置并重启...${NC}"
            systemctl daemon-reload
            systemctl restart ${SERVICE_NAME}
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        5)
            systemctl status ${SERVICE_NAME} --no-pager
            ;;
        6)
            journalctl -u ${SERVICE_NAME} -f
            ;;
        7)
            ${EDITOR:-vi} ${CONFIG_FILE}
            ;;
        8)
            systemctl daemon-reload
            echo -e "${GREEN}systemd配置已重载${NC}"
            ;;
        9)
            systemctl enable ${SERVICE_NAME}
            echo -e "${GREEN}已设置开机自启${NC}"
            ;;
        10)
            systemctl disable ${SERVICE_NAME}
            echo -e "${RED}已禁用开机自启${NC}"
            ;;
        11)
			echo -e "${YELLOW}================================${NC}"
			echo -e "${YELLOW}      Frp 卸载程序             ${NC}"
			echo -e "${YELLOW}================================${NC}"
			echo -e "${RED}警告：此操作将完全移除 frp 服务${NC}"
			echo -e ""
			echo -e "将移除以下内容："
			echo -e "1. systemd 服务 (frps)"
			echo -e "2. 二进制文件 (/usr/local/bin/frps)"
			echo -e "3. FRP 程序文件 (/usr/local/frp/)"
			echo -e "4. 配置文件 (/etc/frp/)"
			echo -e "5. 管理脚本 (/usr/local/bin/frp)"
			echo -e "6. 日志文件 (/var/log/frp/)"
			echo -e ""
			
			read -p "您确定要卸载 frp 吗？(y/N): " -n 1 -r
			echo ""
			
			if [[ ! $REPLY =~ ^[Yy]$ ]]; then
				echo -e "${GREEN}卸载已取消${NC}"
				exit 0
			fi
			
			echo -e "${YELLOW}开始卸载 frp...${NC}"
			
			# 停止并禁用服务
			if systemctl is-active --quiet frps 2>/dev/null; then
				echo -e "${YELLOW}停止 frp 服务...${NC}"
				systemctl stop frps
			fi
			
			if systemctl is-enabled --quiet frps 2>/dev/null; then
				echo -e "${YELLOW}禁用 frp 服务自启动...${NC}"
				systemctl disable frps
			fi
			
			# 移除systemd服务文件
			if [ -f /etc/systemd/system/frps.service ]; then
				echo -e "${YELLOW}删除 systemd 服务文件...${NC}"
				rm -f /etc/systemd/system/frps.service
				systemctl daemon-reload
			fi
			
			# 移除rsyslog配置
			if [ -f /etc/rsyslog.d/frps.conf ]; then
				echo -e "${YELLOW}删除 rsyslog 配置...${NC}"
				rm -f /etc/rsyslog.d/frps.conf
				systemctl restart rsyslog 2>/dev/null || true
			fi
			
			# 删除二进制文件
			if [ -f /usr/local/bin/frps ]; then
				echo -e "${YELLOW}删除 frp 二进制文件...${NC}"
				rm -f /usr/local/bin/frps
			fi
			
			# 删除FRP程序目录
			if [ -d /usr/local/frp ]; then
				echo -e "${YELLOW}删除 frp 程序目录...${NC}"
				rm -rf /usr/local/frp
			fi
			
			# 删除配置文件目录
			if [ -d /etc/frp ]; then
				echo -e "${YELLOW}删除配置文件目录...${NC}"
				rm -rf /etc/frp
			fi
			
			# 删除日志目录
			if [ -d /var/log/frp ]; then
				echo -e "${YELLOW}删除日志目录...${NC}"
				rm -rf /var/log/frp
			fi
			
			# 删除管理脚本
			if [ -f /usr/local/bin/frp ]; then
				echo -e "${YELLOW}删除管理脚本...${NC}"
				rm -f /usr/local/bin/frp
			fi
			
			# 删除临时文件
			if [ -f /tmp/frp.tar.gz ]; then
				echo -e "${YELLOW}清理临时文件...${NC}"
				rm -f /tmp/frp.tar.gz
			fi
			
			# 检查是否还有其他frp相关文件
			echo -e "${YELLOW}检查剩余文件...${NC}"
			
			# 检查frpc相关文件（如果存在）
			if [ -f /usr/local/bin/frpc ]; then
				echo -e "${YELLOW}检测到 frpc 客户端文件，是否删除？${NC}"
				read -p "删除 frpc 文件？(y/N): " -n 1 -r
				echo ""
				if [[ $REPLY =~ ^[Yy]$ ]]; then
					rm -f /usr/local/bin/frpc
					echo -e "${GREEN}已删除 frpc 客户端${NC}"
				fi
			fi
			
			if [ -f /etc/systemd/system/frpc.service ]; then
				systemctl stop frpc 2>/dev/null || true
				systemctl disable frpc 2>/dev/null || true
				rm -f /etc/systemd/system/frpc.service
				echo -e "${GREEN}已删除 frpc 服务${NC}"
			fi
			
			echo -e "${GREEN}================================${NC}"
			echo -e "${GREEN}      Frp 卸载完成！           ${NC}"
			echo -e "${GREEN}================================${NC}"
			echo -e ""
			echo -e "建议执行以下命令清理系统："
			echo -e "1. ${BLUE}systemctl daemon-reload${NC}"
			echo -e "2. ${BLUE}systemctl reset-failed${NC}"
			echo -e "3. ${BLUE}journalctl --vacuum-time=1d${NC} (清理旧日志)"
			echo -e ""
			echo -e "${YELLOW}注意：用户配置文件、日志等已永久删除${NC}"
			exit 0
            ;;
        0)
            echo -e "${BLUE}再见！${NC}"
            exit 0
            ;;
        *)
            echo -e "${RED}无效选择，请重新输入${NC}"
            ;;
    esac
    
    read -p "按回车键继续..."
done
EOF
    
    chmod +x /usr/local/bin/frp
    echo -e "${GREEN}管理脚本已创建: /usr/local/bin/frp${NC}"
}

# 显示安装完成信息
show_completion_info() {
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      Frps 安装完成！                   ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo -e "管理命令: ${YELLOW}frp${NC} (交互式菜单)"
    echo -e "快速命令:"
    echo -e "  ${BLUE}frp start${NC}      # 启动服务"
    echo -e "  ${BLUE}frp stop${NC}       # 停止服务"
    echo -e "  ${BLUE}frp restart${NC}    # 重启服务"
    echo -e "  ${BLUE}frp status${NC}     # 查看状态"
    echo -e "  ${BLUE}frp reload${NC}     # 重载配置"
    echo -e "配置文件: ${YELLOW}/etc/frp/frps.ini${NC}"
    echo -e "日志文件: ${YELLOW}/var/log/frp/frps.log${NC}"
    echo -e ""
    echo -e "${YELLOW}请编辑配置文件: /etc/frp/frps.ini${NC}"
    echo -e "${YELLOW}修改 token 和其他配置项${NC}"
    echo -e ""
    echo -e "${GREEN}启动服务命令: systemctl start frps${NC}"
    echo -e "${GREEN}设置开机自启: systemctl enable frps${NC}"
    echo -e "${GREEN}========================================${NC}"
}

# 主函数
main() {
    echo -e "${BLUE}开始安装 Frp 服务端...${NC}"
    
    check_root
    detect_os
    detect_arch
    install_dependencies
    install_frp
    create_config
    create_service
    create_management_script
    
    echo -e "${GREEN}启动 Frp 服务...${NC}"
    systemctl start frps
    
    show_completion_info
}

# 执行主函数
main
