---
name: ios-use
description: "操作 iOS / iPhone 真机与模拟器自动化。用于 WebDriverAgent 场景下的设备发现、WDA 启动、Session 创建、页面读取、元素交互、手势、系统控制、故障恢复与性能调优。适用于通过 xcodebuild、simctl、curl 或 WDA REST API 完成移动端自动化任务。"
argument-hint: "描述任务，例如：在真机启动 WDA 并创建 session；读取 source 后点击按钮；处理权限弹窗并截图"
user-invocable: true
---

# 操作 iOS / iPhone 真机与模拟器自动化技能

## 适用场景
- 在真机或模拟器上启动、复用或重启 WebDriverAgent
- 通过 WDA REST API 建立 session、读取页面、执行点击、输入、手势和截图
- 控制应用生命周期、系统弹窗、锁屏、方向、位置等设备能力
- 排查签名、连接、无 session、元素失效、键盘和超时问题

## 快速路径（推荐）

**最简单的使用方式：** 只需两条命令即可开始自动化操作。

```bash
# 1. 创建 session 并启动应用（自动处理设备检查、iproxy、WDA）
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 2. 获取页面源码
curl -s http://<DEVICE_IP>:8100/session/<SESSION_ID>/source | jq '.value'
```

**详细步骤：**

```bash
# 1. 初始化（检查设备、启动 iproxy、启动 WDA）
bash skills/ios-use/scripts/ios_wda_init.sh

# 2. 创建 session 并启动应用
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 3. 获取页面源码
bash skills/ios-use/scripts/ios_wda_snapshot.sh
```

## 详细使用流程

### 1. 初始化

```bash
# 自动检查设备、启动 iproxy、启动 WDA
bash skills/ios-use/scripts/ios_wda_init.sh

# 指定设备
bash skills/ios-use/scripts/ios_wda_init.sh --udid 00008140-001465202E10801C

# 指定 host 和 port
bash skills/ios-use/scripts/ios_wda_init.sh --host 192.168.1.107 --port 8100
```

**输出说明：**
```json
{
  "ok": true,
  "device": {
    "name": "iPhone",
    "udid": "00008140-001465202E10801C",
    "ip": "192.168.1.107"
  },
  "wda": {
    "ready": true,
    "runDir": "./tmp/260513210741"
  }
}
```

### 2. 创建 Session

```bash
# 创建 session 并启动应用
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences

# 强制创建新 session
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences --force-new

# 删除 session
bash skills/ios-use/scripts/ios_wda_session.sh --delete
```

**输出说明：**
```json
{
  "ok": true,
  "action": "created",
  "sessionId": "90F28444-A1FC-4FA6-BAF1-F0584F2B9E14",
  "bundleId": "com.apple.Preferences",
  "activeApp": {
    "value": {
      "bundleId": "com.apple.Preferences"
    }
  }
}
```

### 3. 获取页面信息

```bash
# 获取页面源码、可访问性信息、截图
bash skills/ios-use/scripts/ios_wda_snapshot.sh

# 只获取源码
bash skills/ios-use/scripts/ios_wda_snapshot.sh --only-source

# 只获取截图
bash skills/ios-use/scripts/ios_wda_snapshot.sh --only-screenshot
```

### 4. 元素交互

```bash
# 输入文本
bash skills/ios-use/scripts/ios_wda_type.sh --using name --locator "Username" --text-file input.txt

# 使用 curl 直接调用 WDA API
# 获取元素
curl -s http://<DEVICE_IP>:8100/session/<SESSION_ID>/source | jq '.value'

# 点击元素
curl -X POST http://<DEVICE_IP>:8100/session/<SESSION_ID>/element/<ELEMENT_ID>/click

# 输入文本
curl -X POST http://<DEVICE_IP>:8100/session/<SESSION_ID>/element/<ELEMENT_ID>/value \
  -H 'Content-Type: application/json' \
  -d '{"value": ["Hello World"]}'
```

## WiFi 连接场景

当设备通过 WiFi 连接时，脚本会自动：

1. 检测设备 IP 地址
2. 尝试直接连接设备 IP（如果 iproxy 不可用）
3. 缓存设备 IP 以便后续使用

**手动指定设备 IP：**
```bash
bash skills/ios-use/scripts/ios_wda_init.sh --host 192.168.1.107
```

## 缓存文件

缓存文件位于 `./tmp/ios-use-cache.json`，包含：

```json
{
  "device": {
    "udid": "00008140-001465202E10801C",
    "name": "iPhone",
    "osVersion": "26.4.2"
  },
  "connection": {
    "host": "127.0.0.1",
    "port": 8100,
    "deviceIp": "192.168.1.107"
  },
  "wda": {
    "ready": true
  },
  "session": {
    "id": "90F28444-A1FC-4FA6-BAF1-F0584F2B9E14",
    "bundleId": "com.apple.Preferences"
  }
}
```

## 故障排查

### 1. WDA 无法启动

```bash
# 检查日志
cat ./tmp/*/wda-background.log

# 清理并重新启动
pkill -f "xcodebuild.*WebDriverAgent"
pkill -f "iproxy.*8100"
bash skills/ios-use/scripts/ios_wda_init.sh
```

### 2. 连接失败

```bash
# 检查设备 IP
curl -s http://<DEVICE_IP>:8100/status

# 检查 iproxy
lsof -i :8100

# 重新初始化
bash skills/ios-use/scripts/ios_wda_init.sh
```

### 3. Session 创建失败

```bash
# 检查 WDA 状态
curl -s http://<DEVICE_IP>:8100/status | jq '.value.ready'

# 强制创建新 session
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences --force-new
```

## 清理命令

```bash
# 停止所有进程
bash skills/ios-use/scripts/cleanup_ios_wda.sh

# 或手动清理
pkill -f "xcodebuild.*WebDriverAgent"
pkill -f "iproxy.*8100"
```

## 高级用法

### 使用环境变量

```bash
export IOS_WDA_DEFAULT_HOST="192.168.1.107"
export IOS_WDA_DEFAULT_PORT="8100"
bash skills/ios-use/scripts/ios_wda_init.sh
```

### 组合使用

```bash
# 完整流程
bash skills/ios-use/scripts/ios_wda_init.sh && \
bash skills/ios-use/scripts/ios_wda_session.sh --bundle-id com.apple.Preferences && \
bash skills/ios-use/scripts/ios_wda_snapshot.sh
```

### 直接使用 WDA API

```bash
# 获取 session 列表
curl -s http://<DEVICE_IP>:8100/session

# 获取设备信息
curl -s http://<DEVICE_IP>:8100/status

# 获取屏幕方向
curl -s http://<DEVICE_IP>:8100/session/<SESSION_ID>/orientation

# 锁定屏幕
curl -X POST http://<DEVICE_IP>:8100/session/<SESSION_ID>/wda/lock
```

## 完成标准

- WDA 的 `GET /status` 或 `GET /wda/healthcheck` 可用
- Session 创建成功或会话仍然有效
- 每次交互后至少通过元素状态、页面源码、截图或应用状态之一验证结果
- 缓存文件已更新到 `./tmp/ios-use-cache.json`

## 参考资料

- [启动与 Session](./references/startup-and-session.md)
- [命令参考](./references/command-reference.md)
- [输入与键盘](./references/input-and-keyboard.md)
- [应用与设备控制](./references/app-and-device-control.md)
- [视觉驱动与性能](./references/visual-and-performance.md)
- [故障排查](./references/troubleshooting.md)
- [限制与取舍](./references/limitations.md)
