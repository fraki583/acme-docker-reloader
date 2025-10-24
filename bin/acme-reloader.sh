#!/bin/bash
# acme-reloader.sh - 容器端客户端脚本
# 在 acme.sh 容器中调用，通知宿主机重启服务
# 注意：需要在容器中安装 bash（Alpine: apk add bash）

set -euo pipefail

# 检测运行环境并加载库文件
# 容器内路径：/acme-reloader-lib
# 宿主机路径：PROJECT_ROOT/lib
if [[ -d "/acme-reloader-lib" ]]; then
    # 容器环境
    LIB_DIR="/acme-reloader-lib"
    SOCKET_BASE="/acme-reloader"
else
    # 宿主机环境
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
    LIB_DIR="$PROJECT_ROOT/lib"
    SOCKET_BASE="$PROJECT_ROOT/acme-reloader"
fi

# 加载库文件
source "$LIB_DIR/logger.sh"
source "$LIB_DIR/config.sh"
source "$LIB_DIR/ipc.sh"

# 超时设置（秒）
TIMEOUT="${ACME_RELOADER_TIMEOUT:-30}"

# 客户端的简化 IPC 初始化（不依赖配置文件）
function client_ipc_init() {
    # 直接设置 pipe 路径，不读取配置文件
    local socket_dir="${SOCKET_BASE}/socket"
    IPC_REQUEST_PIPE="${socket_dir}/request.pipe"
    IPC_RESPONSE_PIPE="${socket_dir}/response.pipe"
    IPC_TIMEOUT="${TIMEOUT}"

    log_debug "Client IPC initialized: request=$IPC_REQUEST_PIPE, response=$IPC_RESPONSE_PIPE"
}

# 主函数
function main() {
    local request_type="${1:-reload}"

    echo "=================================================="
    echo "  acme-reloader - Certificate Reload Client"
    echo "=================================================="
    echo ""

    # 简化的日志配置（容器端只输出到控制台）
    log_init "" "INFO" "true" ""

    # 初始化 IPC 配置（客户端版本，不需要配置文件）
    client_ipc_init

    log_info "acme-reloader client starting..."
    log_info "Request pipe: $IPC_REQUEST_PIPE"
    log_info "Response pipe: $IPC_RESPONSE_PIPE"
    log_info "Request type: $request_type"

    # 检查 pipes 是否存在
    if ! ipc_pipes_exist; then
        log_error "Communication pipes not found"
        log_error "Please ensure:"
        log_error "  1. acme-reloader-host.sh is running on the host"
        log_error "  2. The pipe directory is properly mounted to the container"
        log_error "     Example: -v /path/to/acme-reloader:/acme-reloader"
        exit 1
    fi

    log_info "Sending reload request to host..."

    # 发送请求并等待响应
    local response
    if response=$(ipc_request "" "$request_type" "$TIMEOUT"); then
        if [[ "$response" == "Complete" ]]; then
            log_info "✓ Service reload completed successfully"
            exit 0
        else
            log_warn "Unexpected response: $response"
            exit 1
        fi
    else
        log_error "✗ Failed to reload service"
        log_error "Please check the host logs for more details:"
        log_error "  - Check: ./logs/acme-reloader.log on the host"
        log_error "  - Or run: journalctl -u acme-reloader-host -n 50"
        exit 1
    fi
}

# 显示使用帮助
function show_help() {
    cat << EOF
Usage: acme-reloader.sh [OPTIONS] [REQUEST_TYPE]

Send a reload request to the acme-reloader-host daemon.

REQUEST_TYPE:
  reload              Reload all configured services (default)
  restart             Same as reload
  reload:<service>    Reload a specific service (e.g., reload:nginx)
  restart:<service>   Same as reload:<service>

OPTIONS:
  -h, --help          Show this help message
  -s, --socket PATH   Socket path (default: $SOCKET_PATH)
  -t, --timeout SEC   Timeout in seconds (default: $TIMEOUT)

ENVIRONMENT VARIABLES:
  ACME_RELOADER_SOCKET    Override socket path
  ACME_RELOADER_TIMEOUT   Override timeout

EXAMPLES:
  # Reload all services
  acme-reloader.sh

  # Reload specific service
  acme-reloader.sh reload:nginx

  # Use custom socket path
  acme-reloader.sh -s /custom/path/socket reload

EXIT CODES:
  0    Success
  1    Failed to reload or communication error

EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -s|--socket)
            SOCKET_PATH="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -*)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
        *)
            # 位置参数（请求类型）
            main "$1"
            exit $?
            ;;
    esac
done

# 没有参数，使用默认
main "reload"
