#!/usr/bin/env bash

# ios_wda_ensure_session.sh — 确保 session 有效
# 检查缓存中的 session 是否有效，无效则创建新 session
# 用法：bash ios_wda_ensure_session.sh [--bundle-id <BUNDLE_ID>]

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

# 默认参数
host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
bundle_id=""

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --port) port="$2"; shift 2 ;;
    --bundle-id) bundle_id="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

# 从缓存读取设备 IP
cached_host="$(ios_wda_cache_get '.connection.host')"
if [[ -n "${cached_host}" ]]; then
  host="${cached_host}"
fi

base_url="http://${host}:${port}"

# 1. 检查 WDA 状态
echo "1. 检查 WDA 状态..." >&2
if ! curl --max-time 5 -sf "${base_url}/status" >/dev/null 2>&1; then
  echo "   WDA 不可用，尝试初始化..." >&2
  init_json="$("${SCRIPT_DIR}/ios_wda_init.sh" --host "${host}" --port "${port}" 2>/dev/null)"
  if [[ "$(printf '%s\n' "${init_json}" | jq -r '.ok')" != "true" ]]; then
    echo "   初始化失败" >&2
    printf '%s\n' "${init_json}" | jq '.'
    exit 1
  fi
  host="$(printf '%s\n' "${init_json}" | jq -r '.device.ip // empty' || echo "${host}")"
  if [[ -n "${host}" ]]; then
    base_url="http://${host}:${port}"
  fi
fi

# 2. 使用统一的 session 管理器
echo "2. 确保 session 有效..." >&2

session_manager_args=('--host' "${host}" '--port' "${port}" '--action' 'ensure')
if [[ -n "${bundle_id}" ]]; then
  session_manager_args+=('--bundle-id' "${bundle_id}")
fi

session_manager_result="$("${SCRIPT_DIR}/ios_wda_session_manager.sh" "${session_manager_args[@]}")"
session_manager_ok="$(printf '%s\n' "${session_manager_result}" | jq -r '.ok')"

if [[ "${session_manager_ok}" != "true" ]]; then
  echo "   Session 管理失败" >&2
  printf '%s\n' "${session_manager_result}" | jq '.' >&2
  exit 1
fi

session_id="$(printf '%s\n' "${session_manager_result}" | jq -r '.sessionId')"
echo "   Session 有效: ${session_id}" >&2

# 3. 输出结果
echo "3. 完成" >&2
jq -n \
  --arg sessionId "${session_id}" \
  --arg host "${host}" \
  --arg port "${port}" \
  '{
    ok: true,
    sessionId: $sessionId,
    host: $host,
    port: $port
  }'
