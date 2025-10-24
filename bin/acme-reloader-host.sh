#!/bin/bash
# acme-reloader-host.sh - 宿主机端守护进程
# 监听来自容器的证书更新通知，执行配置的服务重启命令

set -euo pipefail

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 加载库文件
source "$PROJECT_ROOT/lib/logger.sh"
source "$PROJECT_ROOT/lib/config.sh"
source "$PROJECT_ROOT/lib/ipc.sh"
source "$PROJECT_ROOT/lib/service.sh"

# 配置文件路径
CONFIG_FILE="${CONFIG_FILE:-$PROJECT_ROOT/config/config.yml}"

# 信号处理
function cleanup_and_exit() {
    log_info "Received termination signal, cleaning up..."
    ipc_cleanup
    log_info "acme-reloader-host stopped"
    exit 0
}

trap cleanup_and_exit INT TERM QUIT

# 主函数
function main() {
    echo "=================================================="
    echo "  acme-reloader-host - Certificate Reload Daemon"
    echo "=================================================="
    echo ""

    # 初始化配置
    config_init "$CONFIG_FILE"

    log_info "acme-reloader-host starting..."
    log_info "Project root: $PROJECT_ROOT"
    log_info "Config file: $CONFIG_FILE"

    # 检查配置
    local services=$(config_get_services)
    if [[ -z "$services" ]]; then
        log_error "No services configured. Please check your config file."
        exit 1
    fi

    log_info "Configured services: $services"

    # 切换到工作目录
    local working_dir=$(config_get "working_directory")
    if [[ -d "$working_dir" ]]; then
        cd "$working_dir"
        log_info "Working directory: $working_dir"
    else
        log_warn "Working directory not found: $working_dir, using current directory"
    fi

    # 初始化 IPC
    ipc_init

    # 创建 pipes
    if ! ipc_create_pipes; then
        log_error "Failed to create pipes, exiting"
        exit 1
    fi

    log_info "acme-reloader-host started successfully"
    log_info "Listening for requests..."
    echo ""

    # 开始监听
    ipc_listen "" service_handle_reload_request

    # 正常退出不会到这里，除非 ipc_listen 异常返回
    log_error "Listener exited unexpectedly"
    ipc_cleanup
    exit 1
}

# 运��主函数
main "$@"
