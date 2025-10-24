#!/bin/bash
# uninstall.sh - acme-reloader 卸载脚本
# 完全卸载 acme-reloader 及其服务

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认安装路径
DEFAULT_INSTALL_PATH="/opt/acme-reloader"

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
    echo "  acme-reloader Uninstallation Script"
    echo "=================================================="
    echo ""
}

# 检查是否以 root 运行
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        print_info "Please run: sudo $0"
        exit 1
    fi
}

# 停止并删除 systemd 服务
remove_systemd_service() {
    local service_file="/etc/systemd/system/acme-reloader-host.service"

    if [[ -f "$service_file" ]]; then
        print_info "Stopping and removing systemd service..."

        # 停止服务
        if systemctl is-active --quiet acme-reloader-host; then
            systemctl stop acme-reloader-host
            print_success "Service stopped"
        fi

        # 禁用服务
        if systemctl is-enabled --quiet acme-reloader-host 2>/dev/null; then
            systemctl disable acme-reloader-host
            print_success "Service disabled"
        fi

        # 删除服务文件
        rm -f "$service_file"
        systemctl daemon-reload
        print_success "Service file removed"
    else
        print_info "No systemd service found, skipping"
    fi
}

# 清理 socket 文件
cleanup_sockets() {
    print_info "Cleaning up socket files..."

    local socket_dirs=(
        "/tmp/acme-reloader"
        "/var/run/acme-reloader"
    )

    for dir in "${socket_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            rm -rf "$dir"
            print_success "Removed: $dir"
        fi
    done
}

# 删除安装文件
remove_files() {
    local install_path="$1"

    if [[ ! -d "$install_path" ]]; then
        print_warn "Installation directory not found: $install_path"
        return 0
    fi

    print_info "The following directory will be removed:"
    echo "  $install_path"
    echo ""
    echo -n "Remove installation files? [y/N]: "
    read -r confirm

    if [[ "${confirm,,}" == "y" ]]; then
        # 备份配置文件（可选）
        if [[ -f "$install_path/config/config.yml" ]]; then
            echo -n "Backup configuration file before removing? [Y/n]: "
            read -r backup_answer

            if [[ "${backup_answer,,}" != "n" ]]; then
                local backup_file="$HOME/acme-reloader-config-$(date +%Y%m%d-%H%M%S).yml"
                cp "$install_path/config/config.yml" "$backup_file"
                print_success "Configuration backed up to: $backup_file"
            fi
        fi

        # 删除安装目录
        rm -rf "$install_path"
        print_success "Installation files removed"
    else
        print_info "Installation files kept"
    fi
}

# 显示手动清理提示
show_manual_cleanup() {
    echo ""
    print_info "Manual cleanup suggestions:"
    echo ""
    echo "1. If you used acme.sh with this tool, update your acme.sh configuration:"
    echo "   Remove the --reloadcmd option from your certificate settings"
    echo ""
    echo "2. Check Docker containers for volume mounts:"
    echo "   docker ps -a --filter volume=/tmp/acme-reloader"
    echo ""
    echo "3. Remove Docker volume mounts from docker-compose.yml or container configs"
    echo ""
}

# 主卸载流程
main() {
    print_header

    # 检查 root 权限
    check_root

    # 询问安装路径
    echo -n "Installation path [$DEFAULT_INSTALL_PATH]: "
    read -r user_path

    local install_path="${user_path:-$DEFAULT_INSTALL_PATH}"

    echo ""
    print_warn "This will completely remove acme-reloader from your system"
    echo "  - Stop and remove systemd service"
    echo "  - Remove socket files"
    echo "  - Optionally remove: $install_path"
    echo ""
    echo -n "Continue with uninstallation? [y/N]: "
    read -r confirm

    if [[ "${confirm,,}" != "y" ]]; then
        print_info "Uninstallation cancelled"
        exit 0
    fi

    echo ""

    # 执行卸载步骤
    if command -v systemctl &> /dev/null; then
        remove_systemd_service
    fi

    cleanup_sockets
    remove_files "$install_path"

    # 显示手动清理提示
    show_manual_cleanup

    echo ""
    echo "=================================================="
    print_success "Uninstallation completed!"
    echo "=================================================="
    echo ""
}

# 运行主函数
main "$@"
