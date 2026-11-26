#!/usr/bin/env bash
# Encrypted backup restore and verification script for GranaPaCa (RF-65, RNF-24, ADR-029).
# Usage: ./restore.sh [postgres_snapshot_id] [files_snapshot_id]
# - When omitted, restores the latest 'postgres' snapshot (and latest 'files' snapshot if present).
# - When postgres_snapshot_id is explicit and files_snapshot_id is omitted, files restore is skipped
#   unless FILES_SNAPSHOT_ID (or the 2nd argument) is provided (e.g. a matching snapshot ID or 'latest').
# - Set RESTORE_FILES=false to skip restoring the files volume.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
COMPOSE_FILE="${COMPOSE_FILE:-${COMPOSE_DIR}/compose.yaml}"
APPDATA_VOLUME="${APPDATA_VOLUME:-granapaca_appdata}"
SNAPSHOT_ID="${1:-latest}"
FILES_SNAPSHOT_ID="${2:-${FILES_SNAPSHOT_ID:-}}"
RESTORE_FILES="${RESTORE_FILES:-true}"

log() {
  printf '%s [granapaca-restore] %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$1"
}

json_array_has_items() {
  local json="$1"
  if command -v jq >/dev/null 2>&1; then
    local count
    count="$(printf '%s' "$json" | jq 'if type == "array" then length else 0 end')"
    [[ "$count" -gt 0 ]]
  else
    local compact
    compact="$(printf '%s' "$json" | tr -d '[:space:]')"
    [[ -n "$compact" && "$compact" != "[]" && "$compact" != "null" ]]
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
  if [[ -z "${RESTIC_REPOSITORY:-}" ]]; then
    log "ERROR: RESTIC_REPOSITORY must be set."
    exit 1
  fi
  if [[ -z "${RESTIC_PASSWORD_FILE:-}" || ! -r "${RESTIC_PASSWORD_FILE}" || ! -s "${RESTIC_PASSWORD_FILE}" ]]; then
    log "ERROR: RESTIC_PASSWORD_FILE must point to a readable non-empty file."
    exit 1
  fi
  if ! command -v docker >/dev/null 2>&1; then
    log "ERROR: docker is required."
    exit 1
  fi
  if ! command -v restic >/dev/null 2>&1; then
    log "ERROR: restic is required."
    exit 1
  fi
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    log "ERROR: compose file not found at ${COMPOSE_FILE}."
    exit 1
  fi
}

