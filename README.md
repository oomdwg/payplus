# payplus
GPT 订单
本地监听端口: 127.0.0.1:8000
👉 您现在可以直接在宝塔或 Nginx 中，将您的域名反向代理至: http://127.0.0.1:8000

📝 常用管理命令:
   - 查看运行状态: systemctl status gptplus
   - 重启后台服务: systemctl restart gptplus
   - 停止后台服务: systemctl stop gptplus
   - 查看运行日志: journalctl -u gptplus -f

### 🗑️ 彻底卸载说明

如果您需要从服务器上彻底卸载此项目，请在终端复制并运行以下一键卸载命令：

```bash
systemctl stop gptplus && systemctl disable gptplus && rm -f /etc/systemd/system/gptplus.service && systemctl daemon-reload && rm -rf /www/wwwroot/gplus.gpt9.de && rm -f install.sh && echo "卸载完成！"
