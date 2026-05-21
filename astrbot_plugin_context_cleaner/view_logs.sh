#!/usr/bin/env bash
set -e

# ==============================
# AstrBot Context Cleaner 日志查看脚本
# 从 AstrBot 日志中过滤并展示清理记录
# ==============================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

usage() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -f <路径>    指定 AstrBot 日志文件或目录"
    echo "  -n <行数>    显示最近 N 条清理记录（默认 20）"
    echo "  -w          实时监听日志（类似 tail -f）"
    echo "  -s          显示统计汇总"
    echo "  -h          显示帮助"
    echo ""
    echo "示例:"
    echo "  $0                             自动查找日志并显示最近 20 条记录"
    echo "  $0 -f /var/log/astrbot.log    指定日志文件"
    echo "  $0 -n 50                      显示最近 50 条"
    echo "  $0 -w                         实时监听"
    echo "  $0 -s                         显示统计汇总"
    exit 0
}

# 参数
LOG_PATH=""
LINES=20
WATCH=false
SUMMARY=false

while getopts "f:n:wsh" opt; do
    case $opt in
        f) LOG_PATH="$OPTARG" ;;
        n) LINES="$OPTARG" ;;
        w) WATCH=true ;;
        s) SUMMARY=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# 查找日志文件
find_log_file() {
    # 1. 指定的路径
    if [ -n "$LOG_PATH" ]; then
        if [ -f "$LOG_PATH" ]; then
            echo "$LOG_PATH"
            return 0
        elif [ -d "$LOG_PATH" ]; then
            # 在目录中找最近的日志
            local found
            found=$(find "$LOG_PATH" -name "*.log" -type f 2>/dev/null | sort -r | head -1)
            if [ -n "$found" ]; then
                echo "$found"
                return 0
            fi
        fi
        err "未找到日志文件: $LOG_PATH"
        return 1
    fi

    # 2. 常见 AstrBot 日志路径
    local search_paths=(
        "$(pwd)/../"
        "$(pwd)/"
        "$(pwd)/../../"
        "/var/log/astrbot/"
    )
    for dir in "${search_paths[@]}"; do
        local found
        found=$(find "$dir" -maxdepth 3 -name "astrbot*.log" -o -name "*.log" 2>/dev/null \
                | grep -iv ".git/" \
                | head -1)
        if [ -n "$found" ]; then
            echo "$found"
            return 0
        fi
    done

    err "未找到 AstrBot 日志文件"
    err "请用 -f 参数指定日志文件路径"
    return 1
}

# 解析并格式化单条 ContextCleaner 日志
format_log() {
    local line="$1"
    # 提取时间戳（如果有）
    local ts="$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')"
    # 提取会话
    local session="$(echo "$line" | grep -oP '\[([^\]]+)\]' | sed -n '1p' | tr -d '[]')"
    [ -z "$session" ] && session="..."
    # 提取清理轮数
    local rounds="$(echo "$line" | grep -oP '清理 (\d+) 轮' | grep -oP '\d+')"
    # 提取移除内容
    local removed="$(echo "$line" | grep -oP '移除 .*? \|' | head -1)"
    removed="${removed% |}"
    # 提取节省量
    local saved="$(echo "$line" | grep -oP '节省 .*? \|' | head -1)"
    saved="${saved% |}"
    # 提取保留轮数
    local kept="$(echo "$line" | grep -oP '保留最近 \d+ 轮' | head -1)"

    local status=""
    if echo "$line" | grep -q "清理完成"; then
        status="${GREEN}✓${NC}"
    elif echo "$line" | grep -q "清理失败"; then
        status="${RED}✗${NC}"
    fi

    # 时间
    if [ -n "$ts" ]; then
        echo -e "${GRAY}[${ts}]${NC} ${status} ${YELLOW}${session}${NC}"
    else
        echo -e "${status} ${YELLOW}${session}${NC}"
    fi
    [ -n "$rounds" ]   && echo -e "  ${GRAY}├─${NC} 清理轮次: ${BOLD}${rounds}${NC}"
    [ -n "$removed" ]  && echo -e "  ${GRAY}├─${NC} 移除内容: ${CYAN}${removed#移除 }${NC}"
    [ -n "$saved" ]    && echo -e "  ${GRAY}├─${NC} ${saved}"
    [ -n "$kept" ]     && echo -e "  ${GRAY}└─${NC} ${kept}"
}

