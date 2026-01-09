#!/bin/bash

# Frp Server 自动安装与管理脚本
# 作者: 系统管理员
# 版本: 1.0

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误: 此脚本需要root权限运行" >&2
    exit 1
fi

# 常量定义
FRP_URL="https://github.com/fatedier/frp/releases/download/v0.43.0/frp_0.43.0_linux_amd64.tar.gz"
INSTALL_DIR="/usr/local/frp"
BIN_DIR="/usr/local/bin"
CONFIG_DIR="/etc/frp"
SERVICE_NAME="frps"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
MANAGER_FILE="/usr/local/bin/frp_manager"
FRP_BIN="${BIN_DIR}/frps"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示带颜色的消息
show_message() {
    case $1 in
        success) echo -e "${GREEN}✓ $2${NC}" ;;
        error) echo -e "${RED}✗ $2${NC}" ;;
        warning) echo -e "${YELLOW}⚠ $2${NC}" ;;
        info) echo -e "${BLUE}ℹ $2${NC}" ;;
    esac
}

# 检查依赖
check_dependencies() {
    local missing_deps=()
    
    # 检查必要命令
    for cmd in wget tar systemctl; do
        if ! command -v $cmd &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        show_message error "缺少必要的依赖: ${missing_deps[*]}"
        echo "请先安装这些依赖包:"
        echo "  Ubuntu/Debian: apt-get install -y wget tar systemd"
        echo "  CentOS/RHEL: yum install -y wget tar systemd"
        exit 1
    fi
}

# 备份现有配置
backup_config() {
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        local backup_file="$CONFIG_DIR/frps.ini.backup.$(date +%Y%m%d_%H%M%S)"
        cp -f "$CONFIG_DIR/frps.ini" "$backup_file"
        show_message info "已备份旧配置文件到: $backup_file"
    fi
}

# 检查服务状态
check_service_status() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        return 0
    else
        return 1
    fi
}

# 安装Frps服务
install_frps() {
    echo ""
    echo "正在安装Frp Server..."
    echo "==============================="
    
    # 检查依赖
    check_dependencies
    
    # 创建目录
    mkdir -p $INSTALL_DIR $CONFIG_DIR
    
    # 下载文件
    show_message info "正在下载FRP..."
    if ! wget -qO /tmp/frp.tar.gz $FRP_URL; then
        show_message error "下载失败，请检查网络连接或URL"
        echo "尝试备用下载..."
        if ! curl -sL $FRP_URL -o /tmp/frp.tar.gz; then
            show_message error "备用下载也失败，请手动下载FRP"
            exit 1
        fi
    fi
    
    # 解压文件
    show_message info "正在解压文件..."
    if ! tar -xzf /tmp/frp.tar.gz -C $INSTALL_DIR --strip-components=1; then
        show_message error "解压失败"
        exit 1
    fi
    
    # 检查解压的文件
    if [ ! -f "$INSTALL_DIR/frps" ]; then
        show_message error "解压后未找到frps文件"
        exit 1
    fi
    
    # 复制二进制文件
    show_message info "安装二进制文件..."
    cp -f "$INSTALL_DIR/frps" "$FRP_BIN"
    
    # 创建默认配置文件
    if [ ! -f "$CONFIG_DIR/frps.ini" ]; then
        show_message info "创建默认配置文件..."
        cat > "$CONFIG_DIR/frps.ini" << 'EOF'
[common]
bind_port = 7000
token = $(date +%s | sha256sum | base64 | head -c 32)
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = $(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
enable_prometheus = true
log_level = info
log_max_days = 3
disable_log_color = false
EOF
        # 生成随机token和密码
        local random_token=$(date +%s | sha256sum | base64 | head -c 32)
        local random_pwd=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 16)
        
        # 替换配置文件
        sed -i "s/token = .*/token = $random_token/" "$CONFIG_DIR/frps.ini"
        sed -i "s/dashboard_pwd = .*/dashboard_pwd = $random_pwd/" "$CONFIG_DIR/frps.ini"
        
        show_message success "已生成随机token和密码"
        echo "Token: $random_token"
        echo "Dashboard密码: $random_pwd"
    else
        backup_config
        show_message warning "配置文件已存在，保留现有配置"
    fi
    
    # 创建systemd服务文件
    show_message info "创建systemd服务..."
    cat > "$SERVICE_FILE" << EOF
[Unit]
Description=Frp Server Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
User=nobody
Group=nogroup
Restart=on-failure
RestartSec=5s
LimitNOFILE=4096
ExecStart=$FRP_BIN -c $CONFIG_DIR/frps.ini
ExecReload=/bin/kill -HUP \$MAINPID
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
    
    # 设置权限
    chmod 644 "$CONFIG_DIR/frps.ini"
    chmod 755 "$FRP_BIN"
    chmod 644 "$SERVICE_FILE"
    
    # 重载systemd
    systemctl daemon-reload
    
    # 启用开机启动
    if systemctl enable $SERVICE_NAME >/dev/null 2>&1; then
        show_message success "已启用开机自启动"
    fi
    
    # 启动服务
    show_message info "启动Frp服务..."
    if systemctl start $SERVICE_NAME; then
        show_message success "Frp服务启动成功"
    else
        show_message error "Frp服务启动失败"
        echo "请运行以下命令查看错误信息:"
        echo "  journalctl -u $SERVICE_NAME -n 20 --no-pager"
    fi
    
    # 清理临时文件
    rm -f /tmp/frp.tar.gz
    
    show_message success "Frps安装完成!"
}

