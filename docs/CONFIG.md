# 配置说明

本文档详细说明 acme-reloader 的配置选项。

## 配置文件位置

默认配置文件路径：`/opt/acme-reloader/config/config.yml`

可以通过环境变量覆盖：

```bash
CONFIG_FILE=/path/to/config.yml /opt/acme-reloader/bin/acme-reloader-host.sh
```

## 配置文件格式

配置文件使用 YAML 格式，包含以下主要部分：

- `communication` - 通信配置
- `logging` - 日志配置
- `services` - 服务配置
- `working_directory` - 工作目录
- `security` - 安全配置（预留）

## 完整配置示例

```yaml
# acme-reloader 配置文件

# 通信配置
communication:
  socket_path: "/tmp/acme-reloader/socket/acme-reloader.sock"
  timeout: 30
  retry_count: 3
  retry_interval: 5
  heartbeat_interval: 0

# 日志配置
logging:
  level: "INFO"
  file: "./logs/acme-reloader.log"
  history_file: "./logs/acme-reloader.history"
  max_size: 10
  max_backups: 5
  console: true

# 服务重启配置
services:
  nginx:
    command: "nginx -t && systemctl reload nginx"
    enabled: true
    timeout: 15
    pre_command: ""
    post_command: ""

  caddy:
    command: "systemctl reload caddy"
    enabled: false
    timeout: 10

# 工作目录
working_directory: "/opt/acme-reloader"

# 安全配置（预留）
security:
  message_validation: true
```

## 配置项详解

### communication（通信配置）

#### socket_path

- **类型**: 字符串
- **默认值**: `/tmp/acme-reloader/socket/acme-reloader.sock`
- **说明**: 命名管道（socket）文件路径
- **注意**:
  - 此路径必须在容器和宿主机之间共享
  - 确保目录具有适当的权限
  - 如果使用 Docker，必须通过卷挂载

**示例**：
```yaml
communication:
  socket_path: "/var/run/acme-reloader/acme-reloader.sock"
```

#### timeout

- **类型**: 整数
- **默认值**: `30`
- **单位**: 秒
- **说明**: 通信超时时间
- **建议**:
  - 简单命令（如 nginx reload）: 10-30 秒
  - 复杂命令或多个服务: 60-120 秒

**示例**：
```yaml
communication:
  timeout: 60
```

#### retry_count

- **类型**: 整数
- **默认值**: `3`
- **说明**: 通信失败后的重试次数
- **建议**: 3-5 次

#### retry_interval

- **类型**: 整数
- **默认值**: `5`
- **单位**: 秒
- **说明**: 重试之间的间隔时间

#### heartbeat_interval

- **类型**: 整数
- **默认值**: `0`
- **单位**: 秒
- **说明**: 心跳检测间隔，0 表示禁用
- **状态**: 当前版本未实现，预留功能

### logging（日志配置）

#### level

- **类型**: 字符串
- **默认值**: `INFO`
- **可选值**: `DEBUG`, `INFO`, `WARN`, `ERROR`
- **说明**: 日志级别
  - `DEBUG`: 调试信息（非常详细）
  - `INFO`: 一般信息（推荐）
  - `WARN`: 警告信息
  - `ERROR`: 仅错误信息

**示例**：
```yaml
logging:
  level: "DEBUG"  # 调试时使用
```

#### file

- **类型**: 字符串
- **默认值**: `./logs/acme-reloader.log`
- **说明**: 日志文件路径
- **注意**:
  - 相对路径相对于 `working_directory`
  - 确保目录存在且可写

#### history_file

- **类型**: 字符串
- **默认值**: `./logs/acme-reloader.history`
- **说明**: 操作历史文件路径
- **内容**: 记录所有操作的时间戳、状态、详情

#### max_size

- **类型**: 整数
- **默认值**: `10`
- **单位**: MB
- **说明**: 单个日志文件的最大大小
- **行为**: 超过此大小后会自动轮转

