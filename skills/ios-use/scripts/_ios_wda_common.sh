#!/usr/bin/env bash

set -euo pipefail

IOS_WDA_COMMON_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
IOS_WDA_REPO_ROOT="$(CDPATH= cd -- "${IOS_WDA_COMMON_DIR}/../../.." && pwd)"
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

  ios_wda_init_cache_file
  tmp_file="$(mktemp "${IOS_WDA_TMP_DIR}/ios-use-cache.XXXXXX")"
  jq -s '.[0] * .[1]' "${IOS_WDA_CACHE_FILE}" <(printf '%s\n' "${payload}") >"${tmp_file}"
  mv "${tmp_file}" "${IOS_WDA_CACHE_FILE}"
}

ios_wda_cache_clear_session() {
  local tmp_file

  ios_wda_init_cache_file
  tmp_file="$(mktemp "${IOS_WDA_TMP_DIR}/ios-use-cache.XXXXXX")"
  jq '.session = {}' "${IOS_WDA_CACHE_FILE}" >"${tmp_file}"
  mv "${tmp_file}" "${IOS_WDA_CACHE_FILE}"
}

ios_wda_local_listener_pid() {
  local port="${1:-${IOS_WDA_DEFAULT_PORT}}"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true
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

ios_wda_status_json() {
  local host="${1:-${IOS_WDA_DEFAULT_HOST}}"
  local port="${2:-${IOS_WDA_DEFAULT_PORT}}"
  curl -sf "http://${host}:${port}/status"
}

ios_wda_session_source() {
  local session_id="$1"
  local host="${2:-${IOS_WDA_DEFAULT_HOST}}"
  local port="${3:-${IOS_WDA_DEFAULT_PORT}}"
  curl -sf "http://${host}:${port}/session/${session_id}/source"
}

ios_wda_make_run_dir() {
  local run_dir="${IOS_WDA_TMP_DIR}/$(date +%y%m%d%H%M%S)"
  mkdir -p "${run_dir}"
  printf '%s\n' "${run_dir}"
}

ios_wda_emit_json() {
  local payload="$1"
  printf '%s\n' "${payload}" | jq '.'
}

ios_wda_try_wda_build() {
  local udid="$1"
  local project_path="${2:-${IOS_WDA_DEFAULT_PROJECT_PATH}}"
  local scheme="${3:-${IOS_WDA_DEFAULT_SCHEME}}"
  local run_dir="$4"
  local test_without_building_log="${run_dir}/wda-test-without-building.log"
  local full_test_log="${run_dir}/wda-test.log"
  local test_without_building_status="failed"
  local full_test_status="skipped"

  if xcodebuild -project "${project_path}" -scheme "${scheme}" -destination "id=${udid}" test-without-building >"${test_without_building_log}" 2>&1; then
    test_without_building_status="passed"
  else
    if xcodebuild -project "${project_path}" -scheme "${scheme}" -destination "id=${udid}" test >"${full_test_log}" 2>&1; then
      full_test_status="passed"
    else
      full_test_status="failed"
      printf '%s\n' "$(jq -n \
        --arg result "failed" \
        --arg method "test" \
        --arg projectPath "${project_path}" \
        --arg scheme "${scheme}" \
        --arg withoutBuildingLog "${test_without_building_log}" \
        --arg fullTestLog "${full_test_log}" \
        --argjson withoutBuildingPassed false \
        --argjson fullTestPassed false \
        '{
          result: $result,
          method: $method,
          projectPath: $projectPath,
          scheme: $scheme,
          testWithoutBuildingLog: $withoutBuildingLog,
          fullTestLog: $fullTestLog,
          withoutBuildingPassed: $withoutBuildingPassed,
          fullTestPassed: $fullTestPassed
        }')"
      return 1
    fi
  fi

  printf '%s\n' "$(jq -n \
    --arg result "passed" \
    --arg method "$([[ "${test_without_building_status}" == "passed" ]] && printf 'test-without-building' || printf 'test')" \
    --arg projectPath "${project_path}" \
    --arg scheme "${scheme}" \
    --arg withoutBuildingLog "${test_without_building_log}" \
    --arg fullTestLog "$([[ "${full_test_status}" == "passed" ]] && printf '%s' "${full_test_log}" || printf '')" \
    --argjson withoutBuildingPassed "$([[ "${test_without_building_status}" == "passed" ]] && printf 'true' || printf 'false')" \
    --argjson fullTestPassed "$([[ "${full_test_status}" == "passed" ]] && printf 'true' || printf 'false')" \
    '{
      result: $result,
      method: $method,
      projectPath: $projectPath,
      scheme: $scheme,
      testWithoutBuildingLog: $withoutBuildingLog,
      fullTestLog: (if $fullTestLog == "" then null else $fullTestLog end),
      withoutBuildingPassed: $withoutBuildingPassed,
      fullTestPassed: $fullTestPassed
    }')"
}