# 安装管理脚本
install_manager() {
    show_message info "安装管理脚本..."
    
    # 检查是否已有管理脚本
    if [ -f "$MANAGER_FILE" ]; then
        local backup_file="${MANAGER_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
        cp -f "$MANAGER_FILE" "$backup_file"
        show_message info "已备份旧管理脚本: $backup_file"
    fi
    
    # 创建管理脚本
    cat > "$MANAGER_FILE" << 'MANAGER_EOF'
#!/bin/bash

SERVICE_NAME="frps"
CONFIG_DIR="/etc/frp"
FRP_BIN="/usr/local/bin/frps"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 显示带颜色的消息
show_message() {
    case $1 in
        success) echo -e "${GREEN}✓ $2${NC}" ;;
        error) echo -e "${RED}✗ $2${NC}" ;;
        warning) echo -e "${YELLOW}⚠ $2${NC}" ;;
        info) echo -e "${BLUE}ℹ $2${NC}" ;;
    esac
}

# 检查root权限
check_root() {
    if [ "$(id -u)" != "0" ]; then
        show_message error "此操作需要root权限，请使用sudo运行"
        exit 1
    fi
}

# 检查服务状态
check_service_status() {
    if systemctl is-active --quiet $SERVICE_NAME; then
        return 0
    else
        return 1
    fi
}

# 显示服务状态
show_status() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║         Frp Server 状态监控         ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    
    # 显示服务状态
    echo "【服务状态】"
    systemctl status $SERVICE_NAME --no-pager -l | head -20
    echo ""
    
    # 显示配置文件位置
    echo "【配置文件】"
    echo "  $CONFIG_DIR/frps.ini"
    echo ""
    
    # 显示监听端口
    echo "【网络连接】"
    if command -v ss &>/dev/null; then
        ss -tlnp | grep -E "(frps|7000|7500)" || echo "  未找到frps相关监听端口"
    elif command -v netstat &>/dev/null; then
        netstat -tlnp | grep -E "(frps|7000|7500)" || echo "  未找到frps相关监听端口"
    else
        echo "  请安装ss或netstat工具查看端口"
    fi
    
    # 显示进程信息
    echo ""
    echo "【进程信息】"
    if pgrep -x "frps" >/dev/null; then
        ps aux | grep -E "frps" | grep -v grep
    else
        echo "  Frp进程未运行"
    fi
    
    # 显示配置摘要
    echo ""
    echo "【配置摘要】"
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        echo "  Dashboard地址: http://$(curl -s ifconfig.me || hostname -I | awk '{print $1}'):7500"
        grep -E "^(bind_port|dashboard_port|token|dashboard_user)" "$CONFIG_DIR/frps.ini" 2>/dev/null | while read line; do
            echo "  $line"
        done
    else
        echo "  配置文件不存在"
    fi
    echo ""
    echo "═══════════════════════════════════════"
}

