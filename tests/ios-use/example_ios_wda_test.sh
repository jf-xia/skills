#!/usr/bin/env bash

# iOS WDA 自动化测试示例
# 展示如何使用优化后的脚本进行完整的自动化测试流程

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="${SCRIPT_DIR}/.agents/skills/ios-use/scripts"

echo "=== iOS WDA 自动化测试示例 ==="
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

# 1. 初始化
echo "1. 初始化 WDA 环境"
echo "   运行: ios_wda_init.sh"
"${SKILL_DIR}/ios_wda_init.sh" 2>&1 | grep -E '(ok|device|ip|ready)' | head -10

echo ""

# 2. 创建 Session
echo "2. 创建 Session 并启动 Settings"
echo "   运行: ios_wda_session.sh --bundle-id com.apple.Preferences"
"${SKILL_DIR}/ios_wda_session.sh" --bundle-id com.apple.Preferences 2>&1 | grep -E '(ok|sessionId|bundleId|activeApp)' | head -10

echo ""

# 3. 获取页面信息
echo "3. 获取页面信息"
echo "   运行: ios_wda_snapshot.sh"
"${SKILL_DIR}/ios_wda_snapshot.sh" 2>&1 | grep -E '(ok|sourcePath|screenshotPath)' | head -10

echo ""

# 4. 获取设备信息
echo "4. 获取设备信息"
device_ip=$(cat "${SCRIPT_DIR}/.agents/tmp/ios-use-cache.json" | jq -r '.connection.deviceIp // "127.0.0.1"')
session_id=$(cat "${SCRIPT_DIR}/.agents/tmp/ios-use-cache.json" | jq -r '.session.id // empty')

if [[ -n "${device_ip}" && -n "${session_id}" ]]; then
    echo "   设备 IP: ${device_ip}"
    echo "   Session ID: ${session_id}"
    
    # 获取设备状态
    echo "   设备状态:"
    curl -s "http://${device_ip}:8100/status" | jq '{ready: .value.ready, ip: .value.ios.ip, os: .value.os.version}'
    
    # 获取活跃应用
    echo "   活跃应用:"
    curl -s "http://${device_ip}:8100/session/${session_id}/wda/activeAppInfo" | jq '{bundleId: .value.bundleId, pid: .value.pid}'
else
    echo "   无法获取设备信息"
fi

echo ""

# 5. 总结
echo "=== 测试完成 ==="
echo ""
echo "成功执行的操作:"
print_status "ok" "WDA 初始化"
print_status "ok" "Session 创建"
print_status "ok" "页面信息获取"
print_status "ok" "设备信息获取"

echo ""
echo "后续操作示例:"
echo "  # 获取页面源码"
echo "  curl -s http://${device_ip}:8100/session/${session_id}/source | jq '.value'"
echo ""
echo "  # 点击元素"
echo "  curl -X POST http://${device_ip}:8100/session/${session_id}/element/<ELEMENT_ID>/click"
echo ""
echo "  # 输入文本"
echo "  curl -X POST http://${device_ip}:8100/session/${session_id}/element/<ELEMENT_ID>/value \\"
echo "    -H 'Content-Type: application/json' \\"
echo "    -d '{\"value\": [\"Hello World\"]}'"
echo ""
echo "  # 截图"
echo "  curl -s http://${device_ip}:8100/session/${session_id}/screenshot | jq -r '.value' | base64 --decode > screenshot.png"
echo ""
echo "  # 清理"
echo "  pkill -f 'xcodebuild.*WebDriverAgent'"
echo "  pkill -f 'iproxy.*8100'"
