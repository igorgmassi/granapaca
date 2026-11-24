# Backup cifrado e restauração testada

Guia operacional para manter cópias diárias e cifradas do GranaPaCá fora da máquina (RF-65, RNF-24, ADR-029).

> **Atenção para quem usa Oracle Cloud Always Free:** a Oracle pode reclamar uma instância ociosa que fique 7 dias com CPU, rede e memória abaixo de 20%. Mesmo em outras nuvens ou servidor caseiro, o backup precisa ficar **fora da máquina** onde o Docker roda.

## Regra crítica: guarde as chaves fora do backup

Sem duas chaves, a restauração não completa:

1. **`RESTIC_PASSWORD_FILE`:** a senha do repositório `restic`. Sem ela, nenhum snapshot abre.
2. **`infra/secrets/master_key.txt`:** a chave mestra da criptografia de campo ([ADR-016](../docs/adr/0016-criptografia-de-campo-com-envelope.md)). Sem ela, o banco volta com as transações normalizadas, mas segredos TOTP e payloads brutos cifrados não podem ser decifrados.

**Nunca guarde `master_key.txt` nem `RESTIC_PASSWORD_FILE` dentro do mesmo bucket/repositório do backup.** Salve ambos num gerenciador de senhas (ex.: Bitwarden, KeePassXC) ou em mídia cifrada separada.

## 1. Pré-requisitos

- `restic` instalado na máquina host (`sudo apt-get install restic` ou binário oficial).
- Um destino fora da máquina compatível com `restic`:
  - Backblaze B2 (`b2:meu-bucket:granapaca`)
  - Cloudflare R2 ou S3 compatível (`s3:https://conta.r2.cloudflarestorage.com/meu-bucket/granapaca`)
  - Outro servidor via SFTP (`sftp:backup@exemplo.internal:/srv/backups/granapaca`)

## 2. Configurar e inicializar o repositório

Crie um diretório de configuração fora do repositório Git, com permissão restrita ao seu usuário:

```bash
mkdir -p ~/.config/granapaca-backup
chmod 700 ~/.config/granapaca-backup
openssl rand -hex 32 > ~/.config/granapaca-backup/restic-password
chmod 600 ~/.config/granapaca-backup/restic-password
```

Crie o arquivo de ambiente `~/.config/granapaca-backup/backup.env` (`chmod 600`) com o destino escolhido (use credenciais dedicadas somente ao bucket de backup):

```bash
# Exemplo com S3/R2 (ajuste para o seu destino):
RESTIC_REPOSITORY=s3:https://conta.r2.cloudflarestorage.com/meu-bucket/granapaca
RESTIC_PASSWORD_FILE=/home/seu-usuario/.config/granapaca-backup/restic-password
AWS_ACCESS_KEY_ID=<sua-chave-de-acesso>
AWS_SECRET_ACCESS_KEY=<seu-segredo-de-acesso>

# Opcional: arquivo de estado e webhook para alerta em caso de falha
BACKUP_STATUS_FILE=/var/tmp/granapaca-backup.status
# BACKUP_ALERT_WEBHOOK_URL=https://ntfy.sua-rede.internal/granapaca-alerts
```

Inicialize o repositório uma única vez:

```bash
set -a
source ~/.config/granapaca-backup/backup.env
set +a
restic init
```

## 3. Testar o backup manualmente

```bash
set -a
source ~/.config/granapaca-backup/backup.env
set +a
./infra/backup/backup.sh
```

O script:

1. Faz `pg_dump --format=custom --no-owner` direto para `restic backup --stdin` (nenhum arquivo `.dump` sem cifra toca o disco).
2. Envia o volume `granapaca_appdata` (anexos/arquivos cifrados) em fluxo direto para o `restic`.
3. Aplica a política de retenção padrão: **7 diários, 4 semanais e 6 mensais** (`--keep-daily 7 --keep-weekly 4 --keep-monthly 6 --prune`).
4. Roda `restic check` para validar a integridade do repositório.