# 重载服务配置
reload_config() {
    check_root
    show_message info "正在重载服务配置..."
    
    systemctl daemon-reload
    if systemctl restart $SERVICE_NAME; then
        show_message success "服务配置已重载并重启"
    else
        show_message error "服务重载失败"
    fi
}

# 启动服务
start_service() {
    check_root
    show_message info "正在启动Frp Server..."
    
    if systemctl start $SERVICE_NAME; then
        sleep 2
        if check_service_status; then
            show_message success "Frp Server 启动成功"
        else
            show_message error "Frp Server 启动失败"
        fi
    else
        show_message error "启动命令执行失败"
    fi
}

# 停止服务
stop_service() {
    check_root
    show_message info "正在停止Frp Server..."
    
    if systemctl stop $SERVICE_NAME; then
        sleep 1
        if ! check_service_status; then
            show_message success "Frp Server 已停止"
        else
            show_message error "Frp Server 停止失败"
        fi
    else
        show_message error "停止命令执行失败"
    fi
}

# 重启服务
restart_service() {
    check_root
    show_message info "正在重启Frp Server..."
    
    if systemctl restart $SERVICE_NAME; then
        sleep 2
        if check_service_status; then
            show_message success "Frp Server 重启成功"
        else
            show_message error "Frp Server 重启失败"
        fi
    else
        show_message error "重启命令执行失败"
    fi
}

# 查看配置文件
view_config() {
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        echo "╔══════════════════════════════════════╗"
        echo "║         Frp Server 配置文件         ║"
        echo "╚══════════════════════════════════════╝"
        echo ""
        cat "$CONFIG_DIR/frps.ini"
        echo ""
        echo "═══════════════════════════════════════"
    else
        show_message error "配置文件不存在: $CONFIG_DIR/frps.ini"
    fi
}

# 编辑配置文件
edit_config() {
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        # 备份当前配置
        local backup_file="$CONFIG_DIR/frps.ini.backup.$(date +%Y%m%d_%H%M%S)"
        cp -f "$CONFIG_DIR/frps.ini" "$backup_file"
        show_message info "配置文件已备份到: $backup_file"
        
        # 使用编辑器打开
        ${EDITOR:-vi} "$CONFIG_DIR/frps.ini"
        
        read -p "是否要重启服务使配置生效？(y/n): " restart_choice
        if [[ $restart_choice == "y" || $restart_choice == "Y" ]]; then
            restart_service
        else
            echo "配置已保存，但需要重启服务才能生效"
        fi
    else
        show_message error "配置文件不存在: $CONFIG_DIR/frps.ini"
    fi
}

# 查看日志
view_logs() {
    echo "╔══════════════════════════════════════╗"
    echo "║         Frp Server 运行日志         ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "按 Ctrl+C 退出日志查看"
    echo "───────────────────────────────────────"
    journalctl -u $SERVICE_NAME -f -n 50
}

# 重置配置文件
reset_config() {
    check_root
    echo "⚠ 警告：这将重置配置文件为默认值！"
    read -p "确定要继续吗？(输入 'yes' 确认): " confirm
    
    if [ "$confirm" != "yes" ]; then
        echo "操作已取消"
        return
    fi
    
    # 备份当前配置
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        local backup_file="$CONFIG_DIR/frps.ini.backup.$(date +%Y%m%d_%H%M%S)"
        cp -f "$CONFIG_DIR/frps.ini" "$backup_file"
        show_message info "旧配置已备份到: $backup_file"
    fi
    
    # 创建新配置
    cat > "$CONFIG_DIR/frps.ini" << 'EOF'
[common]
bind_port = 7000
token = your_secure_token_here
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin_password_here
enable_prometheus = true
log_level = info
log_max_days = 3
disable_log_color = false
EOF
    
    show_message success "配置文件已重置"
    echo "请编辑 $CONFIG_DIR/frps.ini 修改token和密码"
}

