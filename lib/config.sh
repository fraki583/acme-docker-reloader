#!/bin/bash
# config.sh - 配置文件解析模块
# 提供简单的 YAML 风格配置文件解析功能

# 全局变量存储配置
declare -A CONFIG

# 默认配置值
CONFIG_DEFAULTS=(
    "communication.socket_path=/tmp/acme-reloader/socket/acme-reloader.sock"
    "communication.timeout=30"
    "communication.retry_count=3"
    "communication.retry_interval=5"
    "communication.heartbeat_interval=0"
    "logging.level=INFO"
    "logging.file=./logs/acme-reloader.log"
    "logging.history_file=./logs/acme-reloader.history"
    "logging.console=true"
    "logging.max_size=10"
    "logging.max_backups=5"
    "working_directory=/opt/acme-reloader"
    "security.message_validation=true"
)

# 加载默认配置
function config_load_defaults() {
    for item in "${CONFIG_DEFAULTS[@]}"; do
        local key="${item%%=*}"
        local value="${item#*=}"
        CONFIG["$key"]="$value"
    done
}

# 去除字符串首尾空白和引号
function config_trim() {
    local value="$1"
    # 去除首尾空白
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    # 去除引号
    value="${value%\"}"
    value="${value#\"}"
    echo "$value"
}

# 解析配置文件
function config_parse() {
    local config_file="$1"

    if [[ ! -f "$config_file" ]]; then
        echo "[WARN] Config file not found: $config_file, using defaults" >&2
        return 1
    fi

    echo "[DEBUG] Parsing config file: $config_file" >&2

    local current_section=""
    local line_num=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        line_num=$((line_num + 1))

        # 跳过空行和注释
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        # 检测section（顶级键，无缩进）
        if [[ "$line" =~ ^([a-zA-Z_][a-zA-Z0-9_]*):$ ]]; then
            current_section="${BASH_REMATCH[1]}"
            echo "[DEBUG] Found section: $current_section" >&2
            continue
        fi

        # 解析服务配置（services 下的二级嵌套）- 优先处理
        if [[ "$current_section" == "services" ]]; then
            # 服务名定义（单层缩进，值为空）
            if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_-]*):[[:space:]]*$ ]]; then
                local service_name="${BASH_REMATCH[1]}"
                CONFIG["services._list_"]="${CONFIG[services._list_]:-} $service_name"
                echo "[DEBUG] Found service: $service_name" >&2
                continue
            fi

            # 服务属性（双层缩进）
            if [[ "$line" =~ ^[[:space:]]{4,}([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
                local attr_key="${BASH_REMATCH[1]}"
                local attr_value="${BASH_REMATCH[2]}"
                attr_value=$(config_trim "$attr_value")

                # 找到最近的服务名
                local services="${CONFIG[services._list_]:-}"
                local last_service="${services##* }"

                if [[ -n "$last_service" ]]; then
                    CONFIG["services.${last_service}.${attr_key}"]="$attr_value"
                    echo "[DEBUG] Loaded service config: services.${last_service}.${attr_key} = $attr_value" >&2
                fi
                continue
            fi
        fi

        # 解析普通键值对（有缩进）
        if [[ "$line" =~ ^[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            value=$(config_trim "$value")

            if [[ -n "$current_section" ]]; then
                local full_key="${current_section}.${key}"
                CONFIG["$full_key"]="$value"
                echo "[DEBUG] Loaded config: $full_key = $value" >&2
            fi
            continue
        fi
    done < "$config_file"

    echo "[INFO] Config file loaded: $config_file" >&2
    return 0
}

# 获取配置值
function config_get() {
    local key="$1"
    local default_value="${2:-}"

    local value="${CONFIG[$key]:-$default_value}"
    echo "$value"
}

# 获取服务列表
function config_get_services() {
    local services="${CONFIG[services._list_]:-}"
    echo "$services" | xargs  # trim and normalize spaces
}

# 获取服务配置
function config_get_service() {
    local service="$1"
    local attr="$2"
    local default_value="${3:-}"

    local key="services.${service}.${attr}"
    config_get "$key" "$default_value"
}

# 检查服务是否启用
function config_service_enabled() {
    local service="$1"
    local enabled=$(config_get_service "$service" "enabled" "false")

    [[ "$enabled" == "true" ]]
}

# 初始化配置系统
function config_init() {
    local config_file="$1"

    # 加载默认配置
    config_load_defaults

    # 如果提供了配置文件，解析它
    if [[ -n "$config_file" ]]; then
        config_parse "$config_file"
    fi

    # 应用配置到日志系统
    local log_file=$(config_get "logging.file")
    local log_level=$(config_get "logging.level")
    local log_console=$(config_get "logging.console")
    local log_history=$(config_get "logging.history_file")

    log_init "$log_file" "$log_level" "$log_console" "$log_history"

    # 设置日志轮转参数
    local max_size_mb=$(config_get "logging.max_size")
    LOG_MAX_SIZE=$((max_size_mb * 1024 * 1024))
    LOG_MAX_BACKUPS=$(config_get "logging.max_backups")

    log_info "Configuration initialized"
}

# 打印配置（调试用）
function config_dump() {
    log_info "Current configuration:"
    for key in "${!CONFIG[@]}"; do
        log_debug "  $key = ${CONFIG[$key]}"
    done
}

# 导出函数
export -f config_load_defaults
export -f config_trim
export -f config_parse
export -f config_get
export -f config_get_services
export -f config_get_service
export -f config_service_enabled
export -f config_init
export -f config_dump
