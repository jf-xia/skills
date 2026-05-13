#!/usr/bin/env bash

# iOS WDA 技能 - 初始化脚本
# 负责：检查设备、启动 iproxy、启动 WDA、等待 ready
# 用法：./ios_wda_init.sh [--udid <UDID>] [--host <HOST>] [--port <PORT>]

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

# 默认参数
host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
requested_udid=""
project_path="${IOS_WDA_DEFAULT_PROJECT_PATH}"
scheme="${IOS_WDA_DEFAULT_SCHEME}"
max_wait=60

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --port) port="$2"; shift 2 ;;
    --udid) requested_udid="$2"; shift 2 ;;
    --project-path) project_path="$2"; shift 2 ;;
    --scheme) scheme="$2"; shift 2 ;;
    --max-wait) max_wait="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# 检查工具
ios_wda_require_tools jq curl xcrun lsof ps
ios_wda_init_cache_file

# 创建本次运行目录
run_dir="$(ios_wda_use_run_dir "")"
mkdir -p "${run_dir}"

# 1. 选择设备
echo "1. 检查设备..." >&2
selected_line="$(ios_wda_choose_device "${requested_udid}" || true)"
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

echo "   设备: ${device_name} (${device_os}) - ${device_udid}" >&2

# 2. 检查并启动 iproxy
echo "2. 检查 iproxy..." >&2
listener_pid="$(ios_wda_local_listener_pid "${port}")"
listener_args=""
listener_udid=""
listener_reusable="false"
forward_restarted="false"
iproxy_log="${IOS_WDA_TMP_DIR}/iproxy-${device_udid}-${port}.log"

if [[ -n "${listener_pid}" ]]; then
  listener_args="$(ios_wda_process_args "${listener_pid}")"
  listener_udid="$(ios_wda_extract_udid_from_args "${listener_args}")"
  if [[ -n "${listener_udid}" && "${listener_udid}" == "${device_udid}" ]]; then
    listener_reusable="true"
    echo "   iproxy 已运行 (PID: ${listener_pid})" >&2
  else
    echo "   iproxy 指向错误设备，重启中..." >&2
    kill "${listener_pid}" >/dev/null 2>&1 || true
    sleep 1
    nohup iproxy -u "${device_udid}" "${port}:${port}" >"${iproxy_log}" 2>&1 &
    listener_pid="$!"
    listener_args="$(ios_wda_process_args "${listener_pid}")"
    listener_udid="${device_udid}"
    listener_reusable="true"
    forward_restarted="true"
    echo "   iproxy 已重启 (PID: ${listener_pid})" >&2
  fi
else
  echo "   启动 iproxy..." >&2
  nohup iproxy -u "${device_udid}" "${port}:${port}" >"${iproxy_log}" 2>&1 &
  listener_pid="$!"
  listener_args="$(ios_wda_process_args "${listener_pid}")"
  listener_udid="${device_udid}"
  listener_reusable="true"
  forward_restarted="true"
  echo "   iproxy 已启动 (PID: ${listener_pid})" >&2
fi

# 3. 检查 WDA 状态
echo "3. 检查 WDA 状态..." >&2
wda_status=""
wda_ready="false"
device_ip=""

# 先尝试本地连接
if wda_status="$(curl --max-time 5 -sf "http://${host}:${port}/status" 2>/dev/null)"; then
  wda_ready="$(printf '%s\n' "${wda_status}" | jq -r '.value.ready // false')"
  device_ip="$(printf '%s\n' "${wda_status}" | jq -r '.value.ios.ip // empty')"
  echo "   WDA 已就绪 (本地连接)" >&2
else
  # 尝试从缓存获取设备 IP
  cached_device_ip="$(ios_wda_cache_get '.connection.deviceIp')"
  if [[ -n "${cached_device_ip}" ]]; then
    if wda_status="$(curl --max-time 5 -sf "http://${cached_device_ip}:${port}/status" 2>/dev/null)"; then
      wda_ready="$(printf '%s\n' "${wda_status}" | jq -r '.value.ready // false')"
      device_ip="${cached_device_ip}"
      host="${cached_device_ip}"
      echo "   WDA 已就绪 (设备 IP: ${device_ip})" >&2
    fi
  fi
fi

