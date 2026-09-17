# 公网 HTTPS 部署

## Windows Server 原生部署（适合你的服务器）

Windows Server 不需要运行 Linux Compose。使用 Python 启动 API，再由 Caddy 负责 HTTPS：

1. 在阿里云安全组放行 TCP 80、443；TCP 5318 不要放行。Windows 防火墙也只允许 80/443：

   ```powershell
   New-NetFirewallRule -DisplayName 'Richeng HTTPS' -Direction Inbound -Protocol TCP -LocalPort 80,443 -Action Allow
   ```

2. 安装 Python 3.10+，确认 `python --version` 可用；从 Caddy 官网下载 Windows `caddy.exe`，放入 PATH，并确认 `caddy version` 可用。启动脚本会自动安装 `server/requirements.txt` 中的 WebSocket 依赖。

3. 在服务器创建 `C:\richeng`，把项目中的 `server` 和 `deploy` 文件夹上传到 `C:\richeng`。复制 `deploy\.env.example` 为 `deploy\.env`，填写域名、AI 和 SMTP 配置。不要把 `.env` 发到聊天或提交到 Git。

4. 在管理员 PowerShell 中启动：

   ```powershell
   Set-Location C:\richeng\deploy
   .\windows-start.ps1
   Invoke-RestMethod https://api.example.com/health
   ```

   `windows-start.ps1` 会隐藏启动 Python 和 Caddy，并把日志写入 `deploy\runtime`。Caddy 会在 `API_DOMAIN` 的 DNS A 记录指向本机公网 IP、且 80/443 可访问后自动申请证书。

5. 停止服务：

   ```powershell
   .\windows-stop.ps1
   ```

   生产环境建议在“任务计划程序”创建系统启动任务，执行 `powershell.exe -ExecutionPolicy Bypass -File C:\richeng\deploy\windows-start.ps1`，并设置“无论用户是否登录都运行”。

客户端“账号与云同步”填写 `https://api.example.com`。Windows Server 的 5318 端口只监听本机，公网请求全部经过 Caddy HTTPS。

## 阿里云 ECS 快速部署

以下以 Ubuntu 22.04/24.04 ECS 为例。先在 ECS 安全组放行 TCP 80、443；TCP 22 只允许你的办公公网 IP。若启用系统防火墙，再执行 `sudo ufw allow 22/tcp && sudo ufw allow 80/tcp && sudo ufw allow 443/tcp && sudo ufw enable`。

在阿里云 DNS 为 `api.example.com` 添加 A 记录，值填写 ECS 的固定公网 IP。DNS 生效后，在本机 PowerShell 上传项目目录：

```powershell
ssh root@你的公网IP "mkdir -p /opt/richeng"
scp -r .\server root@你的公网IP:/opt/richeng/
scp -r .\deploy root@你的公网IP:/opt/richeng/
```

SSH 登录 ECS，安装 Docker 并启动服务：

```bash
sudo apt update
sudo apt install -y ca-certificates curl
curl -fsSL https://get.docker.com | sudo sh
sudo systemctl enable --now docker
cd /opt/richeng/deploy
cp .env.example .env
nano .env
docker compose up -d --build
docker compose ps
curl https://api.example.com/health
```

编辑 `.env` 时将 `API_DOMAIN` 改为实际 API 域名，填入 AI 和 SMTP 凭据；不要在聊天、Git 或 shell 历史中粘贴密钥。Caddy 会在 80/443 可访问且 DNS 已生效后自动申请 HTTPS 证书。安装包客户端的“账号与云同步”地址填写 `https://api.example.com`。

1. 准备一台安装 Docker Compose 的 Linux 云服务器，并让 `API_DOMAIN` 的 A/AAAA 记录指向该服务器。
2. 复制 `.env.example` 为 `.env`，填写域名、OpenAI 兼容服务密钥和 SMTP 凭据；`.env` 不应提交到版本库。
3. 在本目录运行 `docker compose up -d --build`。Caddy 会在域名可解析且 80/443 端口开放后自动申请 HTTPS 证书。
4. 用 `https://API_DOMAIN/health` 检查服务；客户端“账号与云同步”填写 `https://API_DOMAIN`。

部署前请在防火墙仅开放 TCP 80 和 443，不要开放容器的 5318 端口。备份 `richeng_data` 卷，并定期检查 SMTP、AI 用量和 HTTPS 证书状态。
