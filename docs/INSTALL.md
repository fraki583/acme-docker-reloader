# 安装指南

本文档提供 acme-reloader 的详细安装说明。

## 系统要求

### 最低要求

- **操作系统**: Linux（推荐 Ubuntu 20.04+, Debian 10+, CentOS 7+）
- **Shell**: Bash 4.0+
- **权限**: root 或 sudo 权限
- **可选**: systemd（用于服务管理）
- **可选**: Docker（如果使用容器化的 acme.sh）

### 依赖检查

在安装前，确保系统已安装以下工具：

```bash
# 检查 bash 版本
bash --version  # 应该 >= 4.0

# 检查 systemd（可选）
systemctl --version

# 检查 Docker（可选）
docker --version
```

## 安装方式

### 方式 1：自动安装（推荐）

使用提供的安装脚本进行一键安装：

```bash
# 1. 克隆仓库
git clone https://github.com/AptS-1547/acme-docker-reloader.git
cd acme-reloader

# 2. 运行安装脚本
sudo ./install.sh
```

#### 安装流程说明

安装脚本会引导你完成以下步骤：

1. **环境检测**
   - 检测操作系统版本
   - 检测 systemd 可用性
   - 检测 Docker 安装情况

2. **选择安装路径**
   ```
   Install path [/opt/acme-reloader]:
   ```
   - 直接按回车使用默认路径
   - 或输入自定义路径

3. **选择配置模板**
   ```
   Select a configuration template:
     1) Nginx
     2) Caddy
     3) Multiple services
     4) Custom (manual configuration)

   Your choice [1]:
   ```
   - 选择适合你的服务类型
   - 配置文件会自动复制到 `config/config.yml`

4. **确认安装**
   ```
   Ready to install with the following settings:
     - Install path: /opt/acme-reloader
     - Config template: nginx.yml

   Continue? [Y/n]:
   ```

5. **配置 systemd 服务**
   - 自动创建 `/etc/systemd/system/acme-reloader-host.service`
   - 询问是否立即启动服务

6. **完成安装**
   - 显示下一步操作提示
   - 提供配置和测试命令

### 方式 2：手动安装

如果你想手动控制安装过程：

#### 步骤 1：复制文件

```bash
# 创建安装目录
sudo mkdir -p /opt/acme-reloader/{bin,lib,config,logs}

# 复制脚本和库文件
sudo cp -r bin/* /opt/acme-reloader/bin/
sudo cp -r lib/* /opt/acme-reloader/lib/

# 复制配置文件（选择合适的模板）
sudo cp examples/nginx.yml /opt/acme-reloader/config/config.yml

# 设置权限
sudo chmod +x /opt/acme-reloader/bin/*.sh
sudo chmod 755 /opt/acme-reloader/lib/*.sh
```

#### 步骤 2：配置服务

编辑配置文件：

```bash
sudo nano /opt/acme-reloader/config/config.yml
```

根据你的需求修改配置。详见 [CONFIG.md](CONFIG.md)。

#### 步骤 3：创建 systemd 服务

创建服务文件：

```bash
sudo nano /etc/systemd/system/acme-reloader-host.service
```

内容如下：

```ini
[Unit]
Description=acme-reloader-host - Certificate Reload Daemon
Documentation=https://github.com/AptS-1547/acme-docker-reloader
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=/opt/acme-reloader
ExecStart=/bin/bash /opt/acme-reloader/bin/acme-reloader-host.sh
Environment="CONFIG_FILE=/opt/acme-reloader/config/config.yml"
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

# 安全加固
NoNewPrivileges=false
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
```

重载 systemd 并启动服务：

```bash
sudo systemctl daemon-reload
sudo systemctl enable acme-reloader-host
sudo systemctl start acme-reloader-host
```

#### 步骤 4：验证安装

```bash
# 检查服务状态
sudo systemctl status acme-reloader-host

# 查看日志
sudo journalctl -u acme-reloader-host -f
```

## 配置 acme.sh

### 容器化 acme.sh

如果你使用 Docker 运行 acme.sh，需要挂载 socket 目录。

#### 修改 docker-compose.yml

```yaml
version: "3"

services:
  acme.sh:
    image: neilpang/acme.sh
    container_name: acme.sh
    restart: always
    command: daemon
    volumes:
      - ./ssl:/ssl
      - ./acme-config:/acme.sh
      # 重要：挂载 socket 目录
      - /tmp/acme-reloader:/tmp/acme-reloader
    environment:
      # 可选：设置自定义 socket 路径
      - ACME_RELOADER_SOCKET=/tmp/acme-reloader/socket/acme-reloader.sock
```

