#!/usr/bin/env bash

# ios_wda_session_manager.sh — 统一 session 管理器
# 确保 session 状态最新、唯一、无过期
# 用法：bash ios_wda_session_manager.sh [--bundle-id <BUNDLE_ID>] [--action <check|create|delete|ensure>]

set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_ios_wda_common.sh"

# 默认参数
host="${IOS_WDA_DEFAULT_HOST}"
port="${IOS_WDA_DEFAULT_PORT}"
bundle_id=""
action="ensure"  # check, create, delete, ensure
force_new="false"
session_id=""

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) host="$2"; shift 2 ;;
    --port) port="$2"; shift 2 ;;
    --bundle-id) bundle_id="$2"; shift 2 ;;
    --action) action="$2"; shift 2 ;;
    --force-new) force_new="true"; shift ;;
    --session-id) session_id="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

ios_wda_require_tools jq curl

# 获取设备 IP
get_device_ip() {
  local device_ip=""
  device_ip="$(ios_wda_cache_get '.connection.deviceIp')"
  if [[ -n "${device_ip}" ]]; then
    # 验证设备 IP 是否可达
    if curl --max-time 5 -sf "http://${device_ip}:${port}/status" >/dev/null 2>&1; then
      echo "${device_ip}"
      return 0
    fi
  fi
  echo ""
  return 1
}

# 获取基础 URL
get_base_url() {
  local device_ip
  device_ip="$(get_device_ip)"
  if [[ -n "${device_ip}" ]]; then
    echo "http://${device_ip}:${port}"
  else
    echo "http://${host}:${port}"
  fi
}

# 验证 session 是否有效
validate_session() {
  local sid="$1"
  local base_url="$2"
  
  # 检查 session 是否存在且可访问
  if curl --max-time 5 -sf "${base_url}/session/${sid}/source" >/dev/null 2>&1; then
    return 0
  fi
  
  # 检查 session 是否在 WDA 中存在
  local sessions_response
  if sessions_response="$(curl --max-time 5 -sf "${base_url}/session" 2>/dev/null)"; then
    local existing_sessions
    existing_sessions="$(printf '%s\n' "${sessions_response}" | jq -r '.value[].id // empty' 2>/dev/null)"
    if echo "${existing_sessions}" | grep -q "${sid}"; then
      return 0
    fi
  fi
  
  return 1
}

# 获取所有活跃 session
get_active_sessions() {
  local base_url="$1"
  curl --max-time 5 -sf "${base_url}/session" 2>/dev/null | jq -r '.value[].id // empty' 2>/dev/null || true
}

# 删除指定 session
delete_session() {
  local sid="$1"
  local base_url="$2"
  
  # 尝试删除指定 session
  curl -sf -X DELETE "${base_url}/session/${sid}" >/dev/null 2>&1 || \
  curl -sf -X DELETE "${base_url}/session" >/dev/null 2>&1 || true
  
  return 0
}

# 删除所有活跃 session
delete_all_sessions() {
  local base_url="$1"
  local sessions
  sessions="$(get_active_sessions "${base_url}")"
  
  while IFS= read -r sid; do
    if [[ -n "${sid}" ]]; then
      echo "   删除旧 session: ${sid}" >&2
      delete_session "${sid}" "${base_url}"
    fi
  done <<< "${sessions}"
}

# 创建新 session
create_session() {
  local base_url="$1"
  local device_name
  local device_udid
  
  # 从缓存获取设备信息
  device_name="$(ios_wda_cache_get '.device.name' || echo 'iPhone')"
  device_udid="$(ios_wda_cache_get '.device.udid' || echo '')"
  
  # 构建 capabilities
  local capabilities_json
  capabilities_json="$(jq -nc \
    --arg platformName "iOS" \
    --arg deviceName "${device_name}" \
    --arg udid "${device_udid}" \
    --arg bundleId "${bundle_id}" \
    '{
      capabilities: {
        alwaysMatch: (
          {platformName: $platformName, deviceName: $deviceName, udid: $udid}
          + (if $bundleId == "" then {} else {bundleId: $bundleId} end)
        )
      }
    }')"
  
  # 创建 session
  local create_response
  create_response="$(curl --max-time 30 -sf -X POST "${base_url}/session" \
    -H 'Content-Type: application/json' \
    -d "${capabilities_json}")"
  
  local new_session_id
  new_session_id="$(printf '%s\n' "${create_response}" | jq -r '.sessionId // .value.sessionId // empty')"
  
  if [[ -z "${new_session_id}" ]]; then
    echo "   Session 创建失败" >&2
    printf '%s\n' "${create_response}" | jq '.' >&2
    return 1
  fi
  
  echo "${new_session_id}"
  return 0
}

# 更新缓存中的 session 信息
update_cache_session() {
  local sid="$1"
  local action_type="$2"
  
  local cache_payload
  cache_payload="$(jq -n \
    --arg sessionId "${sid}" \
    --arg bundleId "${bundle_id}" \
    --arg checkedAt "$(ios_wda_now_iso)" \
    --arg action "${action_type}" \
    '{session: {id: $sessionId, bundleId: (if $bundleId == "" then null else $bundleId end), checkedAt: $checkedAt, action: $action}}')"
  
  ios_wda_cache_merge_json "${cache_payload}"
}

