#!/usr/bin/env bash

set -euo pipefail

IOS_WDA_COMMON_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IOS_WDA_REPO_ROOT="$(CDPATH= cd -- "${IOS_WDA_COMMON_DIR}/../../../.." && pwd)"
IOS_WDA_TMP_DIR="${IOS_WDA_REPO_ROOT}/tmp"
IOS_WDA_CACHE_FILE="${IOS_WDA_TMP_DIR}/ios-use-cache.json"
IOS_WDA_DEFAULT_HOST="${IOS_WDA_DEFAULT_HOST:-127.0.0.1}"
IOS_WDA_DEFAULT_PORT="${IOS_WDA_DEFAULT_PORT:-8100}"
IOS_WDA_DEFAULT_PROJECT_PATH="${IOS_WDA_DEFAULT_PROJECT_PATH:-$HOME/work/WebDriverAgent/WebDriverAgent.xcodeproj}"
IOS_WDA_DEFAULT_SCHEME="${IOS_WDA_DEFAULT_SCHEME:-WebDriverAgentRunner}"

ios_wda_now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

ios_wda_ensure_tmp_dir() {
  mkdir -p "${IOS_WDA_TMP_DIR}"
}

ios_wda_init_cache_file() {
  ios_wda_ensure_tmp_dir
  if [[ ! -f "${IOS_WDA_CACHE_FILE}" ]]; then
    cat >"${IOS_WDA_CACHE_FILE}" <<'EOF'
{
  "schemaVersion": 1,
  "device": {},
  "connection": {},
  "wda": {},
  "session": {},
  "artifacts": {}
}
EOF
  fi
}

ios_wda_require_tools() {
  local tool
  for tool in "$@"; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
      echo "missing required tool: ${tool}" >&2
      return 1
    fi
  done
}

ios_wda_cache_get() {
  local query="$1"
  ios_wda_init_cache_file
  jq -r "${query} // empty" "${IOS_WDA_CACHE_FILE}"
}

ios_wda_cache_merge_json() {
  local payload="$1"
  local tmp_file
  local lock_file="${IOS_WDA_CACHE_FILE}.lock"

  ios_wda_init_cache_file
  
  # 使用 mkdir 作为简单锁（兼容 macOS，无 flock）
  local lock_dir="${lock_file}.d"
  local wait_count=0
  while ! mkdir "${lock_dir}" 2>/dev/null; do
    sleep 0.1
    wait_count=$((wait_count + 1))
    if [[ ${wait_count} -ge 50 ]]; then
      echo "警告: 获取缓存锁超时" >&2
      return 1
    fi
  done
  trap 'rmdir "${lock_dir}" 2>/dev/null' RETURN
  
  tmp_file="$(mktemp "${IOS_WDA_TMP_DIR}/ios-use-cache.XXXXXX")"
  jq -s '.[0] * .[1]' "${IOS_WDA_CACHE_FILE}" <(printf '%s\n' "${payload}") >"${tmp_file}"
  mv "${tmp_file}" "${IOS_WDA_CACHE_FILE}"
  
  rmdir "${lock_dir}" 2>/dev/null
}

ios_wda_cache_clear_session() {
  local tmp_file
  local lock_file="${IOS_WDA_CACHE_FILE}.lock"

  ios_wda_init_cache_file
  
  # 使用 mkdir 作为简单锁（兼容 macOS，无 flock）
  local lock_dir="${lock_file}.d"
  local wait_count=0
  while ! mkdir "${lock_dir}" 2>/dev/null; do
    sleep 0.1
    wait_count=$((wait_count + 1))
    if [[ ${wait_count} -ge 50 ]]; then
      echo "警告: 获取缓存锁超时" >&2
      return 1
    fi
  done
  trap 'rmdir "${lock_dir}" 2>/dev/null' RETURN
  
  tmp_file="$(mktemp "${IOS_WDA_TMP_DIR}/ios-use-cache.XXXXXX")"
  jq '.session = {}' "${IOS_WDA_CACHE_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${IOS_WDA_CACHE_FILE}"
  
  rmdir "${lock_dir}" 2>/dev/null
}

ios_wda_local_listener_pid() {
  local port="${1:-${IOS_WDA_DEFAULT_PORT}}"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
}

ios_wda_tmux_session_exists() {
  local session_name="$1"
  tmux has-session -t "${session_name}" 2>/dev/null
}