#### 重启容器

```bash
docker-compose down
docker-compose up -d
```

### 配置证书自动重载

#### 方法 1：在申请证书时指定

```bash
docker exec acme.sh acme.sh --issue \
  -d example.com \
  --dns dns_cf \
  --cert-file /ssl/example.com/cert.pem \
  --key-file /ssl/example.com/key.pem \
  --fullchain-file /ssl/example.com/fullchain.pem \
  --reloadcmd "/opt/acme-reloader/bin/acme-reloader.sh"
```

#### 方法 2：更新已有证书配置

```bash
docker exec acme.sh acme.sh --deploy \
  -d example.com \
  --deploy-hook /opt/acme-reloader/bin/acme-reloader.sh
```

#### 方法 3：修改 acme.sh 配置文件

进入容器：

```bash
docker exec -it acme.sh sh
```

编辑证书配置：

```bash
vi /acme.sh/example.com/example.com.conf
```

添加或修改：

```
Le_ReloadCmd='/opt/acme-reloader/bin/acme-reloader.sh'
```

### 非容器化 acme.sh

如果 acme.sh 直接运行在宿主机：

```bash
acme.sh --issue \
  -d example.com \
  --dns dns_cf \
  --reloadcmd "/opt/acme-reloader/bin/acme-reloader.sh"
```

## 测试安装

### 1. 检查服务运行状态

```bash
sudo systemctl status acme-reloader-host
```

应该看到 `Active: active (running)`。

### 2. 检查 socket 文件

```bash
ls -la /tmp/acme-reloader/socket/
```

应该看到命名管道文件：

```
prw-r--r-- 1 root root 0 xxx acme-reloader.sock
```

### 3. 手动测试重载

```bash
/opt/acme-reloader/bin/acme-reloader.sh
```

应该看到：

```
==================================================
  acme-reloader - Certificate Reload Client
==================================================

[INFO] acme-reloader client starting...
[INFO] Socket path: /tmp/acme-reloader/socket/acme-reloader.sock
[INFO] Request type: reload
[INFO] Sending reload request to host...
[INFO] Response from host: Complete
[INFO] ✓ Service reload completed successfully
```

### 4. 查看日志

```bash
# systemd 日志
sudo journalctl -u acme-reloader-host -n 50

# 应用日志
sudo tail -f /opt/acme-reloader/logs/acme-reloader.log
```

## 常见安装问题

### 问题 1：权限不足

**症状**：
```
Permission denied
```

**解决**：
- 确保使用 sudo 运行安装脚本
- 检查安装目录的权限

### 问题 2：systemd 服务无法启动

**症状**：
```
Failed to start acme-reloader-host.service
```

**解决**：
```bash
# 查看详细错误
sudo journalctl -u acme-reloader-host -n 50

# 检查服务文件语法
sudo systemd-analyze verify /etc/systemd/system/acme-reloader-host.service
```

### 问题 3：socket 目录无法创建

**症状**：
```
Failed to create socket directory
```

**解决**：
```bash
# 手动创建目录
sudo mkdir -p /tmp/acme-reloader/socket
sudo chmod 755 /tmp/acme-reloader/socket
```

### 问题 4：容器无法访问 socket

**症状**：
```
Socket not found in container
```

**解决**：
- 确保 docker-compose.yml 中正确挂载了卷
- 检查容器内路径：`docker exec acme.sh ls -la /tmp/acme-reloader/`
- 确保宿主机 socket 目录权限正确

## 升级

### 从旧版本升级

```bash
# 1. 备份配置
sudo cp /opt/acme-reloader/config/config.yml ~/acme-reloader-config.yml.bak

# 2. 停止服务
sudo systemctl stop acme-reloader-host

# 3. 拉取最新代码
cd acme-reloader
git pull

# 4. 重新安装
sudo ./install.sh

# 5. 恢复配置（如果需要）
sudo cp ~/acme-reloader-config.yml.bak /opt/acme-reloader/config/config.yml

# 6. 重启服务
sudo systemctl restart acme-reloader-host
```

## 下一步

- 查看 [CONFIG.md](CONFIG.md) 了解详细配置选项
- 查看 [TROUBLESHOOTING.md](TROUBLESHOOTING.md) 了解故障排查
- 回到 [README.md](../README.md) 查看使用说明
