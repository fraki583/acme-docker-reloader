#!/bin/bash
# service.sh - 服务管理模块
# 提供服务重启、健康检查等功能

# 执行服务命令
function service_execute() {
    local service_name="$1"
    local command="$2"
    local timeout="$3"

    log_info "Executing command for service '$service_name': $command"
    log_history "service_execute" "started" "service=$service_name cmd=$command"

    local start_time=$(date +%s)
    local output
    local exit_code

    # 创建临时文件保存输出
    local temp_output=$(mktemp)

    # 执行命令（带超时）
    if [[ $timeout -gt 0 ]]; then
        timeout "$timeout" bash -c "$command" > "$temp_output" 2>&1
        exit_code=$?
    else
        bash -c "$command" > "$temp_output" 2>&1
        exit_code=$?
    fi

    output=$(cat "$temp_output")
    rm -f "$temp_output"

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    # 记录结果
    if [[ $exit_code -eq 0 ]]; then
        log_info "Service '$service_name' command completed successfully (took ${duration}s)"
        log_history "service_execute" "success" "service=$service_name duration=${duration}s"
        return 0
    elif [[ $exit_code -eq 124 ]]; then
        log_error "Service '$service_name' command timed out after ${timeout}s"
        log_error "Output: $output"
        log_history "service_execute" "timeout" "service=$service_name timeout=${timeout}s output=$output"
        return 1
    else
        log_error "Service '$service_name' command failed with exit code $exit_code"
        log_error "Output: $output"
        log_history "service_execute" "failed" "service=$service_name exit_code=$exit_code output=$output"
        return 1
    fi
}

# 执行单个服务的重启
function service_reload_one() {
    local service_name="$1"

    log_info "Reloading service: $service_name"

    # 检查服务是否启用
    if ! config_service_enabled "$service_name"; then
        log_warn "Service '$service_name' is disabled, skipping"
        return 0
    fi

    # 获取服务配置
    local command=$(config_get_service "$service_name" "command")
    local timeout=$(config_get_service "$service_name" "timeout" "0")
    local pre_command=$(config_get_service "$service_name" "pre_command")
    local post_command=$(config_get_service "$service_name" "post_command")

    # 使用全局超时如果服务未指定
    if [[ "$timeout" == "0" ]]; then
        timeout=$(config_get "communication.timeout")
    fi

    # 验证命令
    if [[ -z "$command" ]]; then
        log_error "Service '$service_name' has no command configured"
        return 1
    fi

    # 执行前置命令
    if [[ -n "$pre_command" ]]; then
        log_info "Executing pre-command for '$service_name': $pre_command"
        if ! service_execute "${service_name}_pre" "$pre_command" "$timeout"; then
            log_error "Pre-command failed for service '$service_name'"
            return 1
        fi
    fi

    # 执行主命令
    if ! service_execute "$service_name" "$command" "$timeout"; then
        log_error "Failed to reload service '$service_name'"
        return 1
    fi

    # 执行后置命令
    if [[ -n "$post_command" ]]; then
        log_info "Executing post-command for '$service_name': $post_command"
        if ! service_execute "${service_name}_post" "$post_command" "$timeout"; then
            log_warn "Post-command failed for service '$service_name' (non-fatal)"
        fi
    fi

    log_info "Service '$service_name' reloaded successfully"
    return 0
}

# 执行所有配置的服务重启
function service_reload_all() {
    log_info "Starting reload for all configured services"

    local services=$(config_get_services)

    if [[ -z "$services" ]]; then
        log_warn "No services configured"
        return 1
    fi

    local failed_services=""
    local success_count=0
    local total_count=0

    for service in $services; do
        ((total_count++))

        if service_reload_one "$service"; then
            ((success_count++))
        else
            failed_services="$failed_services $service"
        fi
    done

    log_info "Reload completed: $success_count/$total_count services succeeded"

    if [[ -n "$failed_services" ]]; then
        log_error "Failed services:$failed_services"
        log_history "service_reload_all" "partial_failure" "succeeded=$success_count failed=$((total_count - success_count)) failed_list=$failed_services"
        return 1
    fi

    log_history "service_reload_all" "success" "count=$total_count"
    return 0
}

# 处理重启请求（IPC回调函数）
function service_handle_reload_request() {
    local request_data="$1"

    log_info "Handling reload request: $request_data"

    case "$request_data" in
        restart|reload)
            # 执行所有服务重启
            if service_reload_all; then
                return 0
            else
                return 1
            fi
            ;;
        restart:*|reload:*)
            # 执行特定服务重启
            local service_name="${request_data#*:}"
            if service_reload_one "$service_name"; then
                return 0
            else
                return 1
            fi
            ;;
        *)
            log_error "Unknown request: $request_data"
            return 1
            ;;
    esac
}

# 导出函数
export -f service_execute
export -f service_reload_one
export -f service_reload_all
export -f service_handle_reload_request
