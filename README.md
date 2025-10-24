# acme-reloader

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**开箱即用的 acme.sh Docker 证书自动化解决方案**

一个完整的解决方案，让 acme.sh 在 Docker 容器中自动申请和续签证书，并在证书更新后自动重载宿主机或其他容器的服务（如 Nginx、Caddy 等）。

## ✨ 为什么选择 acme-reloader？

- 🚀 **开箱即用**：克隆、安装、启动，三步搞定
- 🐳 **完美容器化**：acme.sh 运行在 Docker，Web 服务器在宿主机或其他容器
- 🔄 **自动化一切**：证书自动续签，服务自动重载，无需人工干预
- 🛡️ **健壮可靠**：超时重试、错误处理、详细日志
- 📝 **配置简单**：只需配置一条重启命令即可

## 🎯 使用场景

这个项目专为以下场景设计：

- acme.sh 运行在 Docker 容器中
- Nginx/Caddy 运行在宿主机上
- 需要在证书更新后自动重载 Web 服务器

**架构图：**
```
┌─────────────────────┐         ┌──────────────────┐
│  acme.sh 容器       │  socket │   宿主机          │
│  - 自动续签证书      │◄───────►│  - Nginx/Caddy   │
│  - 调用 reloadcmd   │  通信   │  - 自动重载       │
└─────────────────────┘         └──────────────────┘
```

## 🚀 快速开始

### 三步部署

```bash
# 1. 克隆项目
git clone https://github.com/AptS-1547/acme-docker-reloader.git
cd acme-reloader

# 2. 运行安装脚本（会提示输入重载命令）
sudo ./install.sh

# 3. 启动 acme.sh 容器
docker-compose up -d
```

就这么简单！🎉

### 申请证书

```bash
# 进入容器
docker exec -it acme.sh ash

# 首次使用：注册账号
acme.sh --register-account -m your@email.com
acme.sh --set-default-ca --server letsencrypt

# 申请证书（以 Cloudflare DNS 验证为例）
export CF_Token="your_cloudflare_token"
export CF_Zone_ID="your_zone_id"
acme.sh --issue -d example.com -d *.example.com --dns dns_cf

# 安装证书并设置自动重载
acme.sh --install-cert -d example.com \
  --cert-file /ssl/example.com/cert.pem \
  --key-file /ssl/example.com/key.pem \
  --fullchain-file /ssl/example.com/fullchain.pem \
  --reloadcmd "bash /acme-reloader.sh"
```

### 配置 Web 服务器

证书文件位于项目的 `ssl/` 目录下，配置你的 Nginx：

```nginx
server {
    listen 443 ssl;
    server_name example.com;

    # 使用证书的绝对路径
    ssl_certificate /path/to/acme-reloader/ssl/example.com/fullchain.pem;
    ssl_certificate_key /path/to/acme-reloader/ssl/example.com/key.pem;

    # 其他配置...
}
```

重载 Nginx：
```bash
sudo nginx -t
sudo systemctl reload nginx
```

完成！🎊 证书会自动续签，续签后自动重载 Nginx。

## 📁 项目结构

```
acme-reloader/
├── bin/                          # 可执行脚本
│   ├── acme-reloader.sh          # 容器端客户端
│   └── acme-reloader-host.sh     # 宿主机端守护进程
├── lib/                          # 库模块
│   ├── logger.sh                 # 日志模块
│   ├── config.sh                 # 配置解析
│   ├── ipc.sh                    # 进程间通信
│   └── service.sh                # 服务管理
├── config/                       # 配置文件
│   └── config.yml                # 主配置（安装时自动生成）
├── ssl/                          # 证书存储（自动创建）
├── acme-config/                  # acme.sh 配置（自动创建）
├── acme-reloader/                # Socket 通信目录（自动创建）
├── logs/                         # 日志目录（自动创建）
├── docker-compose.yml            # 核心配置文件
├── install.sh                    # 一键安装脚本
├── uninstall.sh                  # 一键卸载脚本
└── README.md                     # 本文件
```