# 显示菜单
show_menu() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║      Frp Server 管理工具 v1.0      ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "  1. 查看服务状态"
    echo "  2. 启动服务"
    echo "  3. 停止服务"
    echo "  4. 重启服务"
    echo "  5. 重载服务配置"
    echo "  6. 查看配置文件"
    echo "  7. 编辑配置文件"
    echo "  8. 重置配置文件"
    echo "  9. 查看实时日志"
    echo " 10. 查看历史日志"
    echo " 11. 卸载Frp Server"
    echo "  0. 退出"
    echo ""
    echo "═══════════════════════════════════════"
}

# 卸载函数
uninstall_frps() {
    check_root
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║        卸载 Frp Server             ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "⚠ 警告：这将完全删除Frp Server！"
    echo ""
    
    read -p "确定要卸载Frp Server吗？(输入 'YES' 确认): " confirm
    
    if [ "$confirm" != "YES" ]; then
        echo "卸载已取消"
        return
    fi
    
    # 停止服务
    show_message info "停止服务..."
    systemctl stop $SERVICE_NAME 2>/dev/null
    systemctl disable $SERVICE_NAME 2>/dev/null
    
    # 删除服务文件
    rm -f /etc/systemd/system/$SERVICE_NAME.service
    
    # 重载systemd
    systemctl daemon-reload
    systemctl reset-failed 2>/dev/null
    
    # 删除二进制文件
    rm -f /usr/local/bin/frps
    
    # 删除配置文件（询问）
    read -p "是否删除配置文件目录 /etc/frp？(y/n): " del_config
    if [[ $del_config == "y" || $del_config == "Y" ]]; then
        rm -rf /etc/frp
    else
        echo "配置文件保留在 /etc/frp"
    fi
    
    # 删除安装目录
    read -p "是否删除安装目录 /usr/local/frp？(y/n): " del_install
    if [[ $del_install == "y" || $del_install == "Y" ]]; then
        rm -rf /usr/local/frp
    else
        echo "安装文件保留在 /usr/local/frp"
    fi
    
    # 删除管理脚本
    rm -f /usr/local/bin/frp_manager
    rm -f /usr/local/bin/frp 2>/dev/null
    
    echo ""
    echo "═══════════════════════════════════════"
    show_message success "Frp Server 已完全卸载"
    echo "═══════════════════════════════════════"
    exit 0
}

# 命令行参数处理
case "$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        show_status
        ;;
    reload)
        reload_config
        ;;
    config|view)
        view_config
        ;;
    edit)
        edit_config
        ;;
    log|logs)
        view_logs
        ;;
    reset)
        reset_config
        ;;
    uninstall|remove)
        uninstall_frps
        ;;
    *)
        if [ -t 0 ]; then
            # 交互式菜单
            while true; do
                show_menu
                read -p "请选择操作 [0-11]: " choice
                echo ""
                
                case $choice in
                    1) show_status;;
                    2) start_service;;
                    3) stop_service;;
                    4) restart_service;;
                    5) reload_config;;
                    6) view_config;;
                    7) edit_config;;
                    8) reset_config;;
                    9) view_logs;;
                    10) 
                        journalctl -u $SERVICE_NAME --no-pager -n 50
                        ;;
                    11) uninstall_frps;;
                    0) 
                        echo "感谢使用Frp Server管理工具！"
                        exit 0
                        ;;
                    *) echo "无效选择，请重新输入" ;;
                esac
                
                if [ "$choice" != "0" ] && [ "$choice" != "9" ]; then
                    echo ""
                    read -p "按回车键返回主菜单..."
                fi
            done
        else
            # 非交互式模式显示帮助
            echo "使用: frp_manager [command]"
            echo ""
            echo "可用命令:"
            echo "  start      启动服务"
            echo "  stop       停止服务"
            echo "  restart    重启服务"
            echo "  status     查看状态"
            echo "  reload     重载配置"
            echo "  config     查看配置"
            echo "  edit       编辑配置"
            echo "  log        查看实时日志"
            echo "  reset      重置配置"
            echo "  uninstall  卸载服务"
            echo ""
            echo "不带参数运行进入交互菜单"
            exit 1
        fi
        ;;
