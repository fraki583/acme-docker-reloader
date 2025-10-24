# 故障排查指南

本文档提供 acme-reloader 常见问题的诊断和解决方案。

## 目录

- [通用诊断步骤](#通用诊断步骤)
- [常见问题](#常见问题)
  - [通信问题](#通信问题)
  - [服务重启失败](#服务重启失败)
  - [权限问题](#权限问题)
  - [Docker 相关问题](#docker-相关问题)
- [日志分析](#日志分析)
- [调试技巧](#调试技巧)

## 通用诊断步骤

遇到问题时，首先执行这些基本检查：

### 1. 检查服务状态

```bash
# 检查 systemd 服务
sudo systemctl status acme-reloader-host

# 应该看到 Active: active (running)
```

### 2. 查看日志

```bash
# 查看 systemd 日志（最近 50 行）
sudo journalctl -u acme-reloader-host -n 50

# 实时跟踪日志
sudo journalctl -u acme-reloader-host -f

# 查看应用日志
sudo tail -f /opt/acme-reloader/logs/acme-reloader.log

# 查看操作历史
sudo cat /opt/acme-reloader/logs/acme-reloader.history
```

### 3. 检查 Socket

```bash
# 检查 socket 文件是否存在
ls -la /tmp/acme-reloader/socket/

# 应该看到一个命名管道文件（p 开头）
# prw-r--r-- 1 root root 0 xxx acme-reloader.sock
```

### 4. 手动测试

```bash
# 从宿主机测试
/opt/acme-reloader/bin/acme-reloader.sh

# 从容器测试
docker exec acme.sh /opt/acme-reloader/bin/acme-reloader.sh
```

## 常见问题

### 通信问题

#### 问题：Socket not found

**完整错误**：
```
[ERROR] Socket not found: /tmp/acme-reloader/socket/acme-reloader.sock
```

**可能原因**：
1. 宿主机守护进程未运行
2. Socket 目录未创建
3. Socket 目录未正确挂载到容器

**解决方法**：

```bash
# 1. 检查守护进程
sudo systemctl status acme-reloader-host

# 如果未运行，启动它
sudo systemctl start acme-reloader-host

# 2. 检查 socket 目录
ls -la /tmp/acme-reloader/socket/

# 如果不存在，检查守护进程日志
sudo journalctl -u acme-reloader-host -n 50

# 3. 检查容器挂载（Docker）
docker inspect acme.sh | grep -A 10 Mounts

# 应该看到 /tmp/acme-reloader 的挂载
```

#### 问题：通信超时

**完整错误**：
```
[ERROR] Send timeout after 30s
[ERROR] Failed to send message
```

**可能原因**：
1. 守护进程卡死或无响应
2. Socket 权限问题
3. 网络/IO 问题

**解决方法**：

```bash
# 1. 重启守护进程
sudo systemctl restart acme-reloader-host

# 2. 检查进程状态
ps aux | grep acme-reloader-host

# 3. 增加超时时间（临时）
ACME_RELOADER_TIMEOUT=60 /opt/acme-reloader/bin/acme-reloader.sh

# 4. 或修改配置文件
sudo nano /opt/acme-reloader/config/config.yml
# 将 communication.timeout 改为 60
```

#### 问题：连接被拒绝或管道损坏

**完整错误**：
```
Broken pipe
Connection refused
```

**可能原因**：
1. Socket 文件损坏
2. 多个进程同时访问
3. 守护进程异常终止

**解决方法**：

```bash
# 1. 清理并重启
sudo systemctl stop acme-reloader-host
sudo rm -rf /tmp/acme-reloader/socket/
sudo systemctl start acme-reloader-host

# 2. 检查是否有多个守护进程
ps aux | grep acme-reloader-host

# 如果有多个，杀掉旧的
sudo killall acme-reloader-host.sh
sudo systemctl restart acme-reloader-host
```

### 服务重启失败

#### 问题：Nginx reload 失败

**完整错误**：
```
[ERROR] Service 'nginx' command failed with exit code 1
[ERROR] Output: nginx: configuration file /etc/nginx/nginx.conf test failed
```

**可能原因**：
1. Nginx 配置语法错误
2. 证书文件路径错误
3. Nginx 未运行

**解决方法**：

```bash
# 1. 手动测试 Nginx 配置
sudo nginx -t

# 2. 检查证书文件
ls -la /path/to/ssl/

# 3. 检查 Nginx 服务
sudo systemctl status nginx

# 4. 查看详细错误
sudo tail -f /opt/acme-reloader/logs/acme-reloader.log

# 5. 如果是证书路径问题，更新 Nginx 配置
sudo nano /etc/nginx/sites-available/your-site
```

#### 问题：Docker 容器重载失败

**完整错误**：
```
[ERROR] Service 'nginx_container' command failed
[ERROR] Output: Error: No such container: nginx
```

**可能原因**：
1. 容器名称错误
2. 容器未运行
3. Docker 守护进程无权限

**解决方法**：

```bash
# 1. 检查容器是否存在
docker ps -a | grep nginx

# 2. 检查容器名称
docker ps --format "{{.Names}}"

# 3. 更新配置文件中的容器名
sudo nano /opt/acme-reloader/config/config.yml

# 4. 测试 Docker 命令
docker exec your-nginx-container nginx -s reload
```

### 权限问题

#### 问题：Permission denied

**完整错误**：
```
Permission denied: /tmp/acme-reloader/socket/
mkdir: cannot create directory: Permission denied
```

**可能原因**：
1. 目录权限不足
2. SELinux 阻止
3. 用户权限不够

**解决方法**：

```bash
# 1. 检查目录权限
ls -ld /tmp/acme-reloader/

# 2. 修复权限
sudo chmod 755 /tmp/acme-reloader/
sudo chown root:root /tmp/acme-reloader/

# 3. 检查 SELinux（如果启用）
getenforce
# 如果是 Enforcing，临时设为 Permissive 测试
sudo setenforce 0

# 4. 确保使用 sudo 运行
sudo systemctl restart acme-reloader-host
```

#### 问题：systemctl 权限不足

**完整错误**：
```
Failed to reload nginx.service: Access denied
```

**可能原因**：
systemd 服务配置的用户权限不足

**解决方法**：

```bash
# 检查服务运行用户
sudo systemctl show acme-reloader-host | grep User

# 服务应该以 root 运行，或者使用 sudo
# 如果需要修改，编辑服务文件
sudo nano /etc/systemd/system/acme-reloader-host.service

# 确保没有 User= 行，或使用 sudo
# ExecStart=/usr/bin/sudo /bin/bash /opt/acme-reloader/bin/acme-reloader-host.sh

# 重新加载
sudo systemctl daemon-reload
sudo systemctl restart acme-reloader-host
```

### Docker 相关问题

#### 问题：容器内找不到脚本

**完整错误**：
```
acme.sh: /opt/acme-reloader/bin/acme-reloader.sh: not found
```

**可能原因**：
1. 脚本未挂载到容器
2. 挂载路径错误
3. 脚本权限问题

**解决方法**：

```bash
# 1. 检查 docker-compose.yml 配置
cat docker-compose.yml | grep -A 5 volumes

# 应该包含：
# - /opt/acme-reloader/bin/acme-reloader.sh:/opt/acme-reloader/bin/acme-reloader.sh:ro

# 2. 检查容器内是否存在
docker exec acme.sh ls -la /opt/acme-reloader/bin/

# 3. 检查宿主机脚本
ls -la /opt/acme-reloader/bin/acme-reloader.sh

# 4. 重建容器
docker-compose down
docker-compose up -d

# 5. 验证挂载
docker exec acme.sh cat /opt/acme-reloader/bin/acme-reloader.sh
```

#### 问题：证书更新但服务未重载

**症状**：
证书已在容器中更新，但 Nginx 仍使用旧证书

**可能原因**：
1. reloadcmd 未配置
2. 重载命令未执行
3. 证书路径不一致

**解决方法**：

```bash
# 1. 检查 acme.sh 配置
docker exec acme.sh cat /acme.sh/example.com/example.com.conf | grep ReloadCmd

# 应该有：
# Le_ReloadCmd='/opt/acme-reloader/bin/acme-reloader.sh'

# 2. 手动触发重载测试
docker exec acme.sh /opt/acme-reloader/bin/acme-reloader.sh

# 3. 检查证书时间戳
ls -la /path/to/ssl/example.com/

# 4. 重新设置 reloadcmd
docker exec acme.sh acme.sh --deploy \
  -d example.com \
  --deploy-hook /opt/acme-reloader/bin/acme-reloader.sh

# 5. 强制续签测试
docker exec acme.sh acme.sh --renew \
  -d example.com \
  --force
```

## 日志分析

### 日志级别说明

- `[DEBUG]`: 详细的调试信息
- `[INFO]`: 正常操作信息
- `[WARN]`: 警告，非致命错误
- `[ERROR]`: 错误信息

### 关键日志模式

#### 成功的重载

```log
[2024-xx-xx 12:00:00] [INFO] acme-reloader-host started successfully
[2024-xx-xx 12:00:00] [INFO] Listening on: /tmp/acme-reloader/socket/acme-reloader.sock
[2024-xx-xx 12:05:00] [INFO] Received overload request from acme.sh container
[2024-xx-xx 12:05:00] [INFO] Processing request: reload
[2024-xx-xx 12:05:00] [INFO] Reloading service: nginx
[2024-xx-xx 12:05:01] [INFO] Command executed successfully: nginx -t && systemctl reload nginx
[2024-xx-xx 12:05:01] [INFO] Service 'nginx' reloaded successfully
```

#### 失败的重载

```log
[2024-xx-xx 12:05:00] [INFO] Received overload request
[2024-xx-xx 12:05:00] [ERROR] Service 'nginx' command failed with exit code 1
[2024-xx-xx 12:05:00] [ERROR] Output: nginx: configuration test failed
```

### 操作历史

查看操作历史文件了解详细执行记录：

```bash
cat /opt/acme-reloader/logs/acme-reloader.history
```

格式：
```
[2024-xx-xx 12:05:00] action=service_execute status=success details="service=nginx duration=1s"
```

## 调试技巧

### 启用详细日志

临时启用 DEBUG 级别日志：

```bash
# 1. 编辑配置
sudo nano /opt/acme-reloader/config/config.yml

# 2. 修改日志级别
logging:
  level: "DEBUG"

# 3. 重启服务
sudo systemctl restart acme-reloader-host

# 4. 查看详细日志
sudo journalctl -u acme-reloader-host -f
```

### 手动测试每个步骤

```bash
# 1. 测试 socket 创建
sudo /opt/acme-reloader/bin/acme-reloader-host.sh &
sleep 2
ls -la /tmp/acme-reloader/socket/

# 2. 测试客户端连接
/opt/acme-reloader/bin/acme-reloader.sh

# 3. 测试服务命令（单独执行）
nginx -t && systemctl reload nginx

# 4. 停止测试进程
sudo killall acme-reloader-host.sh
```

### 使用 strace 调试

```bash
# 跟踪系统调用
sudo strace -f -e trace=file,network /opt/acme-reloader/bin/acme-reloader-host.sh

# 查看详细的文件和网络操作
```

### 检查配置解析

```bash
# 手动测试配置解析
source /opt/acme-reloader/lib/config.sh
config_init /opt/acme-reloader/config/config.yml
config_dump
```

## 获取帮助

如果以上方法都无法解决问题：

1. **查看完整日志**
   ```bash
   sudo journalctl -u acme-reloader-host --no-pager -l > ~/acme-reloader-debug.log
   ```

2. **收集系统信息**
   ```bash
   uname -a
   docker --version
   systemctl --version
   ```

3. **提交 Issue**
   - 访问: https://github.com/AptS-1547/acme-docker-reloader/issues
   - 包含错误信息、日志、系统信息
   - 说明你的使用场景（容器/宿主机配置）

## 紧急恢复

如果 acme-reloader 导致服务无法正常工作：

### 临时禁用

```bash
# 停止服务
sudo systemctl stop acme-reloader-host

# 手动重载 Nginx
sudo systemctl reload nginx

# 从 acme.sh 配置中移除 reloadcmd
docker exec acme.sh acme.sh --remove-deploy-hook -d example.com
```

### 完全卸载

```bash
# 运行卸载脚本
sudo ./uninstall.sh

# 手动清理残留
sudo rm -rf /tmp/acme-reloader
sudo rm -rf /opt/acme-reloader
```

### 恢复到旧版本

```bash
# 使用备份的旧脚本
cd /opt/acme-reloader/bin
sudo cp acme-reloader-host.sh.bak acme-reloader-host.sh
sudo systemctl restart acme-reloader-host
```
