#!/bin/bash
# logger.sh - 日志模块
# 提供统一的日志输出、日志级别控制和日志轮转功能

# 日志级别定义
declare -A LOG_LEVELS=(
    [DEBUG]=0
    [INFO]=1
    [WARN]=2
    [ERROR]=3
)

# 默认配置
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_FILE="${LOG_FILE:-}"
LOG_CONSOLE="${LOG_CONSOLE:-true}"
LOG_MAX_SIZE="${LOG_MAX_SIZE:-10485760}"  # 10MB
LOG_MAX_BACKUPS="${LOG_MAX_BACKUPS:-5}"
HISTORY_FILE="${HISTORY_FILE:-}"

# 颜色定义
COLOR_RESET='\033[0m'
COLOR_DEBUG='\033[0;36m'   # Cyan
COLOR_INFO='\033[0;32m'    # Green
COLOR_WARN='\033[0;33m'    # Yellow
COLOR_ERROR='\033[0;31m'   # Red

# 初始化日志系统
function log_init() {
    local log_file="$1"
    local level="$2"
    local console="$3"
    local history="$4"

    LOG_FILE="$log_file"
    LOG_LEVEL="${level:-INFO}"
    LOG_CONSOLE="${console:-true}"
    HISTORY_FILE="$history"

    # 创建日志目录
    if [[ -n "$LOG_FILE" ]]; then
        local log_dir=$(dirname "$LOG_FILE")
        mkdir -p "$log_dir" 2>/dev/null
    fi

    if [[ -n "$HISTORY_FILE" ]]; then
        local history_dir=$(dirname "$HISTORY_FILE")
        mkdir -p "$history_dir" 2>/dev/null
    fi
}

# 获取时间戳
function log_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# 日志轮转
function log_rotate() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        return 0
    fi

    local file_size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")

    if [[ $file_size -lt $LOG_MAX_SIZE ]]; then
        return 0
    fi

    # 轮转日志文件
    for ((i=$LOG_MAX_BACKUPS-1; i>=1; i--)); do
        if [[ -f "${file}.${i}" ]]; then
            mv "${file}.${i}" "${file}.$((i+1))"
        fi
    done

    mv "$file" "${file}.1"
    touch "$file"
}

# 检查日志级别
function should_log() {
    local level="$1"
    local current_level="${LOG_LEVELS[$LOG_LEVEL]:-1}"
    local message_level="${LOG_LEVELS[$level]:-0}"

    [[ $message_level -ge $current_level ]]
}

# 核心日志函数
function log_message() {
    local level="$1"
    shift
    local message="$*"

    if ! should_log "$level"; then
        return 0
    fi

    local timestamp=$(log_timestamp)
    local log_line="[$timestamp] [$level] $message"

    # 输出到控制台
    if [[ "$LOG_CONSOLE" == "true" ]]; then
        local color_var="COLOR_${level}"
        local color="${!color_var}"
        echo -e "${color}${log_line}${COLOR_RESET}" >&2
    fi

    # 输出到文件
    if [[ -n "$LOG_FILE" ]]; then
        log_rotate "$LOG_FILE"
        echo "$log_line" >> "$LOG_FILE"
    fi
}

# 便捷日志函数
function log_debug() {
    log_message "DEBUG" "$@"
}

function log_info() {
    log_message "INFO" "$@"
}

function log_warn() {
    log_message "WARN" "$@"
}

function log_error() {
    log_message "ERROR" "$@"
}

# 记录操作历史
function log_history() {
    local action="$1"
    local status="$2"
    local details="$3"

    if [[ -z "$HISTORY_FILE" ]]; then
        return 0
    fi

    local timestamp=$(log_timestamp)
    local history_line="[$timestamp] action=$action status=$status details=\"$details\""

    echo "$history_line" >> "$HISTORY_FILE"
}

# 记录命令执行
function log_command() {
    local cmd="$1"
    local exit_code="$2"
    local output="$3"

    if [[ $exit_code -eq 0 ]]; then
        log_info "Command executed successfully: $cmd"
        log_history "command_execution" "success" "cmd=$cmd exit_code=$exit_code"
    else
        log_error "Command failed: $cmd (exit code: $exit_code)"
        if [[ -n "$output" ]]; then
            log_error "Output: $output"
        fi
        log_history "command_execution" "failed" "cmd=$cmd exit_code=$exit_code output=$output"
    fi
}

# 导出函数供其他脚本使用
export -f log_init
export -f log_timestamp
export -f log_rotate
export -f should_log
export -f log_message
export -f log_debug
export -f log_info
export -f log_warn
export -f log_error
export -f log_history
export -f log_command
