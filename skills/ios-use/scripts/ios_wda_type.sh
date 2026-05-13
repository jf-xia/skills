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
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

ios_wda_require_tools jq curl
ios_wda_init_cache_file

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

if [[ -z "${element_id}" ]]; then
  if [[ -z "${using}" || -z "${locator}" ]]; then
    payload="$(jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "missing-locator"}')"
    ios_wda_emit_json "${payload}"
    exit 5
  fi

  find_response="$(curl -sf -X POST "${base_url}/element" -H 'Content-Type: application/json' -d "$(jq -nc --arg using "${using}" --arg value "${locator}" '{using: $using, value: $value}')")"
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
    ios_wda_emit_json "${payload}"
    exit 6
  fi
fi

if [[ "${click_first}" == "true" ]]; then
  curl -sf -X POST "${base_url}/element/${element_id}/click" -H 'Content-Type: application/json' -d '{}' >/dev/null
fi

if [[ "${clear_first}" == "true" ]]; then
  curl -sf -X POST "${base_url}/element/${element_id}/clear" -H 'Content-Type: application/json' -d '{}' >/dev/null
fi

curl -sf -X POST "${base_url}/element/${element_id}/value" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg text "${text}" --argjson frequency "${frequency}" '{value: [$text], frequency: $frequency}')" >/dev/null

verified_value=""
if [[ "${verify_text}" == "true" ]]; then
  verified_value="$(curl -sf "${base_url}/element/${element_id}/text" | jq -r '.value // empty' || true)"
fi

payload="$(jq -n \
  --arg checkedAt "$(ios_wda_now_iso)" \
  --arg sessionId "${session_id}" \
  --arg elementId "${element_id}" \
  --arg using "${using}" \
  --arg locator "${locator}" \
  --arg enteredText "${text}" \
  --arg verifiedValue "${verified_value}" \
  '{
    ok: true,
    checkedAt: $checkedAt,
    sessionId: $sessionId,
    elementId: $elementId,
    using: (if $using == "" then null else $using end),
    locator: (if $locator == "" then null else $locator end),
    enteredTextLength: ($enteredText | length),
    verifiedValue: (if $verifiedValue == "" then null else $verifiedValue end)
  }')"

ios_wda_emit_json "${payload}"