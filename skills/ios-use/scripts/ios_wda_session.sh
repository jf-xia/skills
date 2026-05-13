#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
bundle_id=""
device_name="iPhone"
udid=""
app_path=""
force_new="false"
delete_session="false"
session_id=""
run_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      host="$2"
      shift 2
      ;;
    --port)
      port="$2"
      shift 2
      ;;
    --bundle-id)
      bundle_id="$2"
      shift 2
      ;;
    --device-name)
      device_name="$2"
      shift 2
      ;;
    --udid)
      udid="$2"
      shift 2
      ;;
    --app)
      app_path="$2"
      shift 2
      ;;
    --force-new)
      force_new="true"
      shift
      ;;
    --delete)
      delete_session="true"
      shift
      ;;
    --session-id)
      session_id="$2"
      shift 2
      ;;
    --run-dir)
      run_dir="$2"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ios_wda_require_tools jq curl
ios_wda_init_cache_file
run_dir="$(ios_wda_use_run_dir "${run_dir}")"

if [[ -z "${udid}" ]]; then
  udid="$(ios_wda_cache_get '.device.udid')"
fi

preflight_cmd=("${SCRIPT_DIR}/ios_wda_preflight.sh" --host "${host}" --port "${port}" --ensure-forward)
if [[ -n "${udid}" ]]; then
  preflight_cmd+=(--udid "${udid}")
fi
preflight_cmd+=(--run-dir "${run_dir}")

preflight_json="$("${preflight_cmd[@]}")"
if [[ "$(printf '%s\n' "${preflight_json}" | jq -r '.wdaReady')" != "true" ]]; then
  payload="$(jq -n \
    --arg checkedAt "$(ios_wda_now_iso)" \
    --arg host "${host}" \
    --argjson port "${port}" \
    --arg reason "$(printf '%s\n' "${preflight_json}" | jq -r '.reason // "wda-not-ready"')" \
    --arg nextAction "$(printf '%s\n' "${preflight_json}" | jq -r '.nextAction // "launch-wda"')" \
    --argjson preflight "${preflight_json}" \
    '{
      ok: false,
      checkedAt: $checkedAt,
      host: $host,
      port: $port,
      reason: $reason,
      nextAction: $nextAction,
      preflight: $preflight
    }')"
  ios_wda_emit_json "${payload}"
  exit 2
fi

if [[ -z "${udid}" ]]; then
  udid="$(printf '%s\n' "${preflight_json}" | jq -r '.device.udid')"
fi

if [[ "${device_name}" == "iPhone" ]]; then
  device_name="$(printf '%s\n' "${preflight_json}" | jq -r '.device.name // "iPhone"')"
fi

base_url="http://${host}:${port}"
cached_session_id=""
if [[ -z "${session_id}" ]]; then
  cached_session_id="$(ios_wda_cache_get '.session.id')"
  session_id="${cached_session_id}"
fi

validate_session() {
  local current_session_id="$1"
  ios_wda_session_source "${current_session_id}" "${host}" "${port}" >/dev/null 2>&1
}

delete_existing_session() {
  local current_session_id="$1"
  curl -sf -X DELETE "${base_url}/session/${current_session_id}" >/dev/null 2>&1 || \
    curl -sf -X DELETE "${base_url}/session" >/dev/null 2>&1 || true
}

if [[ "${delete_session}" == "true" ]]; then
  if [[ -z "${session_id}" ]]; then
    payload="$(jq -n \
      --arg checkedAt "$(ios_wda_now_iso)" \
      '{
        ok: true,
        checkedAt: $checkedAt,
        action: "noop-delete",
        reason: "no-cached-session"
      }')"
    result_path="$(ios_wda_write_json_artifact "session-delete-result" "${payload}" "${run_dir}")"
    payload="$(printf '%s\n' "${payload}" | jq --arg resultPath "${result_path}" '. + {resultPath: $resultPath}')"
    ios_wda_emit_json "${payload}"
    exit 0
  fi

  delete_existing_session "${session_id}"
  ios_wda_cache_clear_session

  payload="$(jq -n \
    --arg checkedAt "$(ios_wda_now_iso)" \
    --arg sessionId "${session_id}" \
    '{
      ok: true,
      checkedAt: $checkedAt,
      action: "deleted",
      sessionId: $sessionId
    }')"
  result_path="$(ios_wda_write_json_artifact "session-delete-result" "${payload}" "${run_dir}")"
  payload="$(printf '%s\n' "${payload}" | jq --arg resultPath "${result_path}" '. + {resultPath: $resultPath}')"
  ios_wda_emit_json "${payload}"
  exit 0
fi

action="created"
create_response_path=""
if [[ "${force_new}" != "true" && -n "${session_id}" ]] && validate_session "${session_id}"; then
  action="reused"
