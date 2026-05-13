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

# 2. 获取或创建 session
echo "2. 获取或创建 session..." >&2
base_url="http://${host}:${port}"
cached_session_id=""
if [[ -z "${session_id}" ]]; then
  cached_session_id="$(ios_wda_cache_get '.session.id')"
  session_id="${cached_session_id}"
fi

# 验证 session 是否有效
validate_session() {
  local current_session_id="$1"
  curl --max-time 5 -sf "${base_url}/session/${current_session_id}/source" >/dev/null 2>&1
}

# 删除现有 session
delete_existing_session() {
  local current_session_id="$1"
  curl -sf -X DELETE "${base_url}/session/${current_session_id}" >/dev/null 2>&1 || \
    curl -sf -X DELETE "${base_url}/session" >/dev/null 2>&1 || true
}

# 如果是删除操作
if [[ "${delete_session}" == "true" ]]; then
  if [[ -z "${session_id}" ]]; then
    echo "   没有缓存的 session" >&2
    payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: true, checkedAt: $checkedAt, action: "noop-delete", reason: "no-cached-session"}')"
    ios_wda_emit_json "${payload}"
    exit 0
  fi
  delete_existing_session "${session_id}"
  ios_wda_cache_clear_session
  echo "   Session 已删除: ${session_id}" >&2
  payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" --arg sessionId "${session_id}" '{ok: true, checkedAt: $checkedAt, action: "deleted", sessionId: $sessionId}')"
  ios_wda_emit_json "${payload}"
  exit 0
fi

# 创建或复用 session
action="created"
if [[ "${force_new}" != "true" && -n "${session_id}" ]] && validate_session "${session_id}"; then
  action="reused"
  echo "   复用现有 session: ${session_id}" >&2
else
  if [[ -n "${session_id}" && "${force_new}" == "true" ]]; then
    delete_existing_session "${session_id}"
  fi
  
  echo "   创建新 session..." >&2
  capabilities_json="$(jq -nc \
    --arg platformName "iOS" \
    --arg deviceName "${device_name}" \
    --arg udid "${device_udid}" \
    --arg bundleId "${bundle_id}" \
    --arg appPath "${app_path}" \
    '{
      capabilities: {
        alwaysMatch: (
          {platformName: $platformName, deviceName: $deviceName, udid: $udid}
          + (if $bundleId == "" then {} else {bundleId: $bundleId} end)
          + (if $appPath == "" then {} else {app: $appPath} end)
        )
      }
    }')"
  
  create_response="$(curl -sf -X POST "${base_url}/session" -H 'Content-Type: application/json' -d "${capabilities_json}")"
  session_id="$(printf '%s\n' "${create_response}" | jq -r '.sessionId // .value.sessionId // empty')"
  
  if [[ -z "${session_id}" ]]; then
    echo "   Session 创建失败" >&2
    payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" --argjson response "${create_response}" '{ok: false, checkedAt: $checkedAt, reason: "session-create-failed", response: $response}')"
    ios_wda_emit_json "${payload}"
    exit 3
  fi
  echo "   Session 创建成功: ${session_id}" >&2
fi

# 3. 激活应用
echo "3. 激活应用..." >&2
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

# 4. 更新缓存
cache_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg sessionId "${session_id}" \
  --arg bundleId "${bundle_id}" \
  --arg deviceName "${device_name}" \
  --arg udid "${device_udid}" \
  --arg action "${action}" \
  --argjson activeApp "${active_app_json}" \
  '{
    session: {
      id: $sessionId,
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