## 4. Agendar backup diário

### Opção A: systemd timer (recomendado)

Crie `~/.config/systemd/user/granapaca-backup.service`:

```ini
[Unit]
Description=Backup cifrado diário do GranaPaCá
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=%h/.config/granapaca-backup/backup.env
ExecStart=/caminho/para/granapaca/infra/backup/backup.sh
```

Crie `~/.config/systemd/user/granapaca-backup.timer`:

```ini
[Unit]
Description=Agenda o backup diário do GranaPaCá

[Timer]
OnCalendar=*-*-* 03:30:00
RandomizedDelaySec=15m
Persistent=true

[Install]
WantedBy=timers.target
```

Ative o timer:

```bash
systemctl --user daemon-reload
systemctl --user enable --now granapaca-backup.timer
systemctl --user list-timers granapaca-backup.timer
```

### Opção B: cron

```cron
30 3 * * * /usr/bin/env bash -c 'set -a; source ~/.config/granapaca-backup/backup.env; set +a; /caminho/para/granapaca/infra/backup/backup.sh' >> ~/.local/state/granapaca-backup.log 2>&1
```

### Alerta em caso de falha

Quando o backup falha, `backup.sh` grava `status=failed` em `BACKUP_STATUS_FILE` (com o nome da etapa, sem credenciais nem dados pessoais) e, se `BACKUP_ALERT_WEBHOOK_URL` estiver definido, envia um aviso genérico em JSON. A instância pode ler `BACKUP_STATUS_FILE` para abrir um alerta na caixa de entrada do app (RF-56, RF-65).

## 5. Runbook de restauração em máquina nova (RNF-24)

Siga estes passos para subir a instância do zero em outra máquina e validar a recuperação:

1. **Instale as dependências** na máquina nova: Docker (Compose v2), `git` e `restic`.
2. **Clone o repositório** e crie os segredos:
   ```bash
   git clone https://github.com/igorgmassi/granapaca.git
   cd granapaca/infra
   ./init-secrets.sh
   cp .env.example .env
   ```
3. **Recoloque a chave mestra original** (recuperada do seu gerenciador de senhas):
   ```bash
   chmod 600 secrets/master_key.txt
   printf '%s' 'SUA_MASTER_KEY_HEX_ORIGINAL' > secrets/master_key.txt
   chmod 444 secrets/master_key.txt
   ```
   A senha do PostgreSQL (`secrets/postgres_password.txt`) pode ser a recém-gerada — ela só protege o banco local da nova máquina.
4. **Configure as variáveis do `restic`** (`RESTIC_REPOSITORY`, `RESTIC_PASSWORD_FILE` e credenciais do bucket) e confira os snapshots disponíveis:
   ```bash
   restic snapshots --tag granapaca
   ```
5. **Suba apenas o banco de dados** e aguarde ficar saudável:
   ```bash
   docker compose up --detach --wait db
   ```
6. **Execute a restauração** (sem argumento restaura o snapshot `latest`, ou passe um ID específico):
   ```bash
   ./backup/restore.sh
   # ou: ./backup/restore.sh <snapshot_id>
   ```
   O script restaura o dump com `pg_restore --clean --if-exists --no-owner`, restaura o volume `granapaca_appdata` (se houver snapshot `files`) e executa a consulta de verificação de tabelas e migrações `schemaversions`.
7. **Suba a API** e valide a instância:
   ```bash
   docker compose up --build --detach --wait
   curl --fail http://127.0.0.1:8080/health
   curl --fail http://127.0.0.1:8080/api/v1/server-info
   ```
8. **Confirme no app:** faça login com a sua conta e código TOTP (validando também que a `master_key` decifra o segredo TOTP corretamente) e verifique o saldo e as correções recentes.

> **Boa prática:** teste este runbook periodicamente (por exemplo, uma vez por mês) numa VM descartável ou ambiente local separado. Backup que nunca foi restaurado é suposição.
