#!/bin/bash

# 确保以 root 权限运行
if [ "$EUID" -ne 0 ]; then
    echo "❌ 错误: 请使用 root 用户或 sudo 运行此脚本！"
    exit 1
fi

# 定义项目安装目录和 Git 地址
INSTALL_DIR="/usr/local/my-flask-app"
# ⚠️ 请把下面这行修改为你自己的 GitHub 仓库克隆地址！
GIT_URL="https://github.com/你的用户名/你的仓库名.git"
SERVICE_NAME="my-flask-app"

echo "========================================="
echo "  🚀 开始一键部署 Python Web 应用..."
echo "========================================="

# 1. 自动安装基础依赖环境
echo "📦 正在检查并安装基础系统依赖..."
apt update -y
apt install -y git python3 python3-pip python3.11-venv

# 2. 拉取/更新代码仓库
if [ -d "$INSTALL_DIR" ]; then
    echo "🔄 检测到项目已存在，正在拉取最新代码..."
    cd "$INSTALL_DIR"
    git fetch --all
    git reset --hard origin/main || git reset --hard origin/master
else
    echo "📥 正在克隆项目代码到: $INSTALL_DIR ..."
    git clone "$GIT_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
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
pip install --upgrade pip -q
pip install gunicorn curl-cffi httpx

# 5. 写入一键启动脚本 (方便后续手动管理)
cat > run.sh << 'EOF'
#!/bin/bash
cd /usr/local/my-flask-app
source venv/bin/activate
# ⚠️ 注意：下面的 app:app 请根据你的实际启动文件名修改（例如 main:app）
exec gunicorn -w 4 -b 127.0.0.1:8000 app:app
EOF
chmod +x run.sh

# 6. 将程序注册为 Systemd 系统服务 (实现后台运行、开机自启)
echo "⚙️  正在将程序注册为系统服务..."
cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=My Flask Application Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/run.sh
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
