#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=${ERPNEXT_V16_TEST_ROOT:-/opt/erpnext-v16-test}
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE=${ERPNEXT_V16_TEST_COMPOSE_FILE:-$ROOT_DIR/compose.yaml}
SITE_NAME=${SITE_NAME:-erptest.jxmhfc.com}
MANIFEST_FILE="$ROOT_DIR/manifest.env"

load_env() {
  for file in "$ENV_FILE" "$MANIFEST_FILE"; do
    if [[ -f "$file" ]]; then
      set -a
      # shellcheck disable=SC1090
      source "$file"
      set +a
    fi
  done
  SITE_NAME=${SITE_NAME:-erptest.jxmhfc.com}
}

die() {
  printf 'verify-local: %s\n' "$*" >&2
  exit 1
}

compose_ps() {
  local service=$1
  docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" ps -q "$service"
}

require_service_running() {
  local service=$1 cid running
  cid=$(compose_ps "$service")
  [[ -n "$cid" ]] || die "服务未启动: $service"
  running=$(docker inspect -f '{{.State.Running}}' "$cid")
  [[ "$running" == true ]] || die "服务未运行: $service"
}

check_log_config() {
  local service=$1 cid log_type max_size max_file
  cid=$(compose_ps "$service")
  [[ -n "$cid" ]] || die "无法找到容器: $service"
  read -r log_type max_size max_file < <(
    docker inspect -f '{{.HostConfig.LogConfig.Type}} {{index .HostConfig.LogConfig.Config "max-size"}} {{index .HostConfig.LogConfig.Config "max-file"}}' "$cid"
  )
  [[ "$log_type" == json-file ]] || die "$service 日志驱动不是 json-file: $log_type"
  [[ "$max_size" == 10m ]] || die "$service max-size 不是 10m: $max_size"
  [[ "$max_file" == 3 ]] || die "$service max-file 不是 3: $max_file"
}

check_root_usage() {
  local usage
  usage=$(df -P / | awk 'NR == 2 { gsub(/%/, "", $5); print $5 }')
  [[ -n "$usage" ]] || die "无法读取根分区使用率"
  (( usage < 80 )) || die "根分区使用率不低于 80%: ${usage}%"
}

check_frontend_http() {
  curl --fail --silent --show-error \
    -H "Host: $SITE_NAME" \
    http://127.0.0.1:8080/ >/dev/null
}

normalize_fingerprint() {
  tr -d '[:space:]:' | tr '[:upper:]' '[:lower:]'
}

expected_fingerprint() {
  local candidate file line value
  for candidate in \
    "${TLS_FINGERPRINT_SHA256:-}" \
    "${TLS_FINGERPRINT:-}" \
    "${SSL_FINGERPRINT_SHA256:-}" \
    "${SSL_FINGERPRINT:-}" \
    "${CERT_FINGERPRINT_SHA256:-}" \
    "${CERT_FINGERPRINT:-}" \
    "${EXPECTED_TLS_FINGERPRINT:-}"
  do
    if [[ -n "${candidate:-}" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  for file in "$ENV_FILE" "$MANIFEST_FILE"; do
    [[ -f "$file" ]] || continue
    line=$(grep -E '^(TLS_FINGERPRINT_SHA256|TLS_FINGERPRINT|SSL_FINGERPRINT_SHA256|SSL_FINGERPRINT|CERT_FINGERPRINT_SHA256|CERT_FINGERPRINT|EXPECTED_TLS_FINGERPRINT)=' "$file" | head -n1 || true)
    if [[ -n "$line" ]]; then
      value=${line#*=}
      printf '%s\n' "$value"
      return 0
    fi
  done

  return 1
}

check_tls_fingerprint() {
  local expected actual
  expected=$(expected_fingerprint) || die "未找到期望的 TLS 指纹变量"
  actual=$(
    openssl s_client -connect 127.0.0.1:443 -servername "$SITE_NAME" -showcerts </dev/null 2>/dev/null \
      | openssl x509 -noout -fingerprint -sha256 \
      | sed 's/^SHA256 Fingerprint=//'
  )
  [[ -n "$actual" ]] || die "无法读取 127.0.0.1:443 的证书指纹"
  if [[ "$(printf '%s' "$actual" | normalize_fingerprint)" != "$(printf '%s' "$expected" | normalize_fingerprint)" ]]; then
    die "TLS 指纹不匹配"
  fi
}

check_https_resolve() {
  curl --fail --silent --show-error \
    --resolve "$SITE_NAME:443:127.0.0.1" \
    "https://$SITE_NAME/" >/dev/null
}

check_bench_doctor() {
  cd "$ROOT_DIR"
  bench --site "$SITE_NAME" doctor
}

main() {
  load_env

  local services=(
    frontend
    backend
    websocket
    queue-short
    queue-long
    scheduler
    db
    redis-cache
    redis-queue
  )

  for service in "${services[@]}"; do
    require_service_running "$service"
    check_log_config "$service"
  done

  check_root_usage
  check_frontend_http
  check_tls_fingerprint
  check_https_resolve
  check_bench_doctor
}

main "$@"
