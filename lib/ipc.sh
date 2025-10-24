#!/bin/bash
# ipc.sh - 进程间通信模块
# 提供基于命名管道的健壮 IPC 机制

# IPC 状态
IPC_SOCKET=""
IPC_TIMEOUT=30
IPC_RETRY_COUNT=3
IPC_RETRY_INTERVAL=5

# 消息格式
# 格式: MESSAGE_TYPE|TIMESTAMP|DATA
# 示例: REQUEST|1234567890|restart
#       RESPONSE|1234567890|Complete
#       ERROR|1234567890|Command failed

# 初始化 IPC 配置
function ipc_init() {
    IPC_SOCKET=$(config_get "communication.socket_path")
    IPC_TIMEOUT=$(config_get "communication.timeout")
    IPC_RETRY_COUNT=$(config_get "communication.retry_count")
    IPC_RETRY_INTERVAL=$(config_get "communication.retry_interval")

    log_debug "IPC initialized: socket=$IPC_SOCKET, timeout=$IPC_TIMEOUT"
}

# 创建 socket
function ipc_create_socket() {
    local socket_path="$1"
    local socket_dir=$(dirname "$socket_path")

    # 清理旧的 socket
    if [[ -e "$socket_path" ]]; then
        log_warn "Removing existing socket: $socket_path"
        rm -f "$socket_path"
    fi

    # 创建目录
    if ! mkdir -p "$socket_dir" 2>/dev/null; then
        log_error "Failed to create socket directory: $socket_dir"
        return 1
    fi

    # 创建命名管道
    if ! mkfifo "$socket_path" 2>/dev/null; then
        log_error "Failed to create named pipe: $socket_path"
        return 1
    fi

    log_info "Socket created: $socket_path"
    return 0
}

# 检查 socket 是否存在
function ipc_socket_exists() {
    local socket_path="${1:-$IPC_SOCKET}"
    [[ -p "$socket_path" ]]
}

# 清理 socket
function ipc_cleanup() {
    local socket_path="${1:-$IPC_SOCKET}"

    if [[ -e "$socket_path" ]]; then
        rm -f "$socket_path"
        log_debug "Socket cleaned up: $socket_path"
    fi

    # 清理socket目录（���果为空）
    local socket_dir=$(dirname "$socket_path")
    rmdir "$socket_dir" 2>/dev/null || true
}

# 构造消息
function ipc_build_message() {
    local msg_type="$1"
    local data="$2"
    local timestamp=$(date +%s)

    echo "${msg_type}|${timestamp}|${data}"
}

# 解析消息
function ipc_parse_message() {
    local message="$1"

    local msg_type="${message%%|*}"
    local rest="${message#*|}"
    local timestamp="${rest%%|*}"
    local data="${rest#*|}"

    echo "$msg_type $timestamp $data"
}

# 发送消息（带超时和重试）
function ipc_send() {
    local socket_path="$1"
    local message="$2"
    local timeout="${3:-$IPC_TIMEOUT}"

    log_debug "Sending message to $socket_path: $message"

    local attempt=0
    while [[ $attempt -lt $IPC_RETRY_COUNT ]]; do
        ((attempt++))

        if ! ipc_socket_exists "$socket_path"; then
            log_error "Socket does not exist: $socket_path"
            if [[ $attempt -lt $IPC_RETRY_COUNT ]]; then
                log_info "Retrying in ${IPC_RETRY_INTERVAL}s... (attempt $attempt/$IPC_RETRY_COUNT)"
                sleep "$IPC_RETRY_INTERVAL"
                continue
            fi
            return 1
        fi

        # 使用 timeout 防止写入阻塞
        if timeout "$timeout" bash -c "echo '$message' > '$socket_path'" 2>/dev/null; then
            log_debug "Message sent successfully"
            return 0
        else
            local exit_code=$?
            if [[ $exit_code -eq 124 ]]; then
                log_error "Send timeout after ${timeout}s"
            else
                log_error "Failed to send message (exit code: $exit_code)"
            fi

            if [[ $attempt -lt $IPC_RETRY_COUNT ]]; then
                log_info "Retrying in ${IPC_RETRY_INTERVAL}s... (attempt $attempt/$IPC_RETRY_COUNT)"
                sleep "$IPC_RETRY_INTERVAL"
            fi
        fi
    done

    log_error "Failed to send message after $IPC_RETRY_COUNT attempts"
    return 1
}

