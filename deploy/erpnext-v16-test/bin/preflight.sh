#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=${ERPNEXT_V16_TEST_ROOT:-/opt/erpnext-v16-test}
ENV_FILE="$ROOT_DIR/.env"

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
  fi
}

die() {
  printf 'preflight: %s\n' "$*" >&2
  exit 1
}

bytes_to_gib() {
  awk -v bytes="$1" 'BEGIN { printf "%.2f", bytes / (1024 * 1024 * 1024) }'
}

report_service_state() {
  local unit state
  for unit in nginx mariadb redis-server redis docker; do
    if systemctl list-unit-files "${unit}.service" >/dev/null 2>&1 || systemctl list-unit-files "$unit" >/dev/null 2>&1; then
      state=$(systemctl is-active "$unit" 2>/dev/null || true)
      printf '%s: %s\n' "$unit" "${state:-unknown}"
    else
      printf '%s: unavailable\n' "$unit"
    fi
  done

  if pgrep -fa java >/dev/null 2>&1; then
    printf 'java: running\n'
    pgrep -fa java
  else
    printf 'java: not running\n'
  fi

  if docker info >/dev/null 2>&1; then
    printf 'docker-cli: reachable\n'
  else
    printf 'docker-cli: unreachable\n'
  fi
}

check_architecture() {
  local arch
  arch=$(uname -m)
  [[ "$arch" == x86_64 ]] || die "需要 x86_64，当前为 $arch"
}

check_root_disk() {
  local available_bytes
  available_bytes=$(df -PB1 / | awk 'NR == 2 { print $4 }')
  [[ -n "$available_bytes" ]] || die "无法读取根分区可用空间"
  (( available_bytes >= 100 * 1024 * 1024 * 1024 )) || die "根分区可用空间不足 100 GiB，当前约 $(bytes_to_gib "$available_bytes") GiB"
}

check_memory() {
  local mem_kb
  mem_kb=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
  [[ -n "$mem_kb" ]] || die "无法读取 MemAvailable"
  (( mem_kb >= 6 * 1024 * 1024 )) || die "MemAvailable 不足 6 GiB，当前约 $(awk -v kb="$mem_kb" 'BEGIN { printf "%.2f", kb / (1024 * 1024) }') GiB"
}

check_port_443() {
  if ss -H -ltn "( sport = :443 )" | grep -q .; then
    printf 'preflight: 443 端口已被占用，监听详情如下:\n' >&2
    ss -H -ltnp "( sport = :443 )" >&2 || true
    exit 1
  fi
}

list_listening_ports() {
  printf 'listening ports:\n'
  ss -H -ltnup || true
}

main() {
  load_env
  check_architecture
  check_root_disk
  check_memory
  check_port_443
  printf 'nginx test:\n'
  sudo -n nginx -t
  list_listening_ports
  printf 'service state:\n'
  report_service_state
}

main "$@"
