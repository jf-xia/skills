#!/usr/bin/env bash

# 清理 iOS WDA 相关进程
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

ios_wda_require_tools jq pkill pgrep

wda_stopped="false"
iproxy_stopped="false"

# 停止 WDA
if pgrep -f "xcodebuild.*WebDriverAgent" >/dev/null 2>&1; then
  pkill -f "xcodebuild.*WebDriverAgent" 2>/dev/null || true
  wda_stopped="true"
fi

# 停止 iproxy
iproxy_port="${IOS_WDA_DEFAULT_PORT}"
if pgrep -f "iproxy.*${iproxy_port}" >/dev/null 2>&1; then
  pkill -f "iproxy.*${iproxy_port}" 2>/dev/null || true
  iproxy_stopped="true"
fi

sleep 1

# 验证
wda_running="false"
iproxy_running="false"
if pgrep -f "xcodebuild.*WebDriverAgent" >/dev/null 2>&1; then
  wda_running="true"
fi
if pgrep -f "iproxy.*${iproxy_port}" >/dev/null 2>&1; then
  iproxy_running="true"
fi

# 清除缓存中的 session
ios_wda_init_cache_file
ios_wda_cache_clear_session

result_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --argjson wdaStopped "${wda_stopped}" \
  --argjson wdaRunning "${wda_running}" \
  --argjson iproxyStopped "${iproxy_stopped}" \
  --argjson iproxyRunning "${iproxy_running}" \
  '{
    ok: (($wdaRunning | not) and ($iproxyRunning | not)),
    checkedAt: $checkedAt,
    wda: { stopped: $wdaStopped, stillRunning: $wdaRunning },
    iproxy: { stopped: $iproxyStopped, stillRunning: $iproxyRunning }
  }')"

ios_wda_emit_json "${result_payload}"