ios_wda_tmux_kill_session() {
  local session_name="$1"
  if ios_wda_tmux_session_exists "${session_name}"; then
    tmux kill-session -t "${session_name}" 2>/dev/null || true
  fi
}

ios_wda_tmux_list_sessions() {
  tmux list-sessions -F "#{session_name}" 2>/dev/null || true
}

ios_wda_process_args() {
  local pid="$1"
  ps -p "${pid}" -o args= 2>/dev/null | sed 's/^[[:space:]]*//' || true
}

ios_wda_extract_udid_from_args() {
  local args="$1"
  local udid

  udid="$(printf '%s\n' "${args}" | sed -n 's/.*-u[[:space:]]\([A-Za-z0-9-]*\).*/\1/p' | head -n 1)"
  if [[ -n "${udid}" ]]; then
    printf '%s\n' "${udid}"
    return 0
  fi

  printf '%s\n' "${args}" | grep -Eo '[A-Za-z0-9-]{20,}' | tail -n 1 || true
}

ios_wda_list_online_devices() {
  xcrun xctrace list devices | awk '
    BEGIN { in_devices = 0 }
    /^== Devices ==$/ { in_devices = 1; next }
    /^== / {
      if (in_devices == 1) {
        exit
      }
    }
    in_devices == 1 {
      line = $0
      sub(/[[:space:]]+$/, "", line)
      if (line ~ /(Simulator|MacBook|Mac mini|Mac Studio|Mac Pro|iMac)/) next
      if (line !~ /(iPhone|iPad|iPod)/) next
      udid = line
      sub(/^.*\(/, "", udid)
      sub(/\)$/, "", udid)
      rest = line
      sub(/[[:space:]]*\([^()]+\)$/, "", rest)
      os = rest
      sub(/^.*\(/, "", os)
      sub(/\)$/, "", os)
      name = rest
      sub(/[[:space:]]*\([^()]+\)$/, "", name)
      if (name != "" && os != "" && udid != "") {
        printf "%s\t%s\t%s\n", name, os, udid
      }
    }
  '
}

ios_wda_choose_device() {
  local preferred_udid="${1:-}"
  local devices
  local chosen

  devices="$(ios_wda_list_online_devices)"
  if [[ -z "${devices}" ]]; then
    return 1
  fi

  if [[ -n "${preferred_udid}" ]]; then
    chosen="$(printf '%s\n' "${devices}" | awk -F '\t' -v preferred="${preferred_udid}" '$3 == preferred { print; exit }')"
    if [[ -n "${chosen}" ]]; then
      printf '%s\n' "${chosen}"
      return 0
    fi
  fi

  printf '%s\n' "${devices}" | head -n 1
}

# 从 WDA 状态响应中提取设备 IP
ios_wda_extract_device_ip() {
  local status_json="$1"
  printf '%s\n' "${status_json}" | jq -r '.value.ios.ip // empty' 2>/dev/null || true
}

# 尝试连接到设备 IP（用于 WiFi 连接场景）
ios_wda_try_device_ip() {
  local device_ip="$1"
  local port="${2:-${IOS_WDA_DEFAULT_PORT}}"
  curl --max-time 5 -sf "http://${device_ip}:${port}/status" 2>/dev/null || true
}

ios_wda_status_json() {
  local host="${1:-${IOS_WDA_DEFAULT_HOST}}"
  local port="${2:-${IOS_WDA_DEFAULT_PORT}}"
  local result=""
  
  # 先尝试本地连接（通过 iproxy）
  if result="$(curl --max-time 5 -sf "http://${host}:${port}/status" 2>/dev/null)"; then
    printf '%s\n' "${result}"
    return 0
  fi
  
  # 如果本地连接失败，尝试从缓存中获取设备 IP
  local cached_device_ip
  cached_device_ip="$(ios_wda_cache_get '.connection.deviceIp')"
  if [[ -n "${cached_device_ip}" ]]; then
    if result="$(curl --max-time 5 -sf "http://${cached_device_ip}:${port}/status" 2>/dev/null)"; then
      printf '%s\n' "${result}"
      return 0
    fi
  fi
  
  return 1
}

ios_wda_session_source() {
  local session_id="$1"
  local host="${2:-${IOS_WDA_DEFAULT_HOST}}"
  local port="${3:-${IOS_WDA_DEFAULT_PORT}}"
  
  # 首先尝试设备 IP
  local device_ip
  device_ip="$(ios_wda_cache_get '.connection.deviceIp')"
  if [[ -n "${device_ip}" ]]; then
    if curl --max-time 15 -sf "http://${device_ip}:${port}/session/${session_id}/source" >/dev/null 2>&1; then
      return 0
    fi
  fi
  
  # 尝试指定的 host
  curl --max-time 15 -sf "http://${host}:${port}/session/${session_id}/source"
}

