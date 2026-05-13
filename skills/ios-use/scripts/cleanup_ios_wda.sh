#!/usr/bin/env bash

# 清理 iOS WDA 相关进程
echo "清理 iOS WDA 相关进程..."

# 停止 WDA
echo "停止 WDA..."
pkill -f "xcodebuild.*WebDriverAgent" 2>/dev/null || echo "  没有找到 WDA 进程"

# 停止 iproxy
echo "停止 iproxy..."
pkill -f "iproxy.*8100" 2>/dev/null || echo "  没有找到 iproxy 进程"

# 等待进程停止
sleep 2

# 验证进程已停止
echo ""
echo "验证进程状态:"
if pgrep -f "xcodebuild.*WebDriverAgent" >/dev/null; then
    echo "  ✗ WDA 仍在运行"
else
    echo "  ✓ WDA 已停止"
fi

if pgrep -f "iproxy.*8100" >/dev/null; then
    echo "  ✗ iproxy 仍在运行"
else
    echo "  ✓ iproxy 已停止"
fi

echo ""
echo "清理完成"
