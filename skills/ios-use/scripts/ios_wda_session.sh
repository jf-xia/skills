#!/usr/bin/env bash

# iOS WDA 技能 - Session 脚本
# 负责：创建或复用 session，激活应用
# 用法：./ios_wda_session.sh --bundle-id <BUNDLE_ID> [--udid <UDID>] [--force-new]

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

# 默认参数
host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
bundle_id=""
device_name="iPhone"
udid=""
app_path=""
force_new="false"
delete_session="false"
session_id=""

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --port) port="$2"; shift 2 ;;
    --bundle-id) bundle_id="$2"; shift 2 ;;
    --device-name) device_name="$2"; shift 2 ;;
    --udid) udid="$2"; shift 2 ;;
    --app) app_path="$2"; shift 2 ;;
    --force-new) force_new="true"; shift ;;
    --delete) delete_session="true"; shift ;;
    --session-id) session_id="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

ios_wda_require_tools jq curl
ios_wda_init_cache_file

# 1. 运行初始化（检查设备、iproxy、WDA）
echo "1. 运行初始化..." >&2
init_cmd=("${SCRIPT_DIR}/ios_wda_init.sh" --host "${host}" --port "${port}")
if [[ -n "${udid}" ]]; then
  init_cmd+=(--udid "${udid}")
fi

init_json="$("${init_cmd[@]}")"
if [[ "$(printf '%s\n' "${init_json}" | jq -r '.ok')" != "true" ]]; then
  echo "   初始化失败" >&2
  printf '%s\n' "${init_json}" | jq '.'
  exit 2
fi

# 从初始化结果中获取信息
device_udid="$(printf '%s\n' "${init_json}" | jq -r '.device.udid')"
device_name="$(printf '%s\n' "${init_json}" | jq -r '.device.name')"
device_ip="$(printf '%s\n' "${init_json}" | jq -r '.device.ip // empty')"
run_dir="$(printf '%s\n' "${init_json}" | jq -r '.wda.runDir')"

if [[ -n "${device_ip}" && "${device_ip}" != "null" ]]; then
  host="${device_ip}"
fi

echo "   设备: ${device_name} (${device_udid})" >&2
echo "   IP: ${host}:${port}" >&2

# 1.5 校验 Bundle ID 是否已安装
if [[ -n "${bundle_id}" ]]; then
  echo "   校验 Bundle ID: ${bundle_id}" >&2
  if ! ios_wda_validate_bundle_id "${device_udid}" "${bundle_id}"; then
    echo "   ⚠ Bundle ID '${bundle_id}' 未在设备上找到" >&2
    echo "   可用 Bundle ID（部分）:" >&2
    ios_wda_list_bundle_ids "${device_udid}" | head -20 >&2
    exit 4
  fi
  echo "   ✓ Bundle ID 有效" >&2
fi

# 2. 获取或创建 session
echo "2. 获取或创建 session..." >&2

# 使用统一的 session 管理器
session_manager_args=('--host' "${host}" '--port' "${port}")
if [[ -n "${bundle_id}" ]]; then
  session_manager_args+=('--bundle-id' "${bundle_id}")
fi

if [[ "${delete_session}" == "true" ]]; then
  session_manager_args+=('--action' 'delete')
  if [[ -n "${session_id}" ]]; then
    session_manager_args+=('--session-id' "${session_id}")
  fi
elif [[ "${force_new}" == "true" ]]; then
  session_manager_args+=('--action' 'create')
else
  session_manager_args+=('--action' 'ensure')
fi

session_manager_result="$("${SCRIPT_DIR}/ios_wda_session_manager.sh" "${session_manager_args[@]}")"
session_manager_ok="$(printf '%s\n' "${session_manager_result}" | jq -r '.ok')"

if [[ "${session_manager_ok}" != "true" ]]; then
  echo "   Session 管理失败" >&2
  printf '%s\n' "${session_manager_result}" | jq '.'
  exit 3
