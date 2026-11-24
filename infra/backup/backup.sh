#!/usr/bin/env bash
# Encrypted off-site backup for GranaPaCa (RF-65, ADR-029).
# Streams pg_dump and the encrypted files volume directly into restic with zero unencrypted dumps on disk.

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-${COMPOSE_DIR}/compose.yaml}"
APPDATA_VOLUME="${APPDATA_VOLUME:-granapaca_appdata}"
KEEP_DAILY="${KEEP_DAILY:-7}"
KEEP_WEEKLY="${KEEP_WEEKLY:-4}"
KEEP_MONTHLY="${KEEP_MONTHLY:-6}"
STATUS_FILE="${BACKUP_STATUS_FILE:-}"
ALERT_WEBHOOK_URL="${BACKUP_ALERT_WEBHOOK_URL:-}"
CURRENT_STEP="init"
BACKUP_SUCCEEDED="false"

log() {
  printf '%s [granapaca-backup] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$1"
}

write_status() {
  local state="$1"
  local detail="$2"
  if [[ -n "$STATUS_FILE" ]]; then
    mkdir -p "$(dirname "$STATUS_FILE")"
    printf 'timestamp=%s\nstatus=%s\nstep=%s\n' \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$state" "$detail" > "$STATUS_FILE"
  fi
}

notify_failure() {
  local failed_step="$1"
  if [[ -n "$ALERT_WEBHOOK_URL" ]] && command -v curl >/dev/null 2>&1; then
    local payload
    payload="$(printf '{"event":"backup_failed","step":"%s","timestamp":"%s"}' \
      "$failed_step" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")")"
    curl --silent --show-error --max-time 10 \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$ALERT_WEBHOOK_URL" >/dev/null || true
  fi
}

on_exit() {
  local exit_code=$?
  if [[ "$BACKUP_SUCCEEDED" != "true" ]]; then
    log "ERROR: backup failed during step '${CURRENT_STEP}' (exit ${exit_code})."
    write_status "failed" "$CURRENT_STEP"
    notify_failure "$CURRENT_STEP"
  fi
}
trap on_exit EXIT

read_env_value() {
  local key="$1"
  local default_value="$2"
  local env_file="${COMPOSE_DIR}/.env"
  local value=""

  if [[ -f "$env_file" ]]; then
    value="$(grep -E "^${key}=" "$env_file" | tail -n 1 | cut -d'=' -f2- | tr -d '\r' || true)"
  fi

  if [[ -n "$value" ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$default_value"
  fi
}

require_prerequisites() {
  CURRENT_STEP="prerequisites"

  if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    log "ERROR: RESTIC_REPOSITORY must be set."
    return 1
  fi
  if [[ -z "${RESTIC_PASSWORD_FILE:-}" || ! -r "${RESTIC_PASSWORD_FILE}" || ! -s "${RESTIC_PASSWORD_FILE}" ]]; then
    log "ERROR: RESTIC_PASSWORD_FILE must point to a readable non-empty file."
    return 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: docker is required."
    return 1
  fi
  if ! command -v restic >/dev/null 2>&1; then
    log "ERROR: restic is required."
    return 1
  fi
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log "ERROR: compose file not found at ${COMPOSE_FILE}."
    return 1
  fi
}

main() {
  require_prerequisites

  local postgres_db postgres_user
  postgres_db="${POSTGRES_DB:-$(read_env_value "POSTGRES_DB" "granapaca")}"
  postgres_user="${POSTGRES_USER:-$(read_env_value "POSTGRES_USER" "granapaca")}"

  CURRENT_STEP="restic_repo_check"
  log "Checking restic repository accessibility..."
  restic cat config >/dev/null

  CURRENT_STEP="postgres_backup"
  log "Streaming PostgreSQL dump directly into restic..."
  docker compose -f "$COMPOSE_FILE" exec -T db \
    pg_dump -U "$postgres_user" -d "$postgres_db" --format=custom --no-owner \
    | restic backup \
      --stdin \
      --stdin-filename granapaca-postgres.dump \
      --tag granapaca \
      --tag postgres \
      --quiet

  CURRENT_STEP="files_backup"
  if docker volume inspect "$APPDATA_VOLUME" >/dev/null 2>&1; then
    log "Streaming encrypted files volume (${APPDATA_VOLUME}) into restic..."
    docker run --rm \
      -v "${APPDATA_VOLUME}:/data:ro" \
      postgres:18-alpine \
      tar -cf - -C /data . \
      | restic backup \
        --stdin \
        --stdin-filename granapaca-files.tar \
        --tag granapaca \
        --tag files \
        --quiet
  else
    log "Files volume (${APPDATA_VOLUME}) not present; skipping files snapshot."
  fi

  CURRENT_STEP="retention_prune"
  log "Applying retention policy (daily=${KEEP_DAILY}, weekly=${KEEP_WEEKLY}, monthly=${KEEP_MONTHLY})..."
  restic forget \
    --tag granapaca \
    --group-by tags \
    --keep-daily "$KEEP_DAILY" \
    --keep-weekly "$KEEP_WEEKLY" \
    --keep-monthly "$KEEP_MONTHLY" \
    --prune \
    --quiet

  CURRENT_STEP="integrity_check"
  log "Verifying repository integrity..."
  restic check --quiet

  BACKUP_SUCCEEDED="true"
  write_status "ok" "completed"
  log "Backup completed and verified successfully."
}

main "$@"
