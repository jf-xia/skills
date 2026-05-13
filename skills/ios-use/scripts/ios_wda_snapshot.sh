#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
session_id=""
output_dir=""
prefix="snapshot"
capture_source="true"
capture_accessible="true"
capture_screenshot="true"

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
    --session-id)
      session_id="$2"
      shift 2
      ;;
    --output-dir)
      output_dir="$2"
      shift 2
      ;;
    --prefix)
      prefix="$2"
      shift 2
      ;;
    --only-source)
      capture_accessible="false"
      capture_screenshot="false"
      shift
      ;;
    --only-accessible)
      capture_source="false"
      capture_screenshot="false"
      shift
      ;;
    --only-screenshot)
      capture_source="false"
      capture_accessible="false"
      shift
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ios_wda_require_tools jq curl base64
ios_wda_init_cache_file

if [[ -z "${session_id}" ]]; then
  session_id="$(ios_wda_cache_get '.session.id')"
fi

if [[ -z "${session_id}" ]]; then
  payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "no-session"}')"
  ios_wda_emit_json "${payload}"
  exit 2
fi

if ! ios_wda_session_source "${session_id}" "${host}" "${port}" >/dev/null 2>&1; then
  payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" --arg sessionId "${session_id}" '{ok: false, checkedAt: $checkedAt, reason: "invalid-session", sessionId: $sessionId}')"
  ios_wda_emit_json "${payload}"
  exit 3
fi

if [[ -z "${output_dir}" ]]; then
  output_dir="$(ios_wda_use_run_dir "")"
else
  output_dir="$(ios_wda_use_run_dir "${output_dir}")"
fi
mkdir -p "${output_dir}"

base_url="http://${host}:${port}/session/${session_id}"
source_path=""
accessible_path=""
screenshot_path=""

if [[ "${capture_source}" == "true" ]]; then
  source_path="$(ios_wda_reserve_artifact_path "${prefix}-source" "xml" "${output_dir}")"
  curl -sf "${base_url}/source" -o "${source_path}"
fi

if [[ "${capture_accessible}" == "true" ]]; then
  accessible_path="$(ios_wda_reserve_artifact_path "${prefix}-accessible-source" "json" "${output_dir}")"
  curl -sf "${base_url}/wda/accessibleSource" -o "${accessible_path}"
fi

if [[ "${capture_screenshot}" == "true" ]]; then
  screenshot_path="$(ios_wda_reserve_artifact_path "${prefix}-screen" "png" "${output_dir}")"
  curl -sf "${base_url}/screenshot" | jq -r '.value' | base64 --decode >"${screenshot_path}"
fi

cache_payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg outputDir "${output_dir}" \
  --arg prefix "${prefix}" \
  --arg sourcePath "$([[ "${capture_source}" == "true" ]] && printf '%s' "${source_path}" || printf '')" \
  --arg accessiblePath "$([[ "${capture_accessible}" == "true" ]] && printf '%s' "${accessible_path}" || printf '')" \
  --arg screenshotPath "$([[ "${capture_screenshot}" == "true" ]] && printf '%s' "${screenshot_path}" || printf '')" \
  '{
    artifacts: {
      lastRunDir: $outputDir,
      lastSnapshot: {
        checkedAt: $checkedAt,
        prefix: $prefix,
        sourcePath: (if $sourcePath == "" then null else $sourcePath end),
        accessiblePath: (if $accessiblePath == "" then null else $accessiblePath end),
        screenshotPath: (if $screenshotPath == "" then null else $screenshotPath end)
      }
    }
  }')"
ios_wda_cache_merge_json "${cache_payload}"

payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg sessionId "${session_id}" \
  --arg outputDir "${output_dir}" \
  --arg sourcePath "$([[ "${capture_source}" == "true" ]] && printf '%s' "${source_path}" || printf '')" \
  --arg accessiblePath "$([[ "${capture_accessible}" == "true" ]] && printf '%s' "${accessible_path}" || printf '')" \
  --arg screenshotPath "$([[ "${capture_screenshot}" == "true" ]] && printf '%s' "${screenshot_path}" || printf '')" \
  '{
    ok: true,
    checkedAt: $checkedAt,
    sessionId: $sessionId,
    outputDir: $outputDir,
    sourcePath: (if $sourcePath == "" then null else $sourcePath end),
    accessiblePath: (if $accessiblePath == "" then null else $accessiblePath end),
    screenshotPath: (if $screenshotPath == "" then null else $screenshotPath end)
  }')"

result_path="$(ios_wda_write_json_artifact "${prefix}-result" "${payload}" "${output_dir}")"
payload="$(printf '%s\n' "${payload}" | jq --arg resultPath "${result_path}" '. + {resultPath: $resultPath}')"

ios_wda_emit_json "${payload}"