#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 用户或 sudo 运行此脚本！"
    exit 1
fi

# 核心修改：动态获取当前脚本执行时所在的绝对路径
INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"

GIT_URL="https://github.com/oomdwg/payplus.git"
SERVICE_NAME="gptplus"

echo "========================================="
echo "  🚀 开始一键部署 Python Web 应用..."
echo "========================================="

# 1. 自动安装基础依赖环境
echo "📦 正在检查并安装基础系统依赖..."
apt update -y
apt install -y git python3 python3-pip python3.11-venv

# 2. 克隆项目代码
echo "📥 正在克隆项目代码..."
# 先克隆到临时目录，再强行覆盖过来，完美解决“目录非空”无法克隆的问题
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

# 3. 创建虚拟环境
VENV_DIR="venv"
if [ ! -d "$VENV_DIR" ]; then
    echo "📦 正在创建 Python 虚拟环境..."
    python3 -m venv "$VENV_DIR"
fi

# 4. 激活虚拟环境并安装 Python 依赖
echo "🔄 正在安装 Python 依赖包..."
source "$VENV_DIR"/bin/activate
./"$VENV_DIR"/bin/pip install --upgrade pip -q
# 👉 把运行所需的 flask 和 flask_cors 完整加进来
./"$VENV_DIR"/bin/pip install flask flask-cors gunicorn curl-cffi httpx

# 5. 写入一键启动脚本 (利用变量，动态写入当前实际的路径)
cat > "$INSTALL_DIR/run.sh" << EOF
#!/bin/bash
# 1. 切换到当前网站目录下的 backend
cd "$INSTALL_DIR/backend"   
# 2. 激活当前网站目录下的虚拟环境
source "$INSTALL_DIR/venv/bin/activate"         
# 3. 启动 Gunicorn
exec gunicorn -w 4 -b 127.0.0.1:8000 app:app
EOF
chmod +x "$INSTALL_DIR/run.sh"

# 6. 写入 systemd 服务配置
cat > /etc/systemd/system/gptplus.service << EOF
[Unit]
Description=My Flask Application Service
After=network.target

[Service]
Type=simple
User=root
# 👉 动态指向当前实际的安装目录 backend
WorkingDirectory=$INSTALL_DIR/backend
# 👉 动态指向当前实际的 run.sh 路径
ExecStart=/bin/bash $INSTALL_DIR/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

# 7. 启动服务并设置开机自启
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