# 显示统计汇总
show_summary() {
    local log_file="$1"
    echo -e "${BOLD}═══════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Context Cleaner 清理统计${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════${NC}"

    local entries
    entries=$(grep "\[ContextCleaner\]" "$log_file" 2>/dev/null || true)
    local total
    total=$(echo "$entries" | grep "清理完成" | wc -l)
    local fails
    fails=$(echo "$entries" | grep "清理失败" | wc -l)

    echo ""
    echo -e "  总清理次数: ${BOLD}${total}${NC} 次"
    echo -e "  失败次数:   ${RED}${fails}${NC} 次"

    if [ "$total" -gt 0 ]; then
        # 解析节省的字符数
        local chars_saved=0
        local chars_saved_sum
        chars_saved_sum=$(echo "$entries" | grep -oP '节省 \d+ 字符' | grep -oP '\d+' | awk '{s+=$1} END {print s}')
        chars_saved=$((chars_saved_sum))
        local tokens_saved=$((chars_saved / 4))
        echo -e "  总节省:     ${GREEN}${chars_saved}${NC} 字符 ≈ ${GREEN}${tokens_saved}${NC} tokens"

        # 各类型移除统计
        local think=0
        local tc=0
        local tr=0
        while IFS= read -r entry; do
            local t
            t=$(echo "$entry" | grep -oP '思考块x\d+' | grep -oP '\d+')
            think=$((think + (t)))
        done <<< "$(echo "$entries" | grep "思考块")"

        while IFS= read -r entry; do
            local t
            t=$(echo "$entry" | grep -oP '工具调用x\d+' | grep -oP '\d+')
            tc=$((tc + (t)))
        done <<< "$(echo "$entries" | grep "工具调用")"

        while IFS= read -r entry; do
            local t
            t=$(echo "$entry" | grep -oP '工具结果x\d+' | grep -oP '\d+')
            tr=$((tr + (t)))
        done <<< "$(echo "$entries" | grep "工具结果")"

        echo ""
        echo -e "  移除明细:"
        [ "$think" -gt 0 ] && echo -e "    ${GRAY}├─${NC} 思考块:     ${BOLD}${think}${NC} 个"
        [ "$tc" -gt 0 ]    && echo -e "    ${GRAY}├─${NC} 工具调用:   ${BOLD}${tc}${NC} 次"
        [ "$tr" -gt 0 ]    && echo -e "    ${GRAY}└─${NC} 工具结果:   ${BOLD}${tr}${NC} 条"
    fi
    echo ""
    echo -e "  日志文件: ${GRAY}${log_file}${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════${NC}"
}

# 主流程
main() {
    local log_file
    log_file=$(find_log_file)
    if [ $? -ne 0 ]; then
        exit 1
    fi

    echo -e "${GRAY}日志文件: ${log_file}${NC}"
    echo ""

    if [ "$SUMMARY" = true ]; then
        show_summary "$log_file"
        exit 0
    fi

    if [ "$WATCH" = true ]; then
        echo -e "${YELLOW}实时监听中 (Ctrl+C 退出)...${NC}"
        tail -f "$log_file" | while IFS= read -r line; do
            if echo "$line" | grep -q "\[ContextCleaner\]"; then
                echo ""
                format_log "$line"
                echo ""
            fi
        done
    else
        local entries
        entries=$(grep "\[ContextCleaner\]" "$log_file" 2>/dev/null | tail -n "$LINES")
        if [ -z "$entries" ]; then
            echo -e "${YELLOW}没有找到 ContextCleaner 日志记录${NC}"
            exit 0
        fi

        echo -e "最近 ${BOLD}${LINES}${NC} 条清理记录:"
        echo ""
        local count=1
        while IFS= read -r line; do
            echo -e "${GRAY}── #${count} ───────────────────────────────${NC}"
            format_log "$line"
            count=$((count + 1))
        done <<< "$(echo "$entries" | tail -n "$LINES")"
        echo ""
        echo -e "${GRAY}提示: 加 -s 查看统计汇总，加 -w 实时监听${NC}"
    fi
}

main