#### max_backups

- **类型**: 整数
- **默认值**: `5`
- **说明**: 保留的历史日志文件数量
- **行为**:
  - 轮转时保留最近的 N 个文件
  - 旧文件命名为 `filename.1`, `filename.2` 等

#### console

- **类型**: 布尔值
- **默认值**: `true`
- **说明**: 是否同时输出到控制台
- **建议**:
  - 调试时设为 `true`
  - 生产环境可设为 `false`（通过 systemd 查看日志）

### services（服务配置）

这是配置的核心部分，定义需要重载的服务。

#### 基本结构

```yaml
services:
  <service_name>:
    command: "<shell_command>"
    enabled: true|false
    timeout: <seconds>
    pre_command: "<shell_command>"
    post_command: "<shell_command>"
```

#### service_name

- **类型**: 字符串（YAML 键名）
- **说明**: 服务的标识符，可以任意命名
- **示例**: `nginx`, `caddy`, `haproxy`, `my_custom_service`

#### command

- **类型**: 字符串
- **必需**: 是
- **说明**: 要执行的 Shell 命令
- **注意**:
  - 可以使用 `&&` 连接多个命令
  - 可以使用管道 `|`
  - 返回非零退出码视为失败

**常见示例**：

```yaml
# Nginx - 先测试配置再重载
command: "nginx -t && systemctl reload nginx"

# Caddy - 直接重载
command: "systemctl reload caddy"

# Docker 容器
command: "docker exec nginx nginx -s reload"

# 自定义脚本
command: "/opt/scripts/reload-services.sh"

# 多个命令
command: "cp /ssl/*.pem /etc/nginx/ssl/ && nginx -t && systemctl reload nginx"
```

#### enabled

- **类型**: 布尔值
- **默认值**: `true`
- **说明**: 是否启用此服务
- **用途**:
  - 临时禁用某个服务而不删除配置
  - 在不同环境使用不同服务

#### timeout

- **类型**: 整数
- **默认值**: `0`（使用全局 `communication.timeout`）
- **单位**: 秒
- **说明**: 此服务命令的专属超时时间
- **建议**: 仅在某个服务需要特别长或短的超时时才设置

#### pre_command

- **类型**: 字符串
- **默认值**: `""`（空）
- **说明**: 主命令执行前的前置命令
- **用途**:
  - 准备工作（如复制文件）
  - 备份操作
  - 健康检查

**示例**：
```yaml
services:
  nginx:
    pre_command: "cp /ssl/*.pem /etc/nginx/ssl/"
    command: "nginx -t && systemctl reload nginx"
```

#### post_command

- **类型**: 字符串
- **默认值**: `""`（空）
- **说明**: 主命令执行后的后置命令
- **用途**:
  - 清理工作
  - 通知操作
  - 验证操作

**示例**：
```yaml
services:
  nginx:
    command: "systemctl reload nginx"
    post_command: "curl -fsS -m 10 --retry 5 -o /dev/null https://hc-ping.com/your-uuid"
```

### working_directory

- **类型**: 字符串
- **默认值**: `/opt/acme-reloader`
- **说明**: 工作目录
- **用途**:
  - 相对路径的基准目录
  - 日志文件的默认位置

### security

预留的安全配置部分，当前版本暂未完全实现。

#### message_validation

- **类型**: 布尔值
- **默认值**: `true`
- **说明**: 是否验证消息格式
- **状态**: 预留功能

## 配置示例

### 示例 1：单一 Nginx 服务

```yaml
communication:
  socket_path: "/tmp/acme-reloader/socket/acme-reloader.sock"
  timeout: 30

logging:
  level: "INFO"
  file: "./logs/acme-reloader.log"
  console: true

services:
  nginx:
    command: "nginx -t && systemctl reload nginx"
    enabled: true
    timeout: 15

working_directory: "/opt/acme-reloader"
```

