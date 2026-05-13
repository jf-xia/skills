#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
requested_udid=""
ensure_forward="false"
force_refresh="false"
project_path="${IOS_WDA_DEFAULT_PROJECT_PATH}"
scheme="${IOS_WDA_DEFAULT_SCHEME}"
auto_launch_wda="true"

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
    --udid)
      requested_udid="$2"
      shift 2
      ;;
    --ensure-forward)
      ensure_forward="true"
      shift
      ;;
    --force-refresh)
      force_refresh="true"
      shift
      ;;
    --project-path)
      project_path="$2"
      shift 2
      ;;
    --scheme)
      scheme="$2"
      shift 2
      ;;
    --no-auto-launch-wda)
      auto_launch_wda="false"
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ios_wda_require_tools jq curl xcrun lsof ps awk sed grep
ios_wda_init_cache_file

cached_udid=""
if [[ "${force_refresh}" != "true" ]]; then
  cached_udid="$(ios_wda_cache_get '.device.udid')"
fi

selected_line="$(ios_wda_choose_device "${requested_udid:-${cached_udid}}" || true)"
if [[ -z "${selected_line}" ]]; then
  payload="$(jq -n \
    --arg checkedAt "$(ios_wda_now_iso)" \
    --arg cacheFile "${IOS_WDA_CACHE_FILE}" \
    '{
      ok: false,
      checkedAt: $checkedAt,
      cacheFile: $cacheFile,
      reason: "no-online-ios-device",
      nextAction: "connect-device"
    }')"
  ios_wda_emit_json "${payload}"
  exit 2
fi

device_name="$(printf '%s\n' "${selected_line}" | awk -F '\t' '{print $1}')"
device_os="$(printf '%s\n' "${selected_line}" | awk -F '\t' '{print $2}')"
device_udid="$(printf '%s\n' "${selected_line}" | awk -F '\t' '{print $3}')"

listener_pid="$(ios_wda_local_listener_pid "${port}")"
listener_args=""
listener_udid=""
listener_reusable="false"

if [[ -n "${listener_pid}" ]]; then
  listener_args="$(ios_wda_process_args "${listener_pid}")"
  listener_udid="$(ios_wda_extract_udid_from_args "${listener_args}")"
  if [[ -n "${listener_udid}" && "${listener_udid}" == "${device_udid}" ]]; then
    listener_reusable="true"
  fi
fi

wda_status=""
wda_ready="false"
if wda_status="$(ios_wda_status_json "${host}" "${port}" 2>/dev/null)"; then
  wda_ready="$(printf '%s\n' "${wda_status}" | jq -r '.value.ready // false')"
fi

if [[ "${wda_ready}" == "true" && -n "${listener_udid}" && "${listener_udid}" != "${device_udid}" ]]; then
  wda_ready="false"
fi

forward_restarted="false"
iproxy_log="${IOS_WDA_TMP_DIR}/iproxy-${device_udid}-${port}.log"
if [[ "${wda_ready}" != "true" && "${ensure_forward}" == "true" ]]; then
  if [[ -n "${listener_pid}" ]]; then
    kill "${listener_pid}" >/dev/null 2>&1 || true
  fi
  nohup iproxy -u "${device_udid}" "${port}:${port}" >"${iproxy_log}" 2>&1 &
  listener_pid="$!"
  listener_args="$(ios_wda_process_args "${listener_pid}")"
  listener_udid="${device_udid}"
  listener_reusable="true"
  forward_restarted="true"
  if wda_status="$(ios_wda_status_json "${host}" "${port}" 2>/dev/null)"; then
    wda_ready="$(printf '%s\n' "${wda_status}" | jq -r '.value.ready // false')"
  fi
fi

wda_launch_attempted="false"
wda_launch_result='{}'
run_dir=""
if [[ "${wda_ready}" != "true" && "${auto_launch_wda}" == "true" ]]; then
  run_dir="$(ios_wda_make_run_dir)"
  wda_launch_attempted="true"
  if wda_launch_result="$(ios_wda_try_wda_build "${device_udid}" "${project_path}" "${scheme}" "${run_dir}")"; then
    if [[ -n "${listener_pid}" ]]; then
      kill "${listener_pid}" >/dev/null 2>&1 || true
    fi
    nohup iproxy -u "${device_udid}" "${port}:${port}" >"${iproxy_log}" 2>&1 &
    listener_pid="$!"
    listener_args="$(ios_wda_process_args "${listener_pid}")"
    listener_udid="${device_udid}"
    listener_reusable="true"
    forward_restarted="true"
    if wda_status="$(ios_wda_status_json "${host}" "${port}" 2>/dev/null)"; then
      wda_ready="$(printf '%s\n' "${wda_status}" | jq -r '.value.ready // false')"
    fi
  fi
