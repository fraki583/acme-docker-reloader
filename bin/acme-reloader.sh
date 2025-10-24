#!/bin/bash
# acme-reloader.sh - 容器端客户端脚本
# 在 acme.sh 容器中调用，通知宿主机重启服务

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

# Socket 路径（可以通过环境变量覆盖）
SOCKET_PATH="${ACME_RELOADER_SOCKET:-$SOCKET_BASE/socket/acme-reloader.sock}"

# 超时设置（秒）
TIMEOUT="${ACME_RELOADER_TIMEOUT:-30}"

# 主函数
function main() {
    local request_type="${1:-reload}"

    echo "=================================================="
    echo "  acme-reloader - Certificate Reload Client"
    echo "=================================================="
    echo ""

    # 简化的日志配置（容器端只输出到控制台）
    log_init "" "INFO" "true" ""

    log_info "acme-reloader client starting..."
    log_info "Socket path: $SOCKET_PATH"
    log_info "Request type: $request_type"

    # 检查 socket 是否存在
    if [[ ! -p "$SOCKET_PATH" ]]; then
        log_error "Socket not found: $SOCKET_PATH"
        log_error "Please ensure:"
        log_error "  1. acme-reloader-host.sh is running on the host"
        log_error "  2. The socket directory is properly mounted to the container"
        log_error "     Example: -v /tmp/acme-reloader:/tmp/acme-reloader"
        exit 1
    fi

    # 初始化 IPC（使用自定义配置）
    IPC_SOCKET="$SOCKET_PATH"
    IPC_TIMEOUT="$TIMEOUT"
    IPC_RETRY_COUNT=3
    IPC_RETRY_INTERVAL=5

    log_info "Sending reload request to host..."

    # 发送请求并等待响应
    local response
    if response=$(ipc_request "$SOCKET_PATH" "$request_type" "$TIMEOUT"); then
        log_info "Response from host: $response"

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
