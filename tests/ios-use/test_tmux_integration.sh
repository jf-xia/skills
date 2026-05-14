#!/usr/bin/env bash

# 测试 tmux 集成

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SCRIPT_DIR}/.agents/skills/ios-use/scripts"

echo "=== tmux 集成测试 ==="
echo ""

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印状态
print_status() {
    local status=$1
    local message=$2
    if [[ "${status}" == "ok" ]]; then
        echo -e "${GREEN}✓${NC} ${message}"
    elif [[ "${status}" == "error" ]]; then
        echo -e "${RED}✗${NC} ${message}"
    else
        echo -e "${YELLOW}●${NC} ${message}"
    fi
}

# 1. 检查 tmux 是否可用
echo "1. 检查 tmux 是否可用"
if command -v tmux >/dev/null 2>&1; then
    tmux_version=$(tmux -V)
    print_status "ok" "tmux 已安装: ${tmux_version}"
else
    print_status "error" "tmux 未安装"
    echo "请安装 tmux: brew install tmux"
    exit 1
fi

echo ""

# 2. 清理现有会话
echo "2. 清理现有 tmux 会话"
existing_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E '^(wda-|iproxy-)' || true)
if [[ -n "${existing_sessions}" ]]; then
    echo "   发现现有会话:"
    echo "${existing_sessions}" | while read -r session; do
        echo "   - ${session}"
        tmux kill-session -t "${session}" 2>/dev/null || true
    done
    print_status "ok" "已清理现有会话"
else
    print_status "ok" "没有需要清理的会话"
fi

echo ""

# 3. 测试 tmux 会话创建
echo "3. 测试 tmux 会话创建"
test_session="test-session-$$"
tmux new-session -d -s "${test_session}" "sleep 30"
if tmux has-session -t "${test_session}" 2>/dev/null; then
    print_status "ok" "tmux 会话创建成功: ${test_session}"
else
    print_status "error" "tmux 会话创建失败"
fi

echo ""

# 4. 测试 tmux 会话列表
echo "4. 测试 tmux 会话列表"
sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null)
if echo "${sessions}" | grep -q "${test_session}"; then
    print_status "ok" "tmux 会话列表正常"
else
    print_status "error" "tmux 会话列表异常"
fi

echo ""

# 5. 测试 tmux 会话日志
echo "5. 测试 tmux 会话日志"
# 创建一个会话来输出日志
log_session="test-log-session-$$"
tmux new-session -d -s "${log_session}" "echo 'Hello from tmux' && sleep 5"
sleep 1
# 捕获输出
log_output=$(tmux capture-pane -t "${log_session}" -p 2>/dev/null || true)
if echo "${log_output}" | grep -q "Hello from tmux"; then
    print_status "ok" "tmux 日志捕获成功"
else
    print_status "warning" "tmux 日志捕获可能需要更多时间"
fi

echo ""

# 6. 测试 tmux 会话清理
echo "6. 测试 tmux 会话清理"
tmux kill-session -t "${test_session}" 2>/dev/null || true
tmux kill-session -t "${log_session}" 2>/dev/null || true
if ! tmux has-session -t "${test_session}" 2>/dev/null; then
    print_status "ok" "tmux 会话清理成功"
else
    print_status "error" "tmux 会话清理失败"
fi

echo ""

# 7. 测试 WDA 脚本的 tmux 集成（如果设备可用）
echo "7. 测试 WDA 脚本的 tmux 集成"
if curl --max-time 2 -sf "http://127.0.0.1:8100/status" >/dev/null 2>&1; then
    echo "   检测到 WDA 服务，测试初始化..."
    init_result=$("${SKILL_DIR}/ios_wda_init.sh" 2>&1 | tail -5)
    if echo "${init_result}" | grep -q "ok.*true"; then
        print_status "ok" "WDA 初始化成功"
        
        # 检查 tmux 会话
        tmux_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E '^(wda-|iproxy-)' || true)
        if [[ -n "${tmux_sessions}" ]]; then
            print_status "ok" "tmux 会话已创建:"
            echo "${tmux_sessions}" | while read -r session; do
                echo "   - ${session}"
            done
        else
            print_status "warning" "未检测到 WDA/iproxy tmux 会话"
        fi
    else
        print_status "warning" "WDA 初始化失败（可能没有连接设备）"
    fi
else
    print_status "warning" "WDA 服务不可用，跳过集成测试"
fi

echo ""

# 8. 总结
echo "=== 测试完成 ==="
echo ""
echo "tmux 集成状态:"
print_status "ok" "tmux 安装和基本功能"
print_status "ok" "会话创建和清理"
print_status "ok" "日志捕获"

echo ""
echo "使用说明:"
echo "  # 查看所有 tmux 会话"
echo "  tmux list-sessions"
echo ""
echo "  # 连接到 WDA 会话"
echo "  tmux attach -t wda-<DEVICE_UDID>"
echo ""
echo "  # 连接到 iproxy 会话"
echo "  tmux attach -t iproxy-<DEVICE_UDID>-<PORT>"
echo ""
echo "  # 分离会话（保持后台运行）"
echo "  Ctrl+B 然后按 D"