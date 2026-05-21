#!/usr/bin/env bash
set -e

# ==============================
# AstrBot Context Cleaner 插件安装脚本
# ==============================

PLUGIN_NAME="astrbot_plugin_context_cleaner"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
err()   { echo -e "${RED}[✗]${NC} $1"; }

# 查找 AstrBot 数据目录
find_data_dir() {
    # 1. 当前目录下
    if [ -f "cmd_config.json" ] && [ -d "plugins" ]; then
        echo "$(pwd)"
        return 0
    fi
    # 2. 父目录
    if [ -f "../cmd_config.json" ] && [ -d "../plugins" ]; then
        cd .. && echo "$(pwd)"
        return 0
    fi
    # 3. ASTRBOT_DATA_DIR 环境变量
    if [ -n "$ASTRBOT_DATA_DIR" ] && [ -f "$ASTRBOT_DATA_DIR/cmd_config.json" ]; then
        echo "$ASTRBOT_DATA_DIR"
        return 0
    fi
    return 1
}

# 安装
install_plugin() {
    local data_dir="$1"
    local plugin_dir="$data_dir/plugins/$PLUGIN_NAME"

    # 创建插件目录
    mkdir -p "$plugin_dir"
    info "创建插件目录: $plugin_dir"

    # 复制文件
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    cp "$SCRIPT_DIR/main.py"       "$plugin_dir/"
    cp "$SCRIPT_DIR/_conf_schema.json" "$plugin_dir/"
    cp "$SCRIPT_DIR/metadata.yaml" "$plugin_dir/"
    info "复制插件文件: main.py, _conf_schema.json, metadata.yaml"

    # 注册到 plugin_set
    local cfg="$data_dir/cmd_config.json"
    if python3 -c "
import json
with open('$cfg', 'r') as f:
    cfg = json.load(f)
if '$PLUGIN_NAME' not in cfg.get('plugin_set', []):
    cfg.setdefault('plugin_set', []).append('$PLUGIN_NAME')
    with open('$cfg', 'w') as f:
        json.dump(cfg, f, indent=2, ensure_ascii=False)
    print('enabled')
else:
    print('exists')
" 2>/dev/null; then
        result=$(python3 -c "
import json
with open('$cfg', 'r') as f:
    cfg = json.load(f)
print('enabled' if '$PLUGIN_NAME' in cfg.get('plugin_set', []) else 'exists')
        " 2>/dev/null)
        if [ "$result" = "enabled" ]; then
            info "已添加到 plugin_set"
        else
            warn "已在 plugin_set 中，跳过"
        fi
    else
        warn "无法更新 cmd_config.json，请手动在 plugin_set 中添加 \"$PLUGIN_NAME\""
    fi

    echo ""
    info "安装完成！请重启 AstrBot 使插件生效。"
    echo ""
    echo "  插件目录: $plugin_dir"
    echo "  配置文件: $cfg"
}

# 主流程
echo ""
echo "  AstrBot Context Cleaner 插件安装"
echo "  ================================="
echo ""

DATA_DIR=$(find_data_dir)
if [ -z "$DATA_DIR" ]; then
    err "未找到 AstrBot 数据目录（包含 cmd_config.json 和 plugins/ 的目录）"
    err "请确认:"
    err "  - 脚本在 AstrBot 数据目录下运行"
    err "  - 或设置环境变量: export ASTRBOT_DATA_DIR=/path/to/astrbot/data"
    exit 1
fi

info "检测到 AstrBot 数据目录: $DATA_DIR"
install_plugin "$DATA_DIR"