fi

session_id="$(printf '%s\n' "${session_manager_result}" | jq -r '.sessionId')"
action="$(printf '%s\n' "${session_manager_result}" | jq -r '.action')"

# 如果是删除操作，输出结果并退出
if [[ "${delete_session}" == "true" ]]; then
  echo "   Session 已删除" >&2
  ios_wda_emit_json "${session_manager_result}"
  exit 0
fi

# 3. 激活应用
echo "3. 激活应用..." >&2
base_url="http://${host}:${port}"
active_app_json='{}'
if [[ -n "${bundle_id}" ]]; then
  # 尝试激活应用
  curl --max-time 15 -sf -X POST "${base_url}/session/${session_id}/wda/apps/activate" \
    -H 'Content-Type: application/json' \
    -d "$(jq -nc --arg bundleId "${bundle_id}" '{bundleId: $bundleId}')" >/dev/null 2>&1 || true
  
  # 获取当前活跃应用
  active_app_json="$(curl --max-time 15 -sf "${base_url}/wda/activeAppInfo" || printf '{}')"
  active_bundle_id="$(printf '%s\n' "${active_app_json}" | jq -r '.value.bundleId // empty')"
  
  if [[ "${active_bundle_id}" != "${bundle_id}" ]]; then
    # 如果激活失败，尝试启动应用
    echo "   启动应用: ${bundle_id}" >&2
    curl --max-time 15 -sf -X POST "${base_url}/wda/apps/launch" \
      -H 'Content-Type: application/json' \
      -d "$(jq -nc --arg bundleId "${bundle_id}" '{bundleId: $bundleId}')" >/dev/null 2>&1 || true
    active_app_json="$(curl --max-time 15 -sf "${base_url}/wda/activeAppInfo" || printf '{}')"
  fi
  
  active_bundle_id="$(printf '%s\n' "${active_app_json}" | jq -r '.value.bundleId // empty')"
  if [[ -n "${active_bundle_id}" && "${active_bundle_id}" != "null" ]]; then
    echo "   活跃应用: ${active_bundle_id}" >&2
  fi
fi

# 4. 更新缓存（session 管理器已更新）
# 只更新活跃应用信息
cache_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg bundleId "${bundle_id}" \
  --arg deviceName "${device_name}" \
  --arg udid "${device_udid}" \
  --arg action "${action}" \
  --argjson activeApp "${active_app_json}" \
  '{
    session: {
      bundleId: (if $bundleId == "" then null else $bundleId end),
      deviceName: $deviceName,
      udid: $udid,
      action: $action,
      checkedAt: $checkedAt,
      activeApp: $activeApp
    }
  }')"
ios_wda_cache_merge_json "${cache_payload}"

# 5. 输出结果
echo "4. 完成" >&2
result_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg action "${action}" \
  --arg sessionId "${session_id}" \
  --arg bundleId "${bundle_id}" \
  --arg deviceName "${device_name}" \
  --arg udid "${device_udid}" \
  --arg cacheFile "${IOS_WDA_CACHE_FILE}" \
  --arg runDir "${run_dir}" \
  --argjson activeApp "${active_app_json}" \
  --argjson init "${init_json}" \
  '{
    ok: true,
    checkedAt: $checkedAt,
    action: $action,
    sessionId: $sessionId,
    cacheFile: $cacheFile,
    device: {
      name: $deviceName,
      udid: $udid
    },
    runDir: $runDir,
    bundleId: (if $bundleId == "" then null else $bundleId end),
    activeApp: $activeApp,
    init: $init
  }')"

result_path="$(ios_wda_write_json_artifact "session-result" "${result_payload}" "${run_dir}")"
result_payload="$(printf '%s\n' "${result_payload}" | jq --arg resultPath "${result_path}" '. + {resultPath: $resultPath}')"

ios_wda_emit_json "${result_payload}"
