#!/bin/bash

# 1. 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 用户或 sudo 运行此脚本！"
    exit 1
fi

# ==================== 配置区 ====================
INSTALL_DIR="/opt/payplus"
GIT_URL="https://github.com/oomdwg/payplus.git"
SERVICE_NAME="gptplus"
DEFAULT_PORT=8000
# ================================================

echo "========================================="
echo "  🚀 开始一键部署 Python Web 应用..."
echo "  📌 固定安装目录: ${INSTALL_DIR}"
echo "========================================="

# 2. 安装 net-tools/lsof 辅助端口检测
echo "📦 正在检查并安装基础系统依赖..."
apt update -y
PYTHON_VERSION=$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
apt install -y git python3 python3-pip python${PYTHON_VERSION}-venv lsof net-tools

# 3. 智能检测 8000 端口
PORT=$DEFAULT_PORT

# 检查端口是否被占用
is_port_in_use() {
    lsof -i:"$1" >/dev/null 2>&1 || netstat -tuln | grep -q ":$1 "
}

if is_port_in_use "$PORT"; then
    echo ""
    echo "⚠️  检测到默认端口 ${PORT} 已被其他程序占用！"
    read -p "👉 请输入需要使用的新端口号 [直接回车默认 8080]: " USER_PORT
    PORT=${USER_PORT:-8080}

    # 循环校验用户输入的端口号，直到可用为止
    while is_port_in_use "$PORT" || [[ ! "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; do
        echo "❌ 端口 ${PORT} 无效或仍被占用！"
        read -p "👉 请重新输入可用的端口号 (1-65535): " PORT
    done
    echo "✅ 已选择端口: ${PORT}"
else
    echo "✅ 默认端口 ${PORT} 空闲，将直接使用该端口。"
fi

# 4. 创建目标安装目录
mkdir -p "$INSTALL_DIR"

# 5. 克隆项目代码到固定路径 /opt/payplus
echo "📥 正在克隆项目代码..."
git clone --depth=1 "$GIT_URL" /tmp/payplus_temp
if [ $? -eq 0 ]; then
    cp -r /tmp/payplus_temp/* "$INSTALL_DIR/" 2>/dev/null || true
    cp -r /tmp/payplus_temp/.* "$INSTALL_DIR/" 2>/dev/null || true
    rm -rf /tmp/payplus_temp
    echo "✅ 代码克隆成功！"
else
    echo "❌ 错误: Git 克隆失败，请检查服务器与 GitHub 的网络连接！"
    exit 1
fi

# 6. 创建虚拟环境
echo "📦 正在创建 Python 虚拟环境..."
python3 -m venv "$INSTALL_DIR/venv"
if [ $? -ne 0 ]; then
    echo "❌ 虚拟环境创建失败！"
    exit 1
fi

# 7. 安装依赖
echo "🔄 正在安装 Python 依赖包..."
"$INSTALL_DIR/venv/bin/pip" install --upgrade pip -q
"$INSTALL_DIR/venv/bin/pip" install flask flask-cors gunicorn curl-cffi httpx
if [ $? -ne 0 ]; then
    echo "❌ 依赖安装失败！"
    exit 1
fi

# 8. 写入后台运行脚本 /opt/payplus/run.sh
cat > "$INSTALL_DIR/run.sh" << EOF
 
#!/bin/bash
cd "$INSTALL_DIR/backend"
exec "$INSTALL_DIR/venv/bin/gunicorn" -w 4 -b 127.0.0.1:${PORT} app:app
EOF

chmod +x "$INSTALL_DIR/run.sh"

# 9. 写入 systemd 服务配置
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=My Flask Application Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR/backend
ExecStart=/bin/bash $INSTALL_DIR/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 10. 写入快捷管理指令 /usr/local/bin/payplus (快捷菜单)
cat > /usr/local/bin/payplus << 'EOF'
#!/bin/bash

SERVICE_NAME="gptplus"
INSTALL_DIR="/opt/payplus"

# 获取当前运行端口
get_current_port() {
    if [ -f "$INSTALL_DIR/run.sh" ]; then
        grep -oP '127\.0\.0\.1:\K[0-9]+' "$INSTALL_DIR/run.sh" || echo "未知"
    else
        echo "未安装"
    fi
}

show_menu() {
    CURRENT_PORT=$(get_current_port)
    clear
    echo "========================================="
    echo "          PayPlus 项目管理面板           "
    echo "========================================="
    echo "  📌 当前运行端口: ${CURRENT_PORT}"
    echo "-----------------------------------------"
    echo "  1. 查看运行状态"
    echo "  2. 启动后台服务"
    echo "  3. 停止后台服务"
    echo "  4. 重启后台服务"
    echo "  5. 查看运行日志"
    echo "  6. 修改运行端口"
    echo "  7. 彻底卸载项目"
    echo "  0. 退出面板"
    echo "========================================="
    read -p "请输入数字选项 [0-7]: " choice

    case $choice in
        1)
            systemctl status $SERVICE_NAME
            ;;
        2)
            systemctl start $SERVICE_NAME
            echo "✅ 服务已启动！"
            ;;
        3)
            systemctl stop $SERVICE_NAME
            echo "🛑 服务已停止！"
            ;;
        4)
            systemctl restart $SERVICE_NAME
            echo "🔄 服务已重启！"
            ;;
        5)
            journalctl -u $SERVICE_NAME -f -n 50
            ;;
        6)
            read -p "👉 请输入想要更换的新端口号 (1-65535): " NEW_PORT
            if [[ "$NEW_PORT" =~ ^[0-9]+$ ]] && [ "$NEW_PORT" -ge 1 ] && [ "$NEW_PORT" -le 65535 ]; then
                if lsof -i:$NEW_PORT >/dev/null 2>&1 || netstat -tuln | grep -q ":$NEW_PORT "; then
                    echo "❌ 错误: 端口 $NEW_PORT 已被其他应用占用，修改失败！"
                else
                    sed -i "s/127\.0\.0\.1:[0-9]*/127\.0\.0\.1:$NEW_PORT/g" "$INSTALL_DIR/run.sh"
                    echo "🔄 正在使用新端口 $NEW_PORT 重启服务..."
                    systemctl restart $SERVICE_NAME
                    echo "✅ 端口修改成功！目前监听端口: 127.0.0.1:$NEW_PORT"
                fi
            else
                echo "❌ 端口输入不合法！"
            fi
            ;;
        7)
            read -p "⚠️ 确定要彻底卸载项目吗？[y/N]: " confirm
            if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
                systemctl stop $SERVICE_NAME
                systemctl disable $SERVICE_NAME
                rm -f /etc/systemd/system/${SERVICE_NAME}.service
                systemctl daemon-reload
                rm -rf $INSTALL_DIR
                rm -f /usr/local/bin/payplus
                echo "✅ 项目已彻底卸载干净！"
                exit 0
            else
                echo "❌ 已取消卸载操作。"
            fi
            ;;
        0)
            exit 0
            ;;
        *)
            echo "❌ 无效选项，请输入正确的数字！"
            ;;
    esac
}

show_menu
EOF

# 赋予快捷指令可执行权限
chmod +x /usr/local/bin/payplus

# 11. 启动服务并设置开机自启
echo "🔄 正在启动后台服务..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

echo "========================================="
echo "  🎉 部署成功！项目已在后台完美运行。"
echo "========================================="
echo "💡 本地监听端口: 127.0.0.1:${PORT}"
echo "👉 您现在可以直接在宝塔或 Nginx 中，将您的域名反向代理至: http://127.0.0.1:${PORT}"
echo ""
echo "🔥 快捷管理面板工具已就绪！"
echo "👉 今后只需在终端输入: payplus"
echo "========================================="