main() {
  require_prerequisites

  local postgres_db postgres_user
  postgres_db="${POSTGRES_DB:-$(read_env_value "POSTGRES_DB" "granapaca")}"
  postgres_user="${POSTGRES_USER:-$(read_env_value "POSTGRES_USER" "granapaca")}"

  log "Checking PostgreSQL container health..."
  docker compose -f "$COMPOSE_FILE" exec -T db \
    pg_isready -U "$postgres_user" -d "$postgres_db" >/dev/null

  local dump_args=()
  local pg_snapshots_json
  if [[ "$SNAPSHOT_ID" == "latest" ]]; then
    dump_args+=(--tag postgres)
    pg_snapshots_json="$(restic snapshots --tag postgres --latest 1 --json)"
  else
    pg_snapshots_json="$(restic snapshots "$SNAPSHOT_ID" --json)"
  fi

  if ! json_array_has_items "$pg_snapshots_json"; then
    log "ERROR: PostgreSQL snapshot '${SNAPSHOT_ID}' not found in repository."
    exit 1
  fi

  local api_was_running="false"
  if [[ -n "$(docker compose -f "$COMPOSE_FILE" ps --status running --services 2>/dev/null | grep -x api || true)" ]]; then
    api_was_running="true"
    log "Stopping api container before database restore..."
    docker compose -f "$COMPOSE_FILE" stop api >/dev/null
  fi

  log "Streaming snapshot '${SNAPSHOT_ID}' into PostgreSQL (${postgres_db})..."
  restic dump "${dump_args[@]}" "$SNAPSHOT_ID" granapaca-postgres.dump \
    | docker compose -f "$COMPOSE_FILE" exec -T db \
      pg_restore \
        -U "$postgres_user" \
        -d "$postgres_db" \
        --clean \
        --if-exists \
        --no-owner \
        --no-privileges \
        --exit-on-error \
        --single-transaction

  if [[ "$RESTORE_FILES" != "true" ]]; then
    log "RESTORE_FILES=${RESTORE_FILES}; skipping files volume restore."
  elif [[ -n "$FILES_SNAPSHOT_ID" ]]; then
    local files_dump_args=()
    local files_snapshots_json
    if [[ "$FILES_SNAPSHOT_ID" == "latest" ]]; then
      files_dump_args+=(--tag files)
      files_snapshots_json="$(restic snapshots --tag files --latest 1 --json)"
    else
      files_snapshots_json="$(restic snapshots "$FILES_SNAPSHOT_ID" --json)"
    fi

    if ! json_array_has_items "$files_snapshots_json"; then
      log "ERROR: requested files snapshot '${FILES_SNAPSHOT_ID}' not found in repository."
      exit 1
    fi

    log "Restoring files snapshot '${FILES_SNAPSHOT_ID}' into volume (${APPDATA_VOLUME})..."
    docker volume create "$APPDATA_VOLUME" >/dev/null
    restic dump "${files_dump_args[@]}" "$FILES_SNAPSHOT_ID" granapaca-files.tar \
      | docker run --rm -i \
        -v "${APPDATA_VOLUME}:/data" \
        postgres:18-alpine \
        sh -ec 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} \; && tar -xf - -C /data'
  elif [[ "$SNAPSHOT_ID" == "latest" ]]; then
    local files_snapshots_json
    files_snapshots_json="$(restic snapshots --tag files --latest 1 --json)"
    if json_array_has_items "$files_snapshots_json"; then
      log "Restoring latest files snapshot into volume (${APPDATA_VOLUME})..."
      docker volume create "$APPDATA_VOLUME" >/dev/null
      restic dump --tag files latest granapaca-files.tar \
        | docker run --rm -i \
          -v "${APPDATA_VOLUME}:/data" \
          postgres:18-alpine \
          sh -ec 'find /data -mindepth 1 -maxdepth 1 -exec rm -rf -- {} \; && tar -xf - -C /data'
    else
      log "No files snapshot found in repository; skipping files volume restore."
    fi
  else
    log "Explicit postgres snapshot '${SNAPSHOT_ID}' requested without a files snapshot ID; skipping files volume restore."
    log "To restore files as well, pass a 2nd argument or set FILES_SNAPSHOT_ID (<snapshot_id> or 'latest')."
  fi

  log "Running post-restore verification query..."
  local table_count
  table_count="$(docker compose -f "$COMPOSE_FILE" exec -T db \
    psql -U "$postgres_user" -d "$postgres_db" -tAc \
    "SELECT count(*) FROM pg_tables WHERE schemaname NOT IN ('pg_catalog', 'information_schema');")"

  if [[ -z "$table_count" || "$table_count" -eq 0 ]]; then
    log "ERROR: restore verification failed (0 user tables found)."
    exit 1
  fi

  log "Restored schema summary (${table_count} tables):"
  docker compose -f "$COMPOSE_FILE" exec -T db \
    psql -U "$postgres_user" -d "$postgres_db" -c \
    "SELECT schemaname AS schema, relname AS table_name, n_live_tup AS estimated_rows
     FROM pg_stat_user_tables
     ORDER BY schemaname, relname;"

  docker compose -f "$COMPOSE_FILE" exec -T db \
    psql -U "$postgres_user" -d "$postgres_db" -tAc \
    "SELECT 'Applied DbUp migrations: ' || count(*) FROM public.schemaversions;" 2>/dev/null || true

  if [[ "$api_was_running" == "true" ]]; then
    log "Restarting api container..."
    docker compose -f "$COMPOSE_FILE" start api >/dev/null
  fi

  log "Restore completed and verified. Check http://127.0.0.1:8080/health and http://127.0.0.1:8080/api/v1/server-info once the API is running."
}

main "$@"
