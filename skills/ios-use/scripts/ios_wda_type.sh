#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
session_id=""
element_id=""
using=""
locator=""
text=""
text_file=""
frequency="60"
clear_first="false"
click_first="true"
verify_text="true"
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
    --session-id)
      session_id="$2"
      shift 2
      ;;
    --element-id)
      element_id="$2"
      shift 2
      ;;
    --using)
      using="$2"
      shift 2
      ;;
    --locator)
      locator="$2"
      shift 2
      ;;
    --text)
      text="$2"
      shift 2
      ;;
    --text-file)
      text_file="$2"
      shift 2
      ;;
    --frequency)
      frequency="$2"
      shift 2
      ;;
    --clear)
      clear_first="true"
      shift
      ;;
    --no-click)
      click_first="false"
      shift
      ;;
    --no-verify)
      verify_text="false"
      shift
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

if [[ -z "${session_id}" ]]; then
  session_id="$(ios_wda_cache_get '.session.id')"
fi

if [[ -z "${session_id}" ]]; then
  payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "no-session"}')"
  ios_wda_emit_json "${payload}"
  exit 2
fi

if [[ -n "${text_file}" ]]; then
  text="$(cat "${text_file}")"
fi

if [[ -z "${text}" ]]; then
  payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "no-text"}')"
  ios_wda_emit_json "${payload}"
  exit 3
fi

if ! ios_wda_session_source "${session_id}" "${host}" "${port}" >/dev/null 2>&1; then
  payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" --arg sessionId "${session_id}" '{ok: false, checkedAt: $checkedAt, reason: "invalid-session", sessionId: $sessionId}')"
  ios_wda_emit_json "${payload}"
  exit 4
fi

base_url="http://${host}:${port}/session/${session_id}"
find_response_path=""

if [[ -z "${element_id}" ]]; then
  if [[ -z "${using}" || -z "${locator}" ]]; then
    payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "missing-locator"}')"
    ios_wda_emit_json "${payload}"
    exit 5
  fi

  find_response="$(curl -sf -X POST "${base_url}/element" -H 'Content-Type: application/json' -d "$(jq -nc --arg using "${using}" --arg value "${locator}" '{using: $using, value: $value}')")"
  find_response_path="$(ios_wda_write_json_artifact "type-find-element-response" "${find_response}" "${run_dir}")"
  element_id="$(printf '%s\n' "${find_response}" | jq -r '.value.ELEMENT // .value["element-6066-11e4-a52e-4f735466cecf"] // empty')"
  if [[ -z "${element_id}" ]]; then
    payload="$(jq -n \
      --arg checkedAt "$(ios_wda_now_iso)" \
      --arg using "${using}" \
      --arg locator "${locator}" \
      --argjson response "${find_response}" \
      '{
        ok: false,
        checkedAt: $checkedAt,
        reason: "element-not-found",
        using: $using,
        locator: $locator,
        response: $response
      }')"
    result_path="$(ios_wda_write_json_artifact "type-result" "${payload}" "${run_dir}")"
    payload="$(printf '%s\n' "${payload}" | jq --arg resultPath "${result_path}" --arg findResponsePath "${find_response_path}" '. + {resultPath: $resultPath, findResponsePath: $findResponsePath}')"
    ios_wda_emit_json "${payload}"
    exit 6
  fi
fi

click_response_path=""
if [[ "${click_first}" == "true" ]]; then
  click_response="$(curl -sf -X POST "${base_url}/element/${element_id}/click" -H 'Content-Type: application/json' -d '{}')"
  click_response_path="$(ios_wda_write_json_artifact "type-click-response" "${click_response}" "${run_dir}")"
fi

clear_response_path=""
if [[ "${clear_first}" == "true" ]]; then
  clear_response="$(curl -sf -X POST "${base_url}/element/${element_id}/clear" -H 'Content-Type: application/json' -d '{}')"
  clear_response_path="$(ios_wda_write_json_artifact "type-clear-response" "${clear_response}" "${run_dir}")"
fi

set_value_response="$(curl -sf -X POST "${base_url}/element/${element_id}/value" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg text "${text}" --argjson frequency "${frequency}" '{value: [$text], frequency: $frequency}')")"
set_value_response_path="$(ios_wda_write_json_artifact "type-set-value-response" "${set_value_response}" "${run_dir}")"

verified_value=""
verify_response_path=""
if [[ "${verify_text}" == "true" ]]; then
  verify_response="$(curl -sf "${base_url}/element/${element_id}/text" || printf '{}')"
  verify_response_path="$(ios_wda_write_json_artifact "type-verify-text-response" "${verify_response}" "${run_dir}")"
  verified_value="$(printf '%s\n' "${verify_response}" | jq -r '.value // empty' || true)"
fi

payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg sessionId "${session_id}" \
  --arg elementId "${element_id}" \
  --arg using "${using}" \
  --arg locator "${locator}" \
  --arg enteredText "${text}" \
  --arg verifiedValue "${verified_value}" \
  --arg runDir "${run_dir}" \
  --arg findResponsePath "${find_response_path}" \
  --arg clickResponsePath "${click_response_path}" \
  --arg clearResponsePath "${clear_response_path}" \
  --arg setValueResponsePath "${set_value_response_path}" \
  --arg verifyResponsePath "${verify_response_path}" \
  '{
    ok: true,
    checkedAt: $checkedAt,
    sessionId: $sessionId,
    elementId: $elementId,
    using: (if $using == "" then null else $using end),
    locator: (if $locator == "" then null else $locator end),
    runDir: $runDir,
    findResponsePath: (if $findResponsePath == "" then null else $findResponsePath end),
    clickResponsePath: (if $clickResponsePath == "" then null else $clickResponsePath end),
    clearResponsePath: (if $clearResponsePath == "" then null else $clearResponsePath end),
    setValueResponsePath: (if $setValueResponsePath == "" then null else $setValueResponsePath end),
    verifyResponsePath: (if $verifyResponsePath == "" then null else $verifyResponsePath end),
    enteredTextLength: ($enteredText | length),
    verifiedValue: (if $verifiedValue == "" then null else $verifiedValue end)
  }')"

result_path="$(ios_wda_write_json_artifact "type-result" "${payload}" "${run_dir}")"
payload="$(printf '%s\n' "${payload}" | jq --arg resultPath "${result_path}" '. + {resultPath: $resultPath}')"

ios_wda_emit_json "${payload}"