# 接收消息（带超时）
function ipc_receive() {
    local socket_path="$1"
    local timeout="${2:-$IPC_TIMEOUT}"

    log_debug "Waiting for message on $socket_path (timeout: ${timeout}s)"

    if ! ipc_socket_exists "$socket_path"; then
        log_error "Socket does not exist: $socket_path"
        return 1
    fi

    # 使用 timeout 防止读取阻塞
    local message
    if message=$(timeout "$timeout" cat "$socket_path" 2>/dev/null); then
        log_debug "Message received: $message"
        echo "$message"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_error "Receive timeout after ${timeout}s"
        else
            log_error "Failed to receive message (exit code: $exit_code)"
        fi
        return 1
    fi
}

# 发送并等待响应（客户端用）
function ipc_request() {
    local socket_path="$1"
    local request_data="$2"
    local timeout="${3:-$IPC_TIMEOUT}"

    local request_msg=$(ipc_build_message "REQUEST" "$request_data")

    if ! ipc_send "$socket_path" "$request_msg" "$timeout"; then
        return 1
    fi

    log_info "Waiting for response..."
    sleep 2  # 给服务端处理时间

    local response
    if ! response=$(ipc_receive "$socket_path" "$timeout"); then
        log_error "No response received"
        return 1
    fi

    # 解析响应
    read -r msg_type timestamp data <<< "$(ipc_parse_message "$response")"

    case "$msg_type" in
        RESPONSE)
            log_info "Response received: $data"
            echo "$data"
            return 0
            ;;
        ERROR)
            log_error "Error response: $data"
            return 1
            ;;
        *)
            log_error "Unknown message type: $msg_type"
            return 1
            ;;
    esac
}

# 发送响应（服务端用）
function ipc_respond() {
    local socket_path="$1"
    local response_data="$2"
    local is_error="${3:-false}"

    local msg_type="RESPONSE"
    if [[ "$is_error" == "true" ]]; then
        msg_type="ERROR"
    fi

    local response_msg=$(ipc_build_message "$msg_type" "$response_data")

    if ! ipc_send "$socket_path" "$response_msg" 10; then
        log_error "Failed to send response"
        return 1
    fi

    log_debug "Response sent: $response_data"
    return 0
}

# 监听并处理请求（服务端用）
function ipc_listen() {
    local socket_path="$1"
    local callback="$2"  # 回调函数，处理收到的请求

    if ! ipc_socket_exists "$socket_path"; then
        log_error "Socket does not exist: $socket_path"
        return 1
    fi

    log_info "Listening on $socket_path..."

    while true; do
        local message
        # 非阻塞式读取，超时后继续循环（支持信号中断）
        if message=$(timeout 1 cat "$socket_path" 2>/dev/null); then
            log_debug "Received message: $message"

            # 解析消息
            read -r msg_type timestamp data <<< "$(ipc_parse_message "$message")"

            if [[ "$msg_type" != "REQUEST" ]]; then
                log_warn "Unexpected message type: $msg_type"
                continue
            fi

            log_info "Processing request: $data"

            # 调用回调处理请求
            if $callback "$data"; then
                ipc_respond "$socket_path" "Complete" false
            else
                ipc_respond "$socket_path" "Failed" true
            fi
        fi

        # 允许信号中断
        sleep 0.1
    done
}

# 导出函数
export -f ipc_init
export -f ipc_create_socket
export -f ipc_socket_exists
export -f ipc_cleanup
export -f ipc_build_message
export -f ipc_parse_message
export -f ipc_send
export -f ipc_receive
export -f ipc_request
export -f ipc_respond
export -f ipc_listen
