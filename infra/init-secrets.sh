#!/usr/bin/env bash
# Generates local Docker secret files for a GranaPaCa instance without overwriting existing ones.
# Secrets stay outside .env and Git, under infra/secrets/.

set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRETS_DIR="${SCRIPT_DIR}/secrets"

generate_hex_32() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 32 | tr -d '\r\n'
  else
    od -An -tx1 -N32 /dev/urandom | tr -d ' \n'
  fi
}

create_secret_if_missing() {
  local name="$1"
  local target="${SECRETS_DIR}/${name}"

  if [[ -s "$target" ]]; then
    echo "Mantido (já existe): infra/secrets/${name}"
    return 0
  fi

  local tmp
  tmp="$(mktemp "${SECRETS_DIR}/.${name}.XXXXXX")"
  trap 'rm -f "${tmp:-}"' RETURN

  generate_hex_32 > "$tmp"
  # infra/secrets/ is 700 (owner-only on the host); files are 444 (read-only) so the
  # non-root chiseled API container (UID 1654) can read bind-mounted Docker secrets.
  chmod 444 "$tmp"
  mv -n "$tmp" "$target"
  trap - RETURN

  echo "Gerado: infra/secrets/${name}"
}

mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

create_secret_if_missing "postgres_password.txt"
create_secret_if_missing "master_key.txt"

echo "Pronto. Guarde uma cópia segura de infra/secrets/master_key.txt fora da máquina (veja infra/BACKUP.md)."
