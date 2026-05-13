#!/usr/bin/env bash

# 测试 iOS WDA 技能的完整流程

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SCRIPT_DIR}/.agents/skills/ios-use/scripts"

echo "=== iOS WDA 技能测试 ==="
echo ""

# 1. 初始化
echo "1. 运行初始化..."
"${SKILL_DIR}/ios_wda_init.sh" 2>&1 | tail -5

echo ""

# 2. 创建 session
echo "2. 创建 session..."
"${SKILL_DIR}/ios_wda_session.sh" --bundle-id com.apple.Preferences 2>&1 | tail -5

echo ""

# 3. 获取页面信息
echo "3. 获取页面信息..."
"${SKILL_DIR}/ios_wda_snapshot.sh" 2>&1 | tail -5

echo ""

# 4. 显示缓存信息
echo "4. 缓存信息:"
cache_file="${SCRIPT_DIR}/.agents/tmp/ios-use-cache.json"
if [[ -f "${cache_file}" ]]; then
    device_ip=$(jq -r '.connection.deviceIp // "N/A"' "${cache_file}")
    session_id=$(jq -r '.session.id // "N/A"' "${cache_file}")
    echo "   设备 IP: ${device_ip}"
    echo "   Session ID: ${session_id}"
fi

echo ""
echo "=== 测试完成 ==="