ios_wda_make_run_dir() {
  local run_dir="${IOS_WDA_TMP_DIR}/$(date +%y%m%d%H%M%S)"
  mkdir -p "${run_dir}"
  printf '%s\n' "${run_dir}"
}

ios_wda_slugify_label() {
  local label="$1"
  printf '%s\n' "${label}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//'
}

ios_wda_use_run_dir() {
  local requested_run_dir="${1:-}"
  local reset_sequence="false"
  local current_run_dir
  local run_dir
  local tmp_file

  ios_wda_init_cache_file
  current_run_dir="$(ios_wda_cache_get '.artifacts.lastRunDir')"

  if [[ -n "${requested_run_dir}" ]]; then
    run_dir="${requested_run_dir}"
    if [[ "${run_dir}" != "${current_run_dir}" ]]; then
      reset_sequence="true"
    fi
  elif [[ -n "${current_run_dir}" ]]; then
    run_dir="${current_run_dir}"
  else
    run_dir="$(ios_wda_make_run_dir)"
    reset_sequence="true"
  fi

  mkdir -p "${run_dir}"
  tmp_file="$(mktemp "${IOS_WDA_TMP_DIR}/ios-use-cache.XXXXXX")"
  jq \
    --arg runDir "${run_dir}" \
    --argjson resetSequence "${reset_sequence}" \
    '.artifacts.lastRunDir = $runDir
    | .artifacts.sequence = (if $resetSequence then 0 else (.artifacts.sequence // 0) end)' \
    "${IOS_WDA_CACHE_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${IOS_WDA_CACHE_FILE}"

  printf '%s\n' "${run_dir}"
}

ios_wda_reserve_artifact_path() {
  local label="$1"
  local extension="$2"
  local requested_run_dir="${3:-}"
  local run_dir
  local slug
  local tmp_file
  local sequence

  run_dir="$(ios_wda_use_run_dir "${requested_run_dir}")"
  slug="$(ios_wda_slugify_label "${label}")"
  tmp_file="$(mktemp "${IOS_WDA_TMP_DIR}/ios-use-cache.XXXXXX")"
  jq '.artifacts.sequence = ((.artifacts.sequence // 0) + 1)' "${IOS_WDA_CACHE_FILE}" >"${tmp_file}"
  sequence="$(jq -r '.artifacts.sequence' "${tmp_file}")"
  mv "${tmp_file}" "${IOS_WDA_CACHE_FILE}"

  printf '%s/%03d-%s.%s\n' "${run_dir}" "${sequence}" "${slug}" "${extension}"
}

ios_wda_write_json_artifact() {
  local label="$1"
  local payload="$2"
  local requested_run_dir="${3:-}"
  local path

  path="$(ios_wda_reserve_artifact_path "${label}" "json" "${requested_run_dir}")"
  printf '%s\n' "${payload}" | jq '.' >"${path}"
  printf '%s\n' "${path}"
}

ios_wda_emit_json() {
  local payload="$1"
  printf '%s\n' "${payload}" | jq '.'
}

ios_wda_wait_for_ready() {
  local host="$1"
  local port="$2"
  local attempts="${3:-30}"
  local interval="${4:-1}"
  local status_json
  local attempt=1

  while [[ "${attempt}" -le "${attempts}" ]]; do
    # 尝试本地连接
    if status_json="$(curl --max-time 2 -sf "http://${host}:${port}/status" 2>/dev/null)"; then
      if [[ "$(printf '%s\n' "${status_json}" | jq -r '.value.ready // false')" == "true" ]]; then
        printf '%s\n' "${status_json}"
        return 0
      fi
    fi
    
    # 尝试设备 IP 连接
    local device_ip
    device_ip="$(ios_wda_cache_get '.connection.deviceIp')"
    if [[ -n "${device_ip}" ]]; then
      if status_json="$(curl --max-time 2 -sf "http://${device_ip}:${port}/status" 2>/dev/null)"; then
        if [[ "$(printf '%s\n' "${status_json}" | jq -r '.value.ready // false')" == "true" ]]; then
          printf '%s\n' "${status_json}"
          return 0
        fi
      fi
    fi
    
    sleep "${interval}"
    attempt=$((attempt + 1))
  done

  return 1
}

