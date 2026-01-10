#!/bin/bash
PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH
LANG=en_US.UTF-8

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "错误：此脚本必须使用root权限运行！" >&2
    exit 1
fi

# 系统检测
if [ -f /etc/redhat-release ]; then
    SYSTEM="centos"
elif [ -f /etc/debian_version ]; then
    SYSTEM="debian"
else
    echo "错误：不支持的操作系统！" >&2
    exit 1
fi

# 安装必要工具
if [ "$SYSTEM" = "centos" ]; then
    yum install -y wget tar
else
    apt-get update
    apt-get install -y wget tar
fi

# 下载和解压Frp
VERSION="0.43.0"
URL="https://github.com/fatedier/frp/releases/download/v${VERSION}/frp_${VERSION}_linux_amd64.tar.gz"
TMP_DIR=$(mktemp -d)
wget -qO "$TMP_DIR/frp.tar.gz" "$URL"
tar xzf "$TMP_DIR/frp.tar.gz" -C "$TMP_DIR"

# 创建目录结构
INSTALL_DIR="/usr/local/frp"
mkdir -p $INSTALL_DIR/{bin,conf,logs}
cp $TMP_DIR/frp_${VERSION}_linux_amd64/frpc $INSTALL_DIR/bin/
chmod +x $INSTALL_DIR/bin/frpc

# 复制服务端文件以便管理
cp $TMP_DIR/frp_${VERSION}_linux_amd64/frps $INSTALL_DIR/bin/
chmod +x $INSTALL_DIR/bin/frps

# 创建配置文件模板
cat > $INSTALL_DIR/conf/frpc.ini << EOF
[common]
server_addr = 127.0.0.1
server_port = 7000
token = your_token_here

[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = 22
remote_port = 6000
EOF

# 创建服务端配置文件模板
cat > $INSTALL_DIR/conf/frps.ini << EOF
[common]
bind_port = 7000
token = your_token_here

dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin
EOF

# 创建systemd服务
cat > /etc/systemd/system/frpc.service << EOF
[Unit]
Description=Frp Client Service
After=network.target

[Service]
Type=simple
User=nobody
Restart=on-failure
RestartSec=5s
ExecStart=$INSTALL_DIR/bin/frpc -c $INSTALL_DIR/conf/frpc.ini
ExecReload=/bin/kill -s HUP \$MAINPID
StandardOutput=file:$INSTALL_DIR/logs/frpc.log
StandardError=file:$INSTALL_DIR/logs/frpc_error.log

[Install]
WantedBy=multi-user.target
EOF

# 清理临时文件
rm -rf "$TMP_DIR"

# 启动服务
systemctl daemon-reload
systemctl enable frpc
systemctl start frpc

# 创建管理脚本
cat > /usr/local/bin/frp << 'EOF'
#!/bin/bash

INSTALL_DIR="/usr/local/frp"
SERVICE_TYPE="client"

# 检测当前是server还是client
if systemctl is-active --quiet frps 2>/dev/null; then
    SERVICE_TYPE="server"
fi

show_menu() {
    echo "=============================="
    echo " Frp 服务管理脚本 "
    echo "=============================="
    echo "当前服务模式: $SERVICE_TYPE"
    echo "1. 启动 frp 服务"
    echo "2. 停止 frp 服务"
    echo "3. 重启 frp 服务"
    echo "4. 查看服务状态"
    echo "5. 重载服务配置"
    echo "6. 显示安装目录"
    echo "7. 卸载 frp 服务"
    echo "8. 退出"
    echo "=============================="
}

# 根据服务类型执行操作
frp_action() {
    local action=$1
    local service_name="frpc"
    
    if [ "$SERVICE_TYPE" = "server" ]; then
        service_name="frps"
    fi
    
    systemctl $action $service_name
}

# 卸载frp服务
uninstall_frp() {
    echo "警告：此操作将卸载Frp服务！"
    read -p "确定要卸载Frp服务吗？(y/N): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "卸载操作已取消"
        return
    fi
    
    echo "正在停止服务..."
    
    # 停止并禁用服务
    if systemctl is-active --quiet frps 2>/dev/null; then
        systemctl stop frps
        systemctl disable frps
    fi
    
    if systemctl is-active --quiet frpc 2>/dev/null; then
        systemctl stop frpc
        systemctl disable frpc
    fi
    
    # 删除服务文件
    if [ -f /etc/systemd/system/frps.service ]; then
        rm -f /etc/systemd/system/frps.service
    fi
    
    if [ -f /etc/systemd/system/frpc.service ]; then
        rm -f /etc/systemd/system/frpc.service
    fi
    
    # 删除安装目录
    if [ -d "$INSTALL_DIR" ]; then
        rm -rf "$INSTALL_DIR"
    fi
    
    # 删除管理脚本
    rm -f /usr/local/bin/frp
    
    # 重载systemd
    systemctl daemon-reload
    
    echo "=============================="
    echo "Frp 服务已卸载完成！"
    echo "=============================="
    echo "已删除以下内容："
    echo "1. Frp 安装目录: $INSTALL_DIR"
    echo "2. systemd 服务文件"
    echo "3. 管理脚本"
    echo "=============================="
}

# 主程序
case $1 in
    [1-8]) 
        choice=$1
        ;;
    *)
        show_menu
        read -p "请输入选项 (1-8): " choice
        ;;
esac

case $choice in
    1)
        frp_action "start"
        echo "服务已启动"
        ;;
    2)
        frp_action "stop"
        echo "服务已停止"
        ;;
    3)
        frp_action "restart"
        echo "服务已重启"
        ;;
    4)
        frp_action "status"
        ;;
    5)
        systemctl daemon-reload
        echo "服务配置已重载"
        ;;
    6)
        echo "=============================="
        echo "Frp 安装信息"
        echo "=============================="
        echo "安装目录: $INSTALL_DIR"
        echo "配置文件: $INSTALL_DIR/conf"
        echo "日志文件: $INSTALL_DIR/logs"
        echo "可执行文件: $INSTALL_DIR/bin"
        echo ""
        echo "配置文件列表:"
        ls -la $INSTALL_DIR/conf/
        echo ""
        echo "当前服务状态:"
        if [ "$SERVICE_TYPE" = "server" ]; then
            systemctl status frps --no-pager
        else
            systemctl status frpc --no-pager
        fi
        echo "=============================="
        ;;
    7)
        uninstall_frp
        ;;
    8)
        exit 0
        ;;
    *)
        echo "无效选项！"
        exit 1
        ;;
esac
EOF

chmod +x /usr/local/bin/frp

echo "=============================="
echo "Frpc 安装完成！"
echo "=============================="
echo "安装信息:"
echo "- 安装目录: $INSTALL_DIR"
echo "- 配置文件: $INSTALL_DIR/conf/frpc.ini"
echo "- 日志目录: $INSTALL_DIR/logs"
echo ""
echo "管理命令:"
echo "- 基本管理: frp"
echo "- 直接命令: frp 1 (启动), frp 2 (停止), frp 3 (重启)"
echo "- 查看状态: frp 4"
echo "- 卸载: frp 7"
echo ""
echo "请修改配置文件: $INSTALL_DIR/conf/frpc.ini"
echo "配置服务器地址、端口和token后执行: systemctl restart frpc"
echo "=============================="
echo "配置示例:"
echo "  server_addr = 服务器IP地址"
echo "  server_port = 7000"
echo "  token = 服务器设置的token"
echo "=============================="