# 4. 如果 WDA 未就绪，启动它
if [[ "${wda_ready}" != "true" ]]; then
  echo "4. 启动 WDA (后台)..." >&2
  
  # 清理旧的 xcodebuild 进程
  pkill -f "xcodebuild.*WebDriverAgent" 2>/dev/null || true
  sleep 1
  
  # 启动 WDA
  wda_log="${run_dir}/wda-background.log"
  cd /Users/jianfengxia/work/WebDriverAgent
  nohup xcodebuild -project "${project_path}" -scheme "${scheme}" -destination "id=${device_udid}" test-without-building >"${wda_log}" 2>&1 &
  wda_pid="$!"
  
  echo "   等待 WDA ready (最多 ${max_wait} 秒)..." >&2
  waited=0
  while [[ ${waited} -lt ${max_wait} ]]; do
    # 尝试本地连接
    if wda_status="$(curl --max-time 2 -sf "http://${host}:${port}/status" 2>/dev/null)"; then
      if [[ "$(printf '%s\n' "${wda_status}" | jq -r '.value.ready // false')" == "true" ]]; then
        wda_ready="true"
        device_ip="$(printf '%s\n' "${wda_status}" | jq -r '.value.ios.ip // empty')"
        break
      fi
    fi
    
    # 尝试从日志提取设备 IP
    if [[ -z "${device_ip}" ]]; then
      device_ip="$(grep -o 'http://[0-9]*\.[0-9]*\.[0-9]*\.[0-9]*:8100' "${wda_log}" 2>/dev/null | head -1 | sed 's|http://||;s|:8100||')" || true
    fi
    
    # 尝试设备 IP 连接
    if [[ -n "${device_ip}" ]]; then
      if wda_status="$(curl --max-time 2 -sf "http://${device_ip}:${port}/status" 2>/dev/null)"; then
        if [[ "$(printf '%s\n' "${wda_status}" | jq -r '.value.ready // false')" == "true" ]]; then
          wda_ready="true"
          host="${device_ip}"
          break
        fi
      fi
    fi
    
    sleep 1
    waited=$((waited + 1))
    echo "   等待 ${waited}s..." >&2
  done
  
  if [[ "${wda_ready}" != "true" ]]; then
    echo "   WDA 启动失败，请检查日志: ${wda_log}" >&2
    payload="$(jq -n \
      --arg checkedAt "$(ios_wda_now_iso)" \
      --arg reason "wda-launch-failed" \
      --arg logFile "${wda_log}" \
      '{
        ok: false,
        checkedAt: $checkedAt,
        reason: $reason,
        logFile: $logFile
      }')"
    ios_wda_emit_json "${payload}"
    exit 3
  fi
fi

# 5. 更新缓存
echo "5. 更新缓存..." >&2
cache_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg host "${host}" \
  --argjson port "${port}" \
  --arg udid "${device_udid}" \
  --arg name "${device_name}" \
  --arg osVersion "${device_os}" \
  --argjson listenerPid "${listener_pid}" \
  --arg listenerArgs "${listener_args}" \
  --arg listenerUdid "${listener_udid}" \
  --argjson listenerReusable "${listener_reusable}" \
  --argjson forwardRestarted "${forward_restarted}" \
  --arg deviceIp "${device_ip}" \
  --arg runDir "${run_dir}" \
  --arg statusJson "${wda_status}" \
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
      listenerPid: $listenerPid,
      listenerArgs: $listenerArgs,
      listenerTargetUdid: $listenerUdid,
      listenerReusable: $listenerReusable,
      deviceIp: (if $deviceIp == "" then null else $deviceIp end)
    },
    wda: {
      checkedAt: $checkedAt,
      ready: true,
      projectPath: "'${project_path}'",
      scheme: "'${scheme}'",
      forwardRestarted: $forwardRestarted,
      lastRunDir: $runDir
    }
  }')"
ios_wda_cache_merge_json "${cache_payload}"

# 6. 输出结果
echo "6. 初始化完成" >&2
result_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg cacheFile "${IOS_WDA_CACHE_FILE}" \
  --arg host "${host}" \
  --argjson port "${port}" \
  --arg udid "${device_udid}" \
  --arg name "${device_name}" \
  --arg osVersion "${device_os}" \
  --arg deviceIp "${device_ip}" \
  --argjson listenerPid "${listener_pid}" \
  --argjson forwardRestarted "${forward_restarted}" \
  --arg runDir "${run_dir}" \
  --arg statusJson "${wda_status}" \
  '{
    ok: true,
    checkedAt: $checkedAt,
    cacheFile: $cacheFile,
    device: {
      name: $name,
      osVersion: $osVersion,
      udid: $udid,
      ip: $deviceIp
    },
    connection: {
      host: $host,
      port: $port,
      listenerPid: $listenerPid,
      forwardRestarted: $forwardRestarted
    },
    wda: {
      ready: true,
      runDir: $runDir
    },
    nextAction: "create-session"
  }')"

result_path="$(ios_wda_write_json_artifact "init-result" "${result_payload}" "${run_dir}")"
result_payload="$(printf '%s\n' "${result_payload}" | jq --arg resultPath "${result_path}" '. + {resultPath: $resultPath}')"

ios_wda_emit_json "${result_payload}"