### 示例 2：多服务环境

```yaml
communication:
  socket_path: "/tmp/acme-reloader/socket/acme-reloader.sock"
  timeout: 60
  retry_count: 3

logging:
  level: "INFO"
  file: "./logs/acme-reloader.log"
  console: true

services:
  nginx:
    command: "nginx -t && systemctl reload nginx"
    enabled: true
    timeout: 15

  haproxy:
    command: "haproxy -c -f /etc/haproxy/haproxy.cfg && systemctl reload haproxy"
    enabled: true
    timeout: 20

  postfix:
    command: "systemctl reload postfix"
    enabled: true
    timeout: 10

working_directory: "/opt/acme-reloader"
```

### 示例 3：Docker 容器服务

```yaml
communication:
  socket_path: "/tmp/acme-reloader/socket/acme-reloader.sock"
  timeout: 30

logging:
  level: "INFO"
  file: "./logs/acme-reloader.log"
  console: true

services:
  nginx_container:
    pre_command: "docker cp /ssl/cert.pem nginx:/etc/nginx/ssl/"
    command: "docker exec nginx nginx -t && docker exec nginx nginx -s reload"
    enabled: true
    timeout: 20

working_directory: "/opt/acme-reloader"
```

### 示例 4：调试配置

```yaml
communication:
  socket_path: "/tmp/acme-reloader/socket/acme-reloader.sock"
  timeout: 30
  retry_count: 5
  retry_interval: 3

logging:
  level: "DEBUG"  # 详细日志
  file: "./logs/acme-reloader.log"
  history_file: "./logs/acme-reloader.history"
  max_size: 50
  max_backups: 10
  console: true

services:
  test:
    command: "echo 'Test reload command executed'"
    enabled: true
    timeout: 5

working_directory: "/opt/acme-reloader"
```

## 配置最佳实践

### 1. 命令设计

- ✅ **先测试后执行**: `nginx -t && systemctl reload nginx`
- ✅ **使用绝对路径**: `/usr/sbin/nginx -t && /bin/systemctl reload nginx`
- ✅ **错误处理**: 使用 `&&` 确保前面的命令成功
- ❌ **避免交互式命令**: 不要使用需要用户输入的命令

### 2. 超时设置

- 简单重载（Nginx/Caddy）: 10-30 秒
- 复杂重载（多个服务）: 60-120 秒
- 容器操作: 加长 20-30 秒

### 3. 日志级别

- 开发/调试: `DEBUG`
- 生产环境: `INFO`
- 问题排查: 临时切换到 `DEBUG`

### 4. 服务启用控制

使用 `enabled: false` 而不是删除配置：

```yaml
services:
  nginx:
    enabled: true
    command: "systemctl reload nginx"

  caddy:
    enabled: false  # 临时禁用
    command: "systemctl reload caddy"
```

## 验证配置

### 检查语法

配置文件是 YAML 格式，可以使用在线工具验证：
- http://www.yamllint.com/

### 测试配置

```bash
# 手动测试重载
/opt/acme-reloader/bin/acme-reloader.sh

# 查看日志输出
sudo tail -f /opt/acme-reloader/logs/acme-reloader.log
```

### 调试模式

临时启用 DEBUG 日志：

```bash
# 修改配置
sudo nano /opt/acme-reloader/config/config.yml
# 将 level 改为 "DEBUG"

# 重启服务
sudo systemctl restart acme-reloader-host

# 执行测试
/opt/acme-reloader/bin/acme-reloader.sh

# 查看详细日志
sudo journalctl -u acme-reloader-host -n 100
```

## 故障排查

如果配置不生效，检查：

1. 配置文件语法是否正确（YAML 格式）
2. 缩进是否正确（使用空格，不是 Tab）
3. 服务是否重启：`sudo systemctl restart acme-reloader-host`
4. 查看日志：`sudo journalctl -u acme-reloader-host -n 50`

更多故障排查，参见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。