else
  if [[ -n "${session_id}" && "${force_new}" == "true" ]]; then
    delete_existing_session "${session_id}"
  fi

  capabilities_json="$(jq -nc \
    --arg platformName "iOS" \
    --arg deviceName "${device_name}" \
    --arg udid "${udid}" \
    --arg bundleId "${bundle_id}" \
    --arg appPath "${app_path}" \
    '{
      capabilities: {
        alwaysMatch: (
          {
            platformName: $platformName,
            deviceName: $deviceName,
            udid: $udid
          }
          + (if $bundleId == "" then {} else {bundleId: $bundleId} end)
          + (if $appPath == "" then {} else {app: $appPath} end)
        )
      }
    }')"

  create_response="$(curl -sf -X POST "${base_url}/session" -H 'Content-Type: application/json' -d "${capabilities_json}")"
  create_response_path="$(ios_wda_write_json_artifact "session-create-response" "${create_response}" "${run_dir}")"
  session_id="$(printf '%s\n' "${create_response}" | jq -r '.sessionId // .value.sessionId // empty')"
  if [[ -z "${session_id}" ]]; then
    payload="$(jq -n \
      --arg checkedAt "$(ios_wda_now_iso)" \
      --argjson response "${create_response}" \
      '{
        ok: false,
        checkedAt: $checkedAt,
        reason: "session-create-failed",
        response: $response
      }')"
    result_path="$(ios_wda_write_json_artifact "session-result" "${payload}" "${run_dir}")"
    payload="$(printf '%s\n' "${payload}" | jq --arg resultPath "${result_path}" --arg createResponsePath "${create_response_path}" '. + {resultPath: $resultPath, createResponsePath: $createResponsePath}')"
    ios_wda_emit_json "${payload}"
    exit 3
  fi
fi

active_app_json='{}'
activate_result='{}'
activate_result_path=""
active_app_path=""
launch_result='{}'
launch_result_path=""
if [[ -n "${bundle_id}" ]]; then
  activate_result="$(curl --max-time 15 -sf -X POST "${base_url}/session/${session_id}/wda/apps/activate" -H 'Content-Type: application/json' -d "$(jq -nc --arg bundleId "${bundle_id}" '{bundleId: $bundleId}')" || printf '{}')"
  activate_result_path="$(ios_wda_write_json_artifact "session-activate-response" "${activate_result}" "${run_dir}")"
  active_app_json="$(curl --max-time 15 -sf "${base_url}/wda/activeAppInfo" || printf '{}')"
  active_app_path="$(ios_wda_write_json_artifact "session-active-app-info" "${active_app_json}" "${run_dir}")"
  if [[ "$(printf '%s\n' "${active_app_json}" | jq -r '.value.bundleId // empty')" != "${bundle_id}" ]]; then
    launch_result="$(curl --max-time 15 -sf -X POST "${base_url}/wda/apps/launch" -H 'Content-Type: application/json' -d "$(jq -nc --arg bundleId "${bundle_id}" '{bundleId: $bundleId}')" || printf '{}')"
    launch_result_path="$(ios_wda_write_json_artifact "session-launch-response" "${launch_result}" "${run_dir}")"
    active_app_json="$(curl --max-time 15 -sf "${base_url}/wda/activeAppInfo" || printf '{}')"
    active_app_path="$(ios_wda_write_json_artifact "session-active-app-info" "${active_app_json}" "${run_dir}")"
  fi
fi

cache_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg sessionId "${session_id}" \
  --arg bundleId "${bundle_id}" \
  --arg deviceName "${device_name}" \
  --arg udid "${udid}" \
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

result_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg action "${action}" \
  --arg sessionId "${session_id}" \
  --arg bundleId "${bundle_id}" \
  --arg deviceName "${device_name}" \
  --arg udid "${udid}" \
  --arg cacheFile "${IOS_WDA_CACHE_FILE}" \
  --arg runDir "${run_dir}" \
  --arg createResponsePath "${create_response_path}" \
  --arg activateResultPath "${activate_result_path}" \
  --arg activeAppPath "${active_app_path}" \
  --arg launchResultPath "${launch_result_path}" \
  --argjson activeApp "${active_app_json}" \
  --argjson activateResult "${activate_result}" \
  --argjson launchResult "${launch_result}" \
  --argjson preflight "${preflight_json}" \
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
    createResponsePath: (if $createResponsePath == "" then null else $createResponsePath end),
    activateResultPath: (if $activateResultPath == "" then null else $activateResultPath end),
    activeAppPath: (if $activeAppPath == "" then null else $activeAppPath end),
    launchResultPath: (if $launchResultPath == "" then null else $launchResultPath end),
    preflight: $preflight,
    activateResult: $activateResult,
    launchResult: $launchResult,
    activeApp: $activeApp
  }')"

result_path="$(ios_wda_write_json_artifact "session-result" "${result_payload}" "${run_dir}")"
result_payload="$(printf '%s\n' "${result_payload}" | jq --arg resultPath "${result_path}" '. + {resultPath: $resultPath}')"

ios_wda_emit_json "${result_payload}"