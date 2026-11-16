# infra

Tudo para rodar a sua instância com um único `docker compose up`. Hoje sobe a API e o PostgreSQL 18. Acesso pela rede privada (Tailscale), Caddy opcional e os guias de atualização e backup entram depois.

## Subir

Precisa só do Docker com o Compose v2, em amd64 ou arm64.

```bash
cd infra
cp .env.example .env
```

No `.env`, preencha `POSTGRES_PASSWORD` com uma senha gerada (`openssl rand -hex 32`). Sem ela, o compose não sobe. As chaves vazias usam os padrões dos comentários.

```bash
docker compose up --build --detach --wait
curl http://127.0.0.1:8080/health
```

A API aplica as migrações pendentes antes de atender, e o `/health` responde `Healthy` quando ela e o banco estão no ar.

## O que fica onde

- **Portas:** a API escuta só em `127.0.0.1:8080`, e o banco não publica porta nenhuma. Nada fica exposto na rede.
- **Dados:** o banco fica no volume `granapaca_pgdata`. `docker compose down` mantém os dados; `docker compose down --volumes` apaga tudo.
- **Imagem:** `backend/Dockerfile` gera a API numa imagem chiseled, sem shell e sem root ([ADR-010](../docs/adr/0010-runtime-em-imagem-chiseled.md)).

## Atualizar

```bash
git pull
docker compose up --build --detach --wait
```

As migrações novas rodam na subida, e o volume continua o mesmo.
