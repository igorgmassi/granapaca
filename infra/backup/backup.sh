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
RESTIC_OUT_FILE=""

log() {
  printf '%s [granapaca-backup] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$1"
}

write_status() {
  local state="$1"
  local detail="$2"
  if [[ -n "$STATUS_FILE" ]]; then
    local status_dir tmp_status
    status_dir="$(dirname "$STATUS_FILE")"
    mkdir -p "$status_dir"
    tmp_status="$(mktemp "${status_dir}/.granapaca-backup-status.XXXXXX")"
    if ! printf 'timestamp=%s\nstatus=%s\nstep=%s\n' \
      "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$state" "$detail" > "$tmp_status"; then
      rm -f "$tmp_status"
      return 1
    fi
    # Status file holds only timestamp/status/step (no secrets); 0644 allows non-root containers to read it.
    chmod 644 "$tmp_status"
    mv -f "$tmp_status" "$STATUS_FILE"
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
  if [[ -n "${RESTIC_OUT_FILE:-}" ]]; then
    rm -f "$RESTIC_OUT_FILE" 2>/dev/null || true
  fi
  if [[ "$BACKUP_SUCCEEDED" != "true" ]]; then
    log "ERROR: backup failed during step '${CURRENT_STEP}' (exit ${exit_code})."
    write_status "failed" "$CURRENT_STEP" || true
    notify_failure "$CURRENT_STEP" || true
  fi
}
trap on_exit EXIT

extract_snapshot_id() {
  local json_file="$1"
  local snapshot_id=""
  if command -v jq >/dev/null 2>&1; then
    snapshot_id="$(jq -r 'select(.message_type == "summary") | .snapshot_id // empty' "$json_file" 2>/dev/null | tail -n 1 || true)"
  fi
  if [[ -z "$snapshot_id" ]]; then
    snapshot_id="$(grep -oE '"snapshot_id"[[:space:]]*:[[:space:]]*"[0-9a-fA-F]+"' "$json_file" | tail -n 1 | sed -E 's/.*"([0-9a-fA-F]+)"$/\1/' || true)"
  fi
  printf '%s' "$snapshot_id"
}

extract_total_bytes() {
  local json_file="$1"
  local total_bytes=""
  if command -v jq >/dev/null 2>&1; then
    total_bytes="$(jq -r 'select(.message_type == "summary") | .total_bytes_processed // empty' "$json_file" 2>/dev/null | tail -n 1 || true)"
  fi
  if [[ -z "$total_bytes" ]]; then
    total_bytes="$(grep -oE '"total_bytes_processed"[[:space:]]*:[[:space:]]*[0-9]+' "$json_file" | tail -n 1 | sed -E 's/.*:[[:space:]]*([0-9]+)$/\1/' || true)"
  fi
  printf '%s' "$total_bytes"
}

forget_partial_snapshot() {
  local snapshot_id="$1"
  if [[ -n "$snapshot_id" ]]; then
    log "Removing partial or empty snapshot '${snapshot_id}' from restic repository..."
    restic forget --prune --quiet "$snapshot_id" || log "WARNING: failed to remove partial snapshot '${snapshot_id}'."
  fi
}

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

  CURRENT_STEP="postgres_healthcheck"
  log "Checking PostgreSQL container health..."
  docker compose -f "$COMPOSE_FILE" exec -T db \
    pg_isready -U "$postgres_user" -d "$postgres_db" >/dev/null

  CURRENT_STEP="postgres_backup"
  log "Streaming PostgreSQL dump directly into restic..."
  local producer_status restic_status snapshot_id total_bytes
  RESTIC_OUT_FILE="$(mktemp)"

  set +e
  docker compose -f "$COMPOSE_FILE" exec -T db \
    pg_dump -U "$postgres_user" -d "$postgres_db" --format=custom --no-owner \
    | restic backup \
      --stdin \
      --stdin-filename granapaca-postgres.dump \
      --tag granapaca \
      --tag postgres \
      --json >"$RESTIC_OUT_FILE"
  producer_status=${PIPESTATUS[0]}
  restic_status=${PIPESTATUS[1]}
  set -e

  snapshot_id="$(extract_snapshot_id "$RESTIC_OUT_FILE")"
  total_bytes="$(extract_total_bytes "$RESTIC_OUT_FILE")"
  rm -f "$RESTIC_OUT_FILE"
  RESTIC_OUT_FILE=""

  if [[ "$producer_status" -ne 0 || "$restic_status" -ne 0 ]]; then
    forget_partial_snapshot "$snapshot_id"
    log "ERROR: PostgreSQL backup stream failed (pg_dump=${producer_status}, restic=${restic_status})."
    return 1
  fi
  if [[ -z "$total_bytes" || "$total_bytes" -le 0 ]]; then
    forget_partial_snapshot "$snapshot_id"
    log "ERROR: PostgreSQL backup produced an empty snapshot (0 bytes)."
    return 1
  fi

  CURRENT_STEP="files_backup"
  if docker volume inspect "$APPDATA_VOLUME" >/dev/null 2>&1; then
    log "Streaming encrypted files volume (${APPDATA_VOLUME}) into restic..."
    RESTIC_OUT_FILE="$(mktemp)"

    set +e
    docker run --rm \
      -v "${APPDATA_VOLUME}:/data:ro" \
      postgres:18-alpine \
      tar -cf - -C /data . \
      | restic backup \
        --stdin \
        --stdin-filename granapaca-files.tar \
        --tag granapaca \
        --tag files \
        --json >"$RESTIC_OUT_FILE"
    producer_status=${PIPESTATUS[0]}
    restic_status=${PIPESTATUS[1]}
    set -e

    snapshot_id="$(extract_snapshot_id "$RESTIC_OUT_FILE")"
    total_bytes="$(extract_total_bytes "$RESTIC_OUT_FILE")"
    rm -f "$RESTIC_OUT_FILE"
    RESTIC_OUT_FILE=""

    if [[ "$producer_status" -ne 0 || "$restic_status" -ne 0 ]]; then
      forget_partial_snapshot "$snapshot_id"
      log "ERROR: files volume backup stream failed (tar=${producer_status}, restic=${restic_status})."
      return 1
    fi
    if [[ -z "$total_bytes" || "$total_bytes" -le 0 ]]; then
      forget_partial_snapshot "$snapshot_id"
      log "ERROR: files volume backup produced an empty snapshot (0 bytes)."
      return 1
    fi
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

  CURRENT_STEP="write_status"
  write_status "ok" "completed"
  BACKUP_SUCCEEDED="true"
  log "Backup completed and verified successfully."
}

main "$@"