fi

status_reason="ready"
next_action="reuse"
if [[ "${wda_ready}" != "true" ]]; then
  status_reason="wda-not-ready"
  next_action="launch-wda"
fi

if [[ -n "${listener_udid}" && "${listener_udid}" != "${device_udid}" ]]; then
  status_reason="listener-target-mismatch"
  next_action="rebuild-forward"
fi

if [[ "${wda_ready}" != "true" && "${wda_launch_attempted}" == "true" ]]; then
  status_reason="wda-launch-failed"
  next_action="inspect-wda-log"
fi

cache_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg host "${host}" \
  --argjson port "${port}" \
  --arg udid "${device_udid}" \
  --arg name "${device_name}" \
  --arg osVersion "${device_os}" \
  --arg listenerPid "${listener_pid}" \
  --arg listenerArgs "${listener_args}" \
  --arg listenerUdid "${listener_udid}" \
  --argjson listenerReusable "${listener_reusable}" \
  --argjson wdaReady "${wda_ready}" \
  --arg statusJson "${wda_status}" \
  --arg projectPath "${project_path}" \
  --arg scheme "${scheme}" \
  --arg runDir "${run_dir}" \
  --argjson launchAttempted "${wda_launch_attempted}" \
  --argjson launchResult "${wda_launch_result}" \
  '{
    device: {
      udid: $udid,
      name: $name,
      osVersion: $osVersion,
      checkedAt: $checkedAt
    },
    connection: {
      host: $host,
      port: $port,
      checkedAt: $checkedAt,
      listenerPid: (if $listenerPid == "" then null else ($listenerPid | tonumber) end),
      listenerArgs: $listenerArgs,
      listenerTargetUdid: $listenerUdid,
      listenerReusable: $listenerReusable
    },
    wda: (
      {
        checkedAt: $checkedAt,
        ready: $wdaReady,
        projectPath: $projectPath,
        scheme: $scheme,
        launchAttempted: $launchAttempted,
        launchResult: $launchResult,
        lastLaunchRunDir: (if $runDir == "" then null else $runDir end)
      }
      + (if $statusJson == "" then {} else {
        status: ($statusJson | fromjson),
        productBundleIdentifier: (($statusJson | fromjson).value.build.productBundleIdentifier // null),
        iosVersion: (($statusJson | fromjson).value.os.version // null)
      } end)
    )
  }')"
ios_wda_cache_merge_json "${cache_payload}"

result_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg cacheFile "${IOS_WDA_CACHE_FILE}" \
  --arg host "${host}" \
  --argjson port "${port}" \
  --arg reason "${status_reason}" \
  --arg nextAction "${next_action}" \
  --argjson wdaReady "${wda_ready}" \
  --argjson reuseCache "$([[ -n "${cached_udid}" && "${cached_udid}" == "${device_udid}" ]] && printf 'true' || printf 'false')" \
  --argjson forwardRestarted "${forward_restarted}" \
  --arg iproxyLog "${iproxy_log}" \
  --arg deviceName "${device_name}" \
  --arg deviceOs "${device_os}" \
  --arg deviceUdid "${device_udid}" \
  --arg listenerArgs "${listener_args}" \
  --arg listenerUdid "${listener_udid}" \
  --argjson listenerReusable "${listener_reusable}" \
  --argjson listenerPid "${listener_pid:-0}" \
  --arg projectPath "${project_path}" \
  --arg scheme "${scheme}" \
  --arg runDir "${run_dir}" \
  --argjson launchAttempted "${wda_launch_attempted}" \
  --argjson launchResult "${wda_launch_result}" \
  '{
    ok: $wdaReady,
    checkedAt: $checkedAt,
    cacheFile: $cacheFile,
    reuseCache: $reuseCache,
    forwardRestarted: $forwardRestarted,
    reason: $reason,
    nextAction: $nextAction,
    device: {
      name: $deviceName,
      osVersion: $deviceOs,
      udid: $deviceUdid
    },
    connection: {
      host: $host,
      port: $port,
      listenerPid: (if $listenerPid == 0 then null else $listenerPid end),
      listenerArgs: $listenerArgs,
      listenerTargetUdid: $listenerUdid,
      listenerReusable: $listenerReusable,
      iproxyLog: $iproxyLog
    },
    wda: {
      ready: $wdaReady,
      projectPath: $projectPath,
      scheme: $scheme,
      launchAttempted: $launchAttempted,
      launchResult: $launchResult,
      lastLaunchRunDir: (if $runDir == "" then null else $runDir end)
    },
    wdaReady: $wdaReady
  }')"

ios_wda_emit_json "${result_payload}"