## 🔧 工作原理

1. **安装阶段**：
   - `install.sh` 在当前目录初始化项目
   - 配置 systemd 服务运行 `acme-reloader-host.sh`
   - 创建必要的目录和配置文件

2. **运行阶段**：
   - `acme-reloader-host.sh` 在宿主机作为守护进程运行
   - 创建命名管道（socket）等待通知

3. **证书更新**：
   - acme.sh 容器中的证书到期自动续签
   - 续签完成后调用 `reloadcmd`（即容器内的 `/acme-reloader.sh`）
   - 脚本通过 socket 通知宿主机守护进程
   - 守护进程执行配置的重载命令（如 `systemctl reload nginx`）
   - 返回执行结果

## ⚙️ 配置说明

配置文件在 `config/config.yml`，安装时会自动生成。

### 核心配置

```yaml
services:
  main:
    command: "systemctl reload nginx"  # 你的重载命令
    enabled: true
    timeout: 15
```

### 多服务配置

如果需要同时重载多个服务：

```yaml
services:
  nginx:
    command: "systemctl reload nginx"
    enabled: true

  caddy:
    command: "systemctl reload caddy"
    enabled: true
```

### Docker 容器服务

如果你的 Nginx 也在 Docker 中：

```yaml
services:
  nginx_container:
    command: "docker exec nginx nginx -s reload"
    enabled: true
```

## 🐛 故障排查

### 检查服务状态

```bash
# 检查宿主机守护进程
sudo systemctl status acme-reloader-host

# 查看日志
sudo journalctl -u acme-reloader-host -f
tail -f ./logs/acme-reloader.log
```

### 手动测试重载

```bash
# 在容器内测试
docker exec acme.sh bash /acme-reloader.sh

# 在宿主机测试
./bin/acme-reloader.sh
```

### 常见问题

#### Socket not found

**问题**：容器无法连接到宿主机

**解决**：
1. 检查守护进程是否运行：`sudo systemctl status acme-reloader-host`
2. 检查 socket 是否存在：`ls -la ./acme-reloader/socket/`
3. 重启守护进程：`sudo systemctl restart acme-reloader-host`

#### 服务重载失败

**问题**：命令执行失败

**解决**：
1. 查看详细日志：`tail -f ./logs/acme-reloader.log`
2. 手动测试命令：`systemctl reload nginx`
3. 检查配置文件：`cat config/config.yml`
4. 确认有 sudo 权限

更多故障排查请查看 [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)

## 📚 详细文档

- [安装指南](docs/INSTALL.md) - 详细的安装步骤和配置说明
- [配置说明](docs/CONFIG.md) - 完整的配置选项文档
- [故障排查](docs/TROUBLESHOOTING.md) - 常见问题和解决方案

## 🔄 升级

```bash
# 1. 备份配置
cp config/config.yml ~/config.yml.bak

# 2. 停止服务
sudo systemctl stop acme-reloader-host
docker-compose down

# 3. 拉取最新代码
git pull

# 4. 重新安装（会保留现有配置）
sudo ./install.sh

# 5. 重启服务
sudo systemctl start acme-reloader-host
docker-compose up -d
```

## 🗑️ 卸载

```bash
sudo ./uninstall.sh
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License

## 👤 作者

AptS:1547

## 🙏 致谢

- [acme.sh](https://github.com/acmesh-official/acme.sh) - 出色的 ACME 客户端
- 所有贡献者

## ⭐ Star History

如果这个项目对你有帮助，欢迎给个 Star！

---

**快速链接**：[安装指南](docs/INSTALL.md) | [配置说明](docs/CONFIG.md) | [故障排查](docs/TROUBLESHOOTING.md) | [提交 Issue](https://github.com/AptS-1547/acme-docker-reloader/issues)
