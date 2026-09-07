#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=${ERPNEXT_V16_TEST_ROOT:-/opt/erpnext-v16-test}
ENV_FILE="$ROOT_DIR/.env"
SITE_NAME=${SITE_NAME:-erptest.jxmhfc.com}
BACKUP_DIR="$ROOT_DIR/backups"

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$ENV_FILE"
    set +a
    SITE_NAME=${SITE_NAME:-erptest.jxmhfc.com}
  fi
}

die() {
  printf 'backup: %s\n' "$*" >&2
  exit 1
}

require_nonempty_recent_file() {
  if ! find "$BACKUP_DIR" -type f -mtime -1 -size +0c | grep -q .; then
    die "备份目录中没有一天内生成的非空文件"
  fi
}

copy_backend_backups() {
  local source_dir
  source_dir="$ROOT_DIR/sites/$SITE_NAME/private/backups"
  [[ -d "$source_dir" ]] || die "未找到后端备份目录: $source_dir"
  mkdir -p "$BACKUP_DIR"
  if ! find "$source_dir" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
    die "后端备份目录为空: $source_dir"
  fi
  cp -a "$source_dir"/. "$BACKUP_DIR"/
}

cleanup_old_backups() {
  find "$BACKUP_DIR" -type f -mtime +7 -delete
}

main() {
  load_env
  umask 077
  cd "$ROOT_DIR"
  bench --site "$SITE_NAME" backup --with-files --compress
  copy_backend_backups
  cleanup_old_backups
  require_nonempty_recent_file
}

main "$@"
