#!/bin/bash

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

show_menu() {
    echo "=============================="
    echo " Frp 服务管理脚本 "
    echo "=============================="
    echo "1. 启动 frp 服务"
    echo "2. 停止 frp 服务"
    echo "3. 重启 frp 服务"
    echo "4. 查看服务状态"
    echo "5. 重载服务配置"
    echo "6. 显示安装目录"
    echo "7. 退出"
    echo "=============================="
}

case $1 in
    [1-7]) 
        choice=$1
        ;;
    *)
        show_menu
        read -p "请输入选项 (1-7): " choice
        ;;
esac

case $choice in
    1)
        systemctl start frpc
        echo "服务已启动"
        ;;
    2)
        systemctl stop frpc
        echo "服务已停止"
        ;;
    3)
        systemctl restart frpc
        echo "服务已重启"
        ;;
    4)
        systemctl status frpc
        ;;
    5)
        systemctl daemon-reload
        echo "服务配置已重载"
        ;;
    6)
        echo "Frp 安装目录: $INSTALL_DIR"
        echo "配置文件目录: $INSTALL_DIR/conf"
        echo "日志文件目录: $INSTALL_DIR/logs"
        ;;
    7)
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
echo "管理命令: frp"
echo "配置文件: $INSTALL_DIR/conf/frpc.ini"
echo "=============================="