#!/bin/bash

# 1. 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 用户或 sudo 运行此脚本！"
    exit 1
fi

# ==================== 配置区 ====================
# 👉 路径固定为 /opt/payplus（重启绝对不会丢失，卸载极度方便）
INSTALL_DIR="/opt/payplus"
GIT_URL="https://github.com/oomdwg/payplus.git"
SERVICE_NAME="gptplus"
# ================================================

echo "========================================="
echo "  🚀 开始一键部署 Python Web 应用..."
echo "  📌 固定安装目录: ${INSTALL_DIR}"
echo "========================================="

# 2. 创建目标安装目录
mkdir -p "$INSTALL_DIR"

# 3. 自动安装基础系统依赖
echo "📦 正在检查并安装基础系统依赖..."
apt update -y
apt install -y git python3 python3-pip python3.11-venv

# 4. 克隆项目代码到固定路径 /opt/payplus
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

# 5. 在 /opt/payplus 下创建 Python 虚拟环境
VENV_DIR="$INSTALL_DIR/venv"
if [ ! -d "$VENV_DIR" ]; then
    python3 -m venv "$VENV_DIR"
fi

# 6. 安装 Python 依赖包
echo "🔄 正在安装 Python 依赖包..."
source "$VENV_DIR/bin/activate"
"$VENV_DIR/bin/pip" install --upgrade pip -q
"$VENV_DIR/bin/pip" install flask flask-cors gunicorn curl-cffi httpx

# 7. 写入启动脚本 /opt/payplus/run.sh
cat > "$INSTALL_DIR/run.sh" << EOF
#!/bin/bash
cd "$INSTALL_DIR/backend"   
source "$INSTALL_DIR/venv/bin/activate"         
exec gunicorn -w 4 -b 127.0.0.1:8000 app:app
EOF
chmod +x "$INSTALL_DIR/run.sh"

# 8. 写入 systemd 服务配置（指向 /opt/payplus）
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

# 9. 启动服务并设置开机自启
echo "🔄 正在启动后台服务..."
systemctl daemon-reload
systemctl enable ${SERVICE_NAME}
systemctl restart ${SERVICE_NAME}

echo "========================================="
echo "  🎉 部署成功！项目已在后台完美运行。"
echo "========================================="
echo "💡 本地监听端口: 127.0.0.1:8000"
echo "👉 您现在可以直接在宝塔或 Nginx 中，将您的域名反向代理至: http://127.0.0.1:8000"
echo ""
echo "📝 常用管理命令:"
echo "   - 查看运行状态: systemctl status $SERVICE_NAME"
echo "   - 重启后台服务: systemctl restart $SERVICE_NAME"
echo "   - 停止后台服务: systemctl stop $SERVICE_NAME"
echo "   - 查看运行日志: journalctl -u $SERVICE_NAME -f"
echo "========================================="
