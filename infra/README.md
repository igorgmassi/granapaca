# infra

Tudo para rodar a sua instância com um único `docker compose up`: API em .NET 10 + PostgreSQL 18, com segredos em Docker secrets, volume para anexos cifrados e scripts de backup cifrado fora da máquina.

## Subir

Precisa só do Docker com o Compose v2, em amd64 ou arm64.

```bash
cd infra
./init-secrets.sh
cp .env.example .env
docker compose up --build --detach --wait
```

Conferir se subiu:

```bash
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/api/v1/server-info
```

A API valida os segredos e aplica as migrações pendentes antes de atender. O `/health` responde `Healthy` quando ela e o banco estão no ar.

Se `PLUGGY_CLIENT_ID` e `PLUGGY_CLIENT_SECRET` ficarem vazios no `.env`, a instância sobe automaticamente em modo **Sintético** (`"providerMode": "synthetic"` em `/api/v1/server-info`), útil para testar sem conectar bancos reais.

## Segurança na subida

- **Docker secrets:** `postgres_password` e `master_key` são gerados por `./init-secrets.sh` em `infra/secrets/` (pasta `0700`, ignorada pelo Git) e montados em `/run/secrets/`. Nenhuma senha entra em variáveis de ambiente nem vaza no `docker inspect`.
- **Recusa de configuração fraca:** a API recusa subir sem a chave mestra (`GRANAPACA_MASTER_KEY_FILE`) ou com senha fraca do banco.
- **Portas:** a API escuta só em `127.0.0.1:8080`, e o banco não publica porta nenhuma. Para acessar de outro aparelho, use rede privada (Tailscale), nunca abra a porta para a internet.
- **Imagem:** `backend/Dockerfile` gera a API numa imagem chiseled, sem shell e sem root ([ADR-010](../docs/adr/0010-runtime-em-imagem-chiseled.md)), e os contêineres sobem com `no-new-privileges:true`.

## O que fica onde

- **Banco:** volume `granapaca_pgdata` (`/var/lib/postgresql`).
- **Arquivos/anexos cifrados:** volume `granapaca_appdata` (`/var/lib/granapaca/files`).
- **Segredos locais:** `infra/secrets/postgres_password.txt` e `infra/secrets/master_key.txt`. Guarde uma cópia de `master_key.txt` fora da máquina; sem ela, segredos TOTP e payloads brutos cifrados não podem ser decifrados ([ADR-016](../docs/adr/0016-criptografia-de-campo-com-envelope.md)).
- `docker compose down` mantém os volumes; `docker compose down --volumes` apaga tudo.

## Backup e restauração

Veja o guia completo em [BACKUP.md](BACKUP.md) para configurar o backup diário cifrado com `restic` fora da máquina e testar a restauração em máquina nova (RF-65, ADR-029).

## Atualizar

```bash
git pull
docker compose up --build --detach --wait
```

As migrações novas rodam na subida, e os volumes e segredos continuam os mesmos.
