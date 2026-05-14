#!/usr/bin/env bash

# 清理 iOS WDA 相关进程（支持 tmux）
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

ios_wda_require_tools jq

# 停止 keep-alive
ios_wda_keepalive_stop "${IOS_WDA_DEFAULT_PORT}"

wda_stopped="false"
iproxy_stopped="false"
wda_running="false"
iproxy_running="false"

# 停止 WDA tmux 会话
wda_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E '^wda-' || true)
if [[ -n "${wda_sessions}" ]]; then
  while IFS= read -r session; do
    echo "   停止 WDA tmux 会话: ${session}" >&2
    tmux kill-session -t "${session}" 2>/dev/null || true
    wda_stopped="true"
  done <<< "${wda_sessions}"
fi

# 停止 iproxy tmux 会话
iproxy_sessions=$(tmux list-sessions -F "#{session_name}" 2>/dev/null | grep -E '^iproxy-' || true)
if [[ -n "${iproxy_sessions}" ]]; then
  while IFS= read -r session; do
    echo "   停止 iproxy tmux 会话: ${session}" >&2
    tmux kill-session -t "${session}" 2>/dev/null || true
    iproxy_stopped="true"
  done <<< "${iproxy_sessions}"
fi

# 也清理可能残留的传统进程
if pgrep -f "xcodebuild.*WebDriverAgent" >/dev/null 2>&1; then
  pkill -f "xcodebuild.*WebDriverAgent" 2>/dev/null || true
  wda_stopped="true"
fi

iproxy_port="${IOS_WDA_DEFAULT_PORT}"
if pgrep -f "iproxy.*${iproxy_port}" >/dev/null 2>&1; then
  pkill -f "iproxy.*${iproxy_port}" 2>/dev/null || true
  iproxy_stopped="true"
fi

sleep 1

# 验证 - 检查 tmux 会话
if tmux list-sessions 2>/dev/null | grep -qE '^wda-'; then
  wda_running="true"
fi
if tmux list-sessions 2>/dev/null | grep -qE '^iproxy-'; then
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