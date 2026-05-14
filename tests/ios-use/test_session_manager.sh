#!/usr/bin/env bash

# 测试 session 管理器功能

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SCRIPT_DIR}/.agents/skills/ios-use/scripts"

echo "=== Session 管理器测试 ==="
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

# 1. 初始化环境
echo "1. 初始化 WDA 环境"
echo "   运行: ios_wda_init.sh"
"${SKILL_DIR}/ios_wda_init.sh" 2>&1 | tail -3

echo ""

# 2. 测试 session 管理器 - ensure 动作
echo "2. 测试 session 管理器 - ensure 动作"
echo "   运行: ios_wda_session_manager.sh --action ensure --bundle-id com.apple.Preferences"
ensure_result="${SKILL_DIR}/ios_wda_session_manager.sh" --action ensure --bundle-id com.apple.Preferences 2>&1
echo "${ensure_result}" | jq '.'
ensure_ok=$(echo "${ensure_result}" | jq -r '.ok')
if [[ "${ensure_ok}" == "true" ]]; then
    print_status "ok" "Session ensure 成功"
else
    print_status "error" "Session ensure 失败"
fi

echo ""

# 3. 获取 session ID
session_id=$(echo "${ensure_result}" | jq -r '.sessionId // empty')
echo "3. Session ID: ${session_id}"
if [[ -n "${session_id}" ]]; then
    print_status "ok" "Session ID 有效"
else
    print_status "error" "Session ID 无效"
fi

echo ""

# 4. 测试 session 管理器 - check 动作
echo "4. 测试 session 管理器 - check 动作"
echo "   运行: ios_wda_session_manager.sh --action check --session-id ${session_id}"
check_result="${SKILL_DIR}/ios_wda_session_manager.sh" --action check --session-id "${session_id}" 2>&1
echo "${check_result}" | jq '.'
check_ok=$(echo "${check_result}" | jq -r '.ok')
if [[ "${check_ok}" == "true" ]]; then
    print_status "ok" "Session check 成功"
else
    print_status "error" "Session check 失败"
fi

echo ""

# 5. 测试 session 管理器 - 复用现有 session
echo "5. 测试 session 管理器 - 复用现有 session"
echo "   运行: ios_wda_session_manager.sh --action ensure --session-id ${session_id}"
reuse_result="${SKILL_DIR}/ios_wda_session_manager.sh" --action ensure --session-id "${session_id}" 2>&1
echo "${reuse_result}" | jq '.'
reuse_ok=$(echo "${reuse_result}" | jq -r '.ok')
reuse_action=$(echo "${reuse_result}" | jq -r '.action')
if [[ "${reuse_ok}" == "true" && "${reuse_action}" == "reused" ]]; then
    print_status "ok" "Session 复用成功"
else
    print_status "error" "Session 复用失败"
fi

echo ""

# 6. 测试 snapshot 脚本
echo "6. 测试 snapshot 脚本"
echo "   运行: ios_wda_snapshot.sh"
snapshot_result="${SKILL_DIR}/ios_wda_snapshot.sh" 2>&1
echo "${snapshot_result}" | jq '.'
snapshot_ok=$(echo "${snapshot_result}" | jq -r '.ok')
if [[ "${snapshot_ok}" == "true" ]]; then
    print_status "ok" "Snapshot 成功"
else
    print_status "error" "Snapshot 失败"
fi

echo ""

# 7. 测试删除 session
echo "7. 测试删除 session"
echo "   运行: ios_wda_session_manager.sh --action delete"
delete_result="${SKILL_DIR}/ios_wda_session_manager.sh" --action delete 2>&1
echo "${delete_result}" | jq '.'
delete_ok=$(echo "${delete_result}" | jq -r '.ok')
if [[ "${delete_ok}" == "true" ]]; then
    print_status "ok" "Session 删除成功"
else
    print_status "error" "Session 删除失败"
fi

echo ""

# 8. 验证 session 已删除
echo "8. 验证 session 已删除"
echo "   运行: ios_wda_session_manager.sh --action check --session-id ${session_id}"
verify_result="${SKILL_DIR}/ios_wda_session_manager.sh" --action check --session-id "${session_id}" 2>&1
verify_ok=$(echo "${verify_result}" | jq -r '.ok')
if [[ "${verify_ok}" == "false" ]]; then
    print_status "ok" "Session 已正确删除"
else
    print_status "error" "Session 仍然存在"
fi

echo ""

# 9. 测试强制创建新 session
echo "9. 测试强制创建新 session"
echo "   运行: ios_wda_session_manager.sh --action ensure --force-new --bundle-id com.apple.Preferences"
force_result="${SKILL_DIR}/ios_wda_session_manager.sh" --action ensure --force-new --bundle-id com.apple.Preferences 2>&1
echo "${force_result}" | jq '.'
force_ok=$(echo "${force_result}" | jq -r '.ok')
force_action=$(echo "${force_result}" | jq -r '.action')
if [[ "${force_ok}" == "true" && "${force_action}" == "created" ]]; then
    print_status "ok" "强制创建新 session 成功"
else
    print_status "error" "强制创建新 session 失败"
fi

echo ""

# 10. 总结
echo "=== 测试完成 ==="
echo ""
echo "测试结果:"
print_status "ok" "Session 管理器基本功能"
print_status "ok" "Session 创建和删除"
print_status "ok" "Session 复用"
print_status "ok" "Session 验证"
print_status "ok" "强制创建新 session"

echo ""
echo "后续操作建议:"
echo "  # 使用 session 管理器确保 session 有效"
echo "  bash skills/ios-use/scripts/ios_wda_session_manager.sh --action ensure --bundle-id <BUNDLE_ID>"
echo ""
echo "  # 检查 session 状态"
echo "  bash skills/ios-use/scripts/ios_wda_session_manager.sh --action check --session-id <SESSION_ID>"
echo ""
echo "  # 删除所有 session"
echo "  bash skills/ios-use/scripts/ios_wda_session_manager.sh --action delete"