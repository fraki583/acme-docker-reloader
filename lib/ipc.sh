#!/bin/bash
# ipc.sh - 进程间通信模块
# 使用两个 named pipe 实现双向通信

# IPC 状态
IPC_REQUEST_PIPE=""
IPC_RESPONSE_PIPE=""
IPC_TIMEOUT=30
IPC_RETRY_COUNT=3
IPC_RETRY_INTERVAL=5

# 消息格式
# 格式: MESSAGE_TYPE|TIMESTAMP|DATA
# 示例: REQUEST|1234567890|reload
#       RESPONSE|1234567890|Complete
#       ERROR|1234567890|Command failed

# 初始化 IPC 配置
function ipc_init() {
    local socket_base=$(config_get "communication.socket_path")
    # 去掉文件名，获取目录
    local socket_dir=$(dirname "$socket_base")
    IPC_REQUEST_PIPE="${socket_dir}/request.pipe"
    IPC_RESPONSE_PIPE="${socket_dir}/response.pipe"

    IPC_TIMEOUT=$(config_get "communication.timeout")
    IPC_RETRY_COUNT=$(config_get "communication.retry_count")
    IPC_RETRY_INTERVAL=$(config_get "communication.retry_interval")

    log_debug "IPC initialized: request=$IPC_REQUEST_PIPE, response=$IPC_RESPONSE_PIPE, timeout=$IPC_TIMEOUT"
}

# 创建两个 pipe（服务端用）
function ipc_create_pipes() {
    local socket_dir=$(dirname "$IPC_REQUEST_PIPE")

    # 创建目录
    if ! mkdir -p "$socket_dir" 2>/dev/null; then
        log_error "Failed to create pipe directory: $socket_dir"
        return 1
    fi

    # 清理旧的 pipes
    rm -f "$IPC_REQUEST_PIPE" "$IPC_RESPONSE_PIPE" 2>/dev/null

    # 创建请求 pipe
    if ! mkfifo "$IPC_REQUEST_PIPE" 2>/dev/null; then
        log_error "Failed to create request pipe: $IPC_REQUEST_PIPE"
        return 1
    fi

    # 创建响应 pipe
    if ! mkfifo "$IPC_RESPONSE_PIPE" 2>/dev/null; then
        log_error "Failed to create response pipe: $IPC_RESPONSE_PIPE"
        rm -f "$IPC_REQUEST_PIPE"
        return 1
    fi

    log_info "Pipes created: request=$IPC_REQUEST_PIPE, response=$IPC_RESPONSE_PIPE"
    return 0
}

# 检查 pipe 是否存在
function ipc_pipes_exist() {
    [[ -p "$IPC_REQUEST_PIPE" && -p "$IPC_RESPONSE_PIPE" ]]
}

# 清理 pipes
function ipc_cleanup() {
    rm -f "$IPC_REQUEST_PIPE" "$IPC_RESPONSE_PIPE" 2>/dev/null
    log_debug "Pipes cleaned up"

    # 清理目录（如果为空）
    local socket_dir=$(dirname "$IPC_REQUEST_PIPE")
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

# 发送并等待响应（客户端用）
function ipc_request() {
    # 第一个参数被忽略（兼容性）
    local request_data="$2"
    local timeout="${3:-$IPC_TIMEOUT}"

    log_info "Sending request to host..."

    # 检查 pipes 是否存在
    if ! ipc_pipes_exist; then
        log_error "Communication pipes not found"
        log_error "Request pipe: $IPC_REQUEST_PIPE"
        log_error "Response pipe: $IPC_RESPONSE_PIPE"
        log_error "Please ensure acme-reloader-host is running"
        return 1
    fi

    local request_msg=$(ipc_build_message "REQUEST" "$request_data")
    log_debug "Sending: $request_msg"

    # 发送请求到 request pipe
    if ! timeout "$timeout" bash -c "echo '$request_msg' > '$IPC_REQUEST_PIPE'" 2>/dev/null; then
        log_error "Failed to send request (timeout or pipe closed)"
        return 1
    fi

    log_info "Request sent, waiting for response..."

    # 从 response pipe 读取响应
    local response
    if ! response=$(timeout "$timeout" cat "$IPC_RESPONSE_PIPE" 2>/dev/null); then
        log_error "No response received (timeout or pipe closed)"
        return 1
    fi

    log_debug "Received: $response"

    # 解析响应
    read -r msg_type timestamp data <<< "$(ipc_parse_message "$response")"

    case "$msg_type" in
        RESPONSE)
            log_info "Response: $data"
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

# 监听并处理请求（服务端用）
function ipc_listen() {
    # 第一个参数被忽略（兼容性）
    local callback="$2"

    if ! ipc_pipes_exist; then
        log_error "Pipes do not exist"
        return 1
    fi

    log_info "Listening on request pipe: $IPC_REQUEST_PIPE"

    while true; do
        # 从 request pipe 读取（阻塞）
        local message
        if read -r message < "$IPC_REQUEST_PIPE" 2>/dev/null; then
            log_debug "Received message: $message"

            # 解析消息
            read -r msg_type timestamp data <<< "$(ipc_parse_message "$message")"

            if [[ "$msg_type" != "REQUEST" ]]; then
                log_warn "Unexpected message type: $msg_type"
                continue
            fi

            log_info "Processing request: $data"

            # 调用回调处理请求
            local response_msg
            if $callback "$data"; then
                response_msg=$(ipc_build_message "RESPONSE" "Complete")
                log_info "Request completed successfully"
            else
                response_msg=$(ipc_build_message "ERROR" "Failed")
                log_error "Request processing failed"
            fi

            # 发送响应到 response pipe
            log_debug "Sending response: $response_msg"
            if ! echo "$response_msg" > "$IPC_RESPONSE_PIPE" 2>/dev/null; then
                log_error "Failed to send response (client may have disconnected)"
            fi
        else
            # 读取失败，可能是 pipe 被关闭或中断
            local exit_code=$?
            if [[ $exit_code -ne 0 ]]; then
                log_warn "Read from pipe interrupted or closed (exit code: $exit_code)"
                sleep 0.5
            fi
        fi
    done
}

# 导出函数
export -f ipc_init
export -f ipc_create_pipes
export -f ipc_pipes_exist
export -f ipc_cleanup
export -f ipc_build_message
export -f ipc_parse_message
export -f ipc_request
export -f ipc_listen