esac
MANAGER_EOF
    
    # 设置管理脚本权限
    chmod 755 "$MANAGER_FILE"
    
    # 创建软链接
    ln -sf "$MANAGER_FILE" "/usr/local/bin/frp"
    
    show_message success "管理脚本安装完成"
}

# 主安装流程
main() {
    clear
    echo "╔══════════════════════════════════════╗"
    echo "║     Frp Server 自动安装脚本 v1.0    ║"
    echo "╚══════════════════════════════════════╝"
    echo ""
    echo "本脚本将自动安装和配置 Frp Server"
    echo "安装目录: $INSTALL_DIR"
    echo "配置文件: $CONFIG_DIR/frps.ini"
    echo ""
    
    # 检查是否已安装
    if [ -f "$SERVICE_FILE" ]; then
        show_message warning "检测到Frp Server已安装！"
        echo ""
        echo "当前安装状态:"
        echo "  Service文件: $SERVICE_FILE"
        echo "  二进制文件: $FRP_BIN"
        echo ""
        
        read -p "是否重新安装？(y/N): " reinstall
        if [[ $reinstall != "y" && $reinstall != "Y" ]]; then
            echo "已取消重新安装"
            echo ""
            echo "使用 'frp' 命令管理已安装的服务"
            exit 0
        fi
        
        # 备份现有配置
        backup_config
    fi
    
    # 安装Frps
    install_frps
    
    # 安装管理脚本
    install_manager
    
    # 显示安装完成信息
    echo ""
    echo "═══════════════════════════════════════"
    show_message success "Frp Server 安装完成！"
    echo "═══════════════════════════════════════"
    echo ""
    echo "【基本信息】"
    echo "  Service名称: $SERVICE_NAME"
    echo "  安装目录: $INSTALL_DIR"
    echo "  配置文件: $CONFIG_DIR/frps.ini"
    echo ""
    
    echo "【管理命令】"
    echo "  frp               # 进入管理菜单"
    echo "  frp status        # 查看状态"
    echo "  frp start         # 启动服务"
    echo "  frp stop          # 停止服务"
    echo "  frp restart       # 重启服务"
    echo "  frp config         # 查看配置"
    echo "  frp edit          # 编辑配置"
    echo ""
    
    echo "【默认端口】"
    echo "  客户端连接端口: 7000"
    echo "  管理面板端口: 7500"
    echo ""
    
    # 显示当前配置
    if [ -f "$CONFIG_DIR/frps.ini" ]; then
        echo "【当前配置】"
        echo "  Dashboard地址: http://$(curl -s ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'):7500"
        grep -E "^(token|dashboard_user|dashboard_pwd)" "$CONFIG_DIR/frps.ini" 2>/dev/null | while read line; do
            echo "  $line"
        done
    fi
    
    echo ""
    echo "═══════════════════════════════════════"
    echo ""
    
    # 检查服务状态
    if check_service_status; then
        show_message success "Frp Server 正在运行"
    else
        show_message warning "Frp Server 未运行，请手动启动: systemctl start $SERVICE_NAME"
    fi
    
    # 询问是否进入管理菜单
    echo ""
    read -p "是否现在进入管理菜单？(Y/n): " enter_menu
    if [[ $enter_menu != "n" && $enter_menu != "N" ]]; then
        echo "启动管理菜单..."
        sleep 1
        bash "$MANAGER_FILE"
    else
        echo "安装完成！使用 'frp' 命令管理服务"
    fi
}

# 执行主函数
main "$@"