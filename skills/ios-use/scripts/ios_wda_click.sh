#!/usr/bin/env bash

# ios_wda_click.sh — 多策略点击脚本
#
# 解决 element.click() 点错位置的问题。提供 4 种点击策略：
#   element  — 直接调用 /element/:uuid/click（默认，最简单）
#   center   — 获取 rect 计算中心点，用 /wda/tap 绝对坐标点击
#   w3c      — W3C Actions pointerDown/pointerUp（最底层，模拟真实触摸）
#   offset   — 获取 rect，用 /wda/tap + 元素偏移量（偏移基准是左上角）
#
# 用法:
#   bash ios_wda_click.sh --element-id <ID> [--strategy element|center|w3c|offset]
#   bash ios_wda_click.sh --element-id <ID> --strategy offset --x-offset 50 --y-offset 20
#
# 环境:
#   需要 SESSION_ID（通过参数或缓存）

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_ios_wda_common.sh
source "${SCRIPT_DIR}/_ios_wda_common.sh"

# ── 参数解析 ──
ELEMENT_ID=""
STRATEGY="element"
X_OFFSET=""
Y_OFFSET=""
SESSION_ID_ARG=""
VERIFY="false"
HOST="${IOS_WDA_DEFAULT_HOST}"
PORT="${IOS_WDA_DEFAULT_PORT}"

# 从缓存中读取设备 IP（如果存在）
CACHED_HOST="$(ios_wda_cache_get '.connection.host')"
if [[ -n "${CACHED_HOST}" ]]; then
  HOST="${CACHED_HOST}"
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --element-id) ELEMENT_ID="$2"; shift 2 ;;
    --strategy) STRATEGY="$2"; shift 2 ;;
    --x-offset) X_OFFSET="$2"; shift 2 ;;
    --y-offset) Y_OFFSET="$2"; shift 2 ;;
    --session-id) SESSION_ID_ARG="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --verify) VERIFY="true"; shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "${ELEMENT_ID}" ]]; then
  echo "error: --element-id is required" >&2
  exit 1
fi

# ── 获取 session ID ──
SESSION_ID="${SESSION_ID_ARG:-$(ios_wda_cache_get '.session.id')}"
if [[ -z "${SESSION_ID}" ]]; then
  echo "error: no session ID (pass --session-id or run ios_wda_session.sh first)" >&2
  exit 1
fi

BASE_URL="http://${HOST}:${PORT}"

# ── 验证 session 有效性 ──
if ! curl --max-time 5 -sf "${BASE_URL}/session/${SESSION_ID}/source" >/dev/null 2>&1; then
  echo "warning: session ${SESSION_ID} 无效，尝试创建新 session..." >&2
  session_manager_result="$("${SCRIPT_DIR}/ios_wda_session_manager.sh" --host "${HOST}" --port "${PORT}" --action ensure 2>/dev/null)"
  if [[ "$(printf '%s\n' "${session_manager_result}" | jq -r '.ok')" == "true" ]]; then
    SESSION_ID="$(printf '%s\n' "${session_manager_result}" | jq -r '.sessionId')"
    echo "   新 session: ${SESSION_ID}" >&2
  else
    echo "error: 无法创建有效 session" >&2
    exit 1
  fi
fi

# ── 获取元素 rect ──
get_element_rect() {
  local rect_json
  rect_json="$(curl --max-time 10 -s \
    "${BASE_URL}/session/${SESSION_ID}/element/${ELEMENT_ID}/rect")"
  if [[ -z "${rect_json}" ]]; then
    echo "error: failed to get element rect for ${ELEMENT_ID}" >&2
    exit 1
  fi
  # 检查是否返回了错误
  if echo "${rect_json}" | jq -e '.value.error' >/dev/null 2>&1; then
    echo "error: WDA returned error: $(echo "${rect_json}" | jq -r '.value.message')" >&2
    exit 1
  fi
  printf '%s\n' "${rect_json}"
}

# ── 策略: element（默认）──
click_element() {
  local result
  result="$(curl --max-time 10 -sf -X POST \
    "${BASE_URL}/session/${SESSION_ID}/element/${ELEMENT_ID}/click" \
    -H "Content-Type: application/json" -d '{}')"
  printf '%s\n' "${result:-{}}"
}

# ── 策略: center（绝对坐标中心点）──
click_center() {
  local rect_json center_x center_y
  rect_json="$(get_element_rect)"

  # rect: { x, y, width, height }
  local x y w h
  x="$(printf '%s\n' "${rect_json}" | jq -r '.value.x')"
  y="$(printf '%s\n' "${rect_json}" | jq -r '.value.y')"
  w="$(printf '%s\n' "${rect_json}" | jq -r '.value.width')"
  h="$(printf '%s\n' "${rect_json}" | jq -r '.value.height')"

  # 中心点 = (x + width/2, y + height/2)
  center_x="$(printf '%s' "${x} ${w}" | awk '{printf "%.0f", $1 + $2/2}')"
  center_y="$(printf '%s' "${y} ${h}" | awk '{printf "%.0f", $1 + $2/2}')"

  echo "center strategy: rect=(${x},${y},${w},${h}) -> tap(${center_x},${center_y})" >&2

  local result
  result="$(curl --max-time 10 -sf -X POST \
    "${BASE_URL}/session/${SESSION_ID}/wda/tap" \
    -H "Content-Type: application/json" \
    -d "{\"x\": ${center_x}, \"y\": ${center_y}}")"
  printf '%s\n' "${result:-{}}"
}

# ── 策略: w3c（W3C Actions 模拟真实触摸）──
click_w3c() {
  local rect_json
  rect_json="$(get_element_rect)"

  local x y w h cx cy
  x="$(printf '%s\n' "${rect_json}" | jq -r '.value.x')"
  y="$(printf '%s\n' "${rect_json}" | jq -r '.value.y')"
  w="$(printf '%s\n' "${rect_json}" | jq -r '.value.width')"
  h="$(printf '%s\n' "${rect_json}" | jq -r '.value.height')"

  cx="$(printf '%s' "${x} ${w}" | awk '{printf "%.0f", $1 + $2/2}')"
  cy="$(printf '%s' "${y} ${h}" | awk '{printf "%.0f", $1 + $2/2}')"

  echo "w3c strategy: rect=(${x},${y},${w},${h}) -> tap(${cx},${cy})" >&2

  # W3C Actions: pointerMove 到绝对坐标 -> pointerDown -> pause -> pointerUp
  local payload
  payload="$(cat <<EOJSON
{
  "actions": [
    {
      "type": "pointer",
      "id": "mimo_click",
      "parameters": { "pointerType": "touch" },
      "actions": [
        { "type": "pointerMove", "duration": 0, "origin": "viewport", "x": ${cx}, "y": ${cy} },
        { "type": "pointerDown", "button": 0 },
        { "type": "pause", "duration": 100 },
        { "type": "pointerUp", "button": 0 }
      ]
    }
  ]
}
EOJSON
)"

  local result
  result="$(curl --max-time 10 -sf -X POST \
    "${BASE_URL}/session/${SESSION_ID}/actions" \
    -H "Content-Type: application/json" \
    -d "${payload}")"
  printf '%s\n' "${result:-{}}"
}

# ── 策略: offset（元素偏移，基准是左上角）──
click_offset() {
  local x_off="${X_OFFSET:-0}"
  local y_off="${Y_OFFSET:-0}"

  # 无偏移时，偏移量是元素宽高的一半（等效中心点）
  if [[ "${x_off}" == "0" && "${y_off}" == "0" ]]; then
    local rect_json
    rect_json="$(get_element_rect)"
    local w h
    w="$(printf '%s\n' "${rect_json}" | jq -r '.value.width')"
    h="$(printf '%s\n' "${rect_json}" | jq -r '.value.height')"
    x_off="$(printf '%s' "${w}" | awk '{printf "%.0f", $1/2}')"
    y_off="$(printf '%s' "${h}" | awk '{printf "%.0f", $1/2}')"
    echo "offset strategy (auto center): offset=(${x_off},${y_off})" >&2
  else
    echo "offset strategy: offset=(${x_off},${y_off})" >&2
  fi

  local result
  result="$(curl --max-time 10 -sf -X POST \
    "${BASE_URL}/session/${SESSION_ID}/wda/tap/${ELEMENT_ID}" \
    -H "Content-Type: application/json" \
    -d "{\"x\": ${x_off}, \"y\": ${y_off}}")"
  printf '%s\n' "${result:-{}}"
}

# ── 执行 ──
echo "click strategy=${STRATEGY} element=${ELEMENT_ID}" >&2

case "${STRATEGY}" in
  element) click_element ;;
  center)  click_center ;;
  w3c)     click_w3c ;;
  offset)  click_offset ;;
  *) echo "error: unknown strategy '${STRATEGY}' (use: element|center|w3c|offset)" >&2; exit 1 ;;
esac

# ── 验证（可选）──
if [[ "${VERIFY}" == "true" ]]; then
  echo "--- verify: re-fetching element state ---" >&2
  local enabled displayed
  enabled="$(curl --max-time 5 -sf "${BASE_URL}/session/${SESSION_ID}/element/${ELEMENT_ID}/enabled" | jq -r '.value')"
  displayed="$(curl --max-time 5 -sf "${BASE_URL}/session/${SESSION_ID}/element/${ELEMENT_ID}/displayed" | jq -r '.value')"
  echo "element enabled=${enabled} displayed=${displayed}" >&2
fi
