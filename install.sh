#!/bin/bash
# install.sh - acme-reloader 一键安装脚本
# 在当前目录部署完整的 acme.sh + reloader 解决方案

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 获取脚本所在目录（项目根目录）
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 打印带颜色的消息
print_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $*"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

print_error() {
    echo -e "${RED}[✗]${NC} $*"
}

# 打印标题
print_header() {
    echo ""
    echo "=================================================="
    echo "  acme-reloader 一键安装脚本"
    echo "  完整的 acme.sh Docker 证书自动化解决方案"
    echo "=================================================="
    echo ""
}

# 检查是否以 root 运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        print_info "请使用: sudo $0"
        exit 1
    fi
}

# 检测系统环境
detect_environment() {
    print_info "检测系统环境..."

    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        print_success "操作系统: $NAME $VERSION"
    else
        print_warn "无法检测操作系统版本"
    fi

    # 检测 systemd
    if command -v systemctl &> /dev/null; then
        print_success "systemd 已安装"
    else
        print_error "未找到 systemd，无法配置服务自动启动"
        print_info "你需要手动运行 bin/acme-reloader-host.sh"
        exit 1
    fi

    # 检测 Docker
    if command -v docker &> /dev/null; then
        print_success "Docker 已安装: $(docker --version)"
    else
        print_warn "未检测到 Docker"
        print_info "你需要先安装 Docker 才能使用此解决方案"
        echo -n "是否继续安装（不安装 Docker）? [y/N]: "
        read -r answer
        if [[ "${answer,,}" != "y" ]]; then
            print_info "安装已取消"
            exit 0
        fi
    fi

    # 检测 docker-compose
    if command -v docker-compose &> /dev/null || docker compose version &> /dev/null; then
        print_success "docker-compose 已安装"
    else
        print_warn "未检测到 docker-compose"
        print_info "你需要手动运行 Docker 容器"
    fi

    echo ""
}

# 初始化项目目录
init_directories() {
    print_info "初始化项目目录..."

    cd "$PROJECT_DIR"

    # 创建必要的目录
    mkdir -p ssl acme-config acme-reloader logs

    # 设置脚本权限
    chmod +x bin/*.sh 2>/dev/null || true
    chmod 755 lib/*.sh 2>/dev/null || true

    print_success "目录结构已创建"
}

# 创建配置文件
create_config() {
    print_info "配置 acme-reloader..."

    local config_file="$PROJECT_DIR/config/config.yml"

    if [[ -f "$config_file" ]]; then
        print_warn "配置文件已存在: $config_file"
        echo -n "是否覆盖? [y/N]: "
        read -r answer
        if [[ "${answer,,}" != "y" ]]; then
            print_info "保留现有配置"
            return 0
        fi
    fi

    # 询问重启命令
    echo ""
    print_info "请输入证书更新后需要执行的重启命令"
    print_info "常见示例:"
    echo "  - Nginx (宿主机):  systemctl reload nginx"
    echo "  - Nginx (容器):    docker exec nginx nginx -s reload"
    echo "  - Caddy (宿主机):  systemctl reload caddy"
    echo ""
    echo -n "重启命令 [systemctl reload nginx]: "
    read -r reload_cmd

    if [[ -z "$reload_cmd" ]]; then
        reload_cmd="systemctl reload nginx"
    fi

    # 生成配置文件
    cat > "$config_file" << EOF
# acme-reloader 配置文件

communication:
  socket_path: "$PROJECT_DIR/acme-reloader/socket/acme-reloader.sock"
  timeout: 30
  retry_count: 3
  retry_interval: 5

logging:
  level: "INFO"
  file: "$PROJECT_DIR/logs/acme-reloader.log"
  history_file: "$PROJECT_DIR/logs/acme-reloader.history"
  console: true
  max_size: 10
  max_backups: 5

services:
  main:
    command: "$reload_cmd"
    enabled: true
    timeout: 15

working_directory: "$PROJECT_DIR"

security:
  message_validation: true
EOF

    print_success "配置文件已创建: $config_file"
}

# 配置 systemd 服务
configure_systemd() {
    print_info "配置 systemd 服务..."

    local service_file="/etc/systemd/system/acme-reloader-host.service"

    cat > "$service_file" << EOF
[Unit]
Description=acme-reloader-host - Certificate Reload Daemon
Documentation=https://github.com/AptS-1547/acme-docker-reloader
After=network-online.target docker.service
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$PROJECT_DIR
ExecStart=/bin/bash $PROJECT_DIR/bin/acme-reloader-host.sh
Environment="CONFIG_FILE=$PROJECT_DIR/config/config.yml"
Restart=on-failure
RestartSec=10s
StandardOutput=journal
StandardError=journal

# 安全加固
NoNewPrivileges=false
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

    # 重载 systemd
    systemctl daemon-reload

    print_success "systemd 服务已配置"
}

# 启动服务
start_service() {
    echo ""
    echo -n "是否现在启动 acme-reloader-host 服务? [Y/n]: "
    read -r answer

    if [[ "${answer,,}" != "n" ]]; then
        systemctl enable acme-reloader-host
        systemctl start acme-reloader-host

        sleep 1

        if systemctl is-active --quiet acme-reloader-host; then
            print_success "服务已启动并设置为开机自启"
            echo ""
            print_info "服务状态:"
            systemctl status acme-reloader-host --no-pager -l | head -n 10
        else
            print_error "服务启动失败，请检查日志:"
            print_info "  sudo journalctl -u acme-reloader-host -n 50"
        fi
    else
        print_info "服务未启动，你可以稍后手动启动:"
        print_info "  sudo systemctl start acme-reloader-host"
    fi
}

# 显示后续步骤
show_next_steps() {
    echo ""
    echo "=================================================="
    print_success "安装完成！"
    echo "=================================================="
    echo ""
    print_info "接下来的步骤:"
    echo ""
    echo "1. 启动 acme.sh Docker 容器:"
    echo "   cd $PROJECT_DIR"
    echo "   docker-compose up -d"
    echo ""
    echo "2. 进入容器申请证书:"
    echo "   docker exec -it acme.sh ash"
    echo "   acme.sh --register-account -m your@email.com"
    echo "   acme.sh --issue -d example.com --dns dns_cf"
    echo ""
    echo "3. 安装证书并设置自动重载:"
    echo "   acme.sh --install-cert -d example.com \\"
    echo "     --cert-file /ssl/cert.pem \\"
    echo "     --key-file /ssl/key.pem \\"
    echo "     --fullchain-file /ssl/fullchain.pem \\"
    echo "     --reloadcmd \"bash /acme-reloader.sh\""
    echo ""
    echo "4. 配置你的 Web 服务器使用证书:"
    echo "   证书位置: $PROJECT_DIR/ssl/"
    echo ""
    echo "5. 查看日志:"
    echo "   sudo journalctl -u acme-reloader-host -f"
    echo "   tail -f $PROJECT_DIR/logs/acme-reloader.log"
    echo ""
    print_info "详细文档请查看 README.md"
    echo ""
}

# 主安装流程
main() {
    print_header

    # 检查 root 权限
    check_root

    # 检测环境
    detect_environment

    # 显示安装信息
    print_info "安装位置: $PROJECT_DIR"
    echo ""
    echo -n "确认开始安装? [Y/n]: "
    read -r confirm

    if [[ "${confirm,,}" == "n" ]]; then
        print_info "安装已取消"
        exit 0
    fi

    echo ""

    # 执行安装步骤
    init_directories
    create_config
    configure_systemd
    start_service

    # 显示后续步骤
    show_next_steps
}

# 运行主函数
main "$@"