# 清除缓存中的 session 信息
clear_cache_session() {
  ios_wda_cache_clear_session
}

# 主逻辑
main() {
  local base_url
  base_url="$(get_base_url)"
  
  echo "Session 管理器 - 动作: ${action}" >&2
  echo "   基础 URL: ${base_url}" >&2
  
  case "${action}" in
    check)
      # 检查 session 状态
      if [[ -z "${session_id}" ]]; then
        session_id="$(ios_wda_cache_get '.session.id')"
      fi
      
      if [[ -z "${session_id}" ]]; then
        echo "   没有缓存的 session" >&2
        jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "no-session"}'
        return 1
      fi
      
      echo "   检查 session: ${session_id}" >&2
      if validate_session "${session_id}" "${base_url}"; then
        echo "   Session 有效" >&2
        jq -n \
          --arg sessionId "${session_id}" \
          --arg checkedAt "$(ios_wda_now_iso)" \
          '{ok: true, checkedAt: $checkedAt, sessionId: $sessionId, status: "valid"}'
        return 0
      else
        echo "   Session 无效" >&2
        jq -n \
          --arg sessionId "${session_id}" \
          --arg checkedAt "$(ios_wda_now_iso)" \
          '{ok: false, checkedAt: $checkedAt, sessionId: $sessionId, status: "invalid"}'
        return 1
      fi
      ;;
    
    create)
      # 创建新 session
      echo "   清除现有 session..." >&2
      delete_all_sessions "${base_url}"
      
      echo "   创建新 session..." >&2
      local new_session_id
      new_session_id="$(create_session "${base_url}")"
      
      if [[ -z "${new_session_id}" ]]; then
        jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "create-failed"}'
        return 1
      fi
      
      echo "   Session 创建成功: ${new_session_id}" >&2
      update_cache_session "${new_session_id}" "created"
      
      jq -n \
        --arg sessionId "${new_session_id}" \
        --arg checkedAt "$(ios_wda_now_iso)" \
        '{ok: true, checkedAt: $checkedAt, sessionId: $sessionId, action: "created"}'
      return 0
      ;;
    
    delete)
      # 删除 session
      if [[ -z "${session_id}" ]]; then
        session_id="$(ios_wda_cache_get '.session.id')"
      fi
      
      if [[ -n "${session_id}" ]]; then
        echo "   删除 session: ${session_id}" >&2
        delete_session "${session_id}" "${base_url}"
      fi
      
      echo "   清除所有 session..." >&2
      delete_all_sessions "${base_url}"
      
      clear_cache_session
      
      jq -n \
        --arg checkedAt "$(ios_wda_now_iso)" \
        '{ok: true, checkedAt: $checkedAt, action: "deleted"}'
      return 0
      ;;
    
    ensure)
      # 确保 session 有效（检查 + 创建）
      if [[ -z "${session_id}" ]]; then
        session_id="$(ios_wda_cache_get '.session.id')"
      fi
      
      # 如果强制创建新 session
      if [[ "${force_new}" == "true" ]]; then
        echo "   强制创建新 session..." >&2
        delete_all_sessions "${base_url}"
        session_id=""
      fi
      
      # 检查现有 session 是否有效
      local session_valid="false"
      if [[ -n "${session_id}" ]]; then
        echo "   检查现有 session: ${session_id}" >&2
        if validate_session "${session_id}" "${base_url}"; then
          session_valid="true"
          echo "   Session 有效，复用" >&2
        else
          echo "   Session 无效，需要创建新 session" >&2
          delete_session "${session_id}" "${base_url}"
          session_id=""
        fi
      fi
      
      # 如果没有有效 session，创建新 session
      if [[ "${session_valid}" != "true" ]]; then
        echo "   创建新 session..." >&2
        local new_session_id
        new_session_id="$(create_session "${base_url}")"
        
        if [[ -z "${new_session_id}" ]]; then
          jq -n --arg checkedAt "$(ios_wda_now_iso)" '{ok: false, checkedAt: $checkedAt, reason: "create-failed"}'
          return 1
        fi
        
        session_id="${new_session_id}"
        echo "   Session 创建成功: ${session_id}" >&2
        update_cache_session "${session_id}" "created"
      else
        update_cache_session "${session_id}" "reused"
      fi
      
      # 激活应用（如果指定了 bundle-id）
      if [[ -n "${bundle_id}" && "${bundle_id}" != "null" ]]; then
        echo "   激活应用: ${bundle_id}" >&2
        curl --max-time 15 -sf -X POST "${base_url}/session/${session_id}/wda/apps/activate" \
          -H 'Content-Type: application/json' \
          -d "$(jq -nc --arg bundleId "${bundle_id}" '{bundleId: $bundleId}')" >/dev/null 2>&1 || true
      fi
      
      jq -n \
        --arg sessionId "${session_id}" \
        --arg checkedAt "$(ios_wda_now_iso)" \
        --arg action "$(if [[ "${session_valid}" == "true" ]]; then echo "reused"; else echo "created"; fi)" \
        '{ok: true, checkedAt: $checkedAt, sessionId: $sessionId, action: $action}'
      return 0
      ;;
    
    *)
      echo "未知动作: ${action}" >&2
      return 1
      ;;
  esac
}

# 执行主逻辑
main