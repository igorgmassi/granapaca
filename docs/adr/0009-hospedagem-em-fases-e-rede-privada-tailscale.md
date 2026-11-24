# ADR-009: Hospedagem em fases e rede privada com Tailscale

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O GranaPaCá é self-hosted e single-tenant: cada pessoa roda a própria instância com os próprios dados financeiros (RF-64). A jornada típica passa por fases distintas — começar no computador pessoal, migrar para um mini-PC/Raspberry Pi (arm64) em casa ou mover para uma VM na nuvem (amd64 ou arm64) — e não deveria exigir reaprender a pilha a cada mudança. Além disso, expor uma API financeira diretamente na internet pública amplia desnecessariamente a superfície de ataque.

## Decisão

Padronizar todas as fases de hospedagem sobre o **mesmo `infra/compose.yaml`** (multi-arch `amd64`/`arm64`), com **acesso privado por Tailscale como padrão** e proxy reverso público **apenas como extensão opcional**:

- **Padrão fechado em `infra/compose.yaml`:** a API escuta exclusivamente em `127.0.0.1:8080`, o PostgreSQL não publica porta nenhuma no host e os segredos entram via Docker secrets (`infra/secrets/`). O mesmo arquivo sobe localmente, em servidor doméstico ou em VM na nuvem.
- **Rede privada com Tailscale por padrão:** o acesso remoto a partir do celular e de outros computadores é feito via `tailscale serve --bg http://127.0.0.1:8080` (documentado em `infra/TAILSCALE.md`), entregando túnel WireGuard autenticado e HTTPS automático (`*.ts.net`) sem abrir nenhuma porta no roteador ou firewall.
- **Caddy opcional via Compose override:** para quem precisa de domínio público próprio, `infra/compose.caddy.yaml` + `infra/caddy/Caddyfile` acrescentam o proxy reverso `caddy:2-alpine` com TLS automático (Let's Encrypt), cabeçalhos restritivos de segurança (`HSTS`, `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, remoção de `Server`) e limite de payload de `10MB`, acionado explicitamente com `docker compose -f compose.yaml -f compose.caddy.yaml up -d`.

## Alternativas consideradas

- **Incluir Caddy e portas 80/443 abertas no `compose.yaml` padrão:** obrigaria quem quer rodar só localmente ou na rede privada a configurar DNS público e exporia a instância à internet por padrão.
- **Manter manifests separados para local, Raspberry Pi e Kubernetes:** multiplica manutenção, diverge rapidamente e dificulta migrar a instância entre máquinas.
- **Adotar Cloudflare Tunnel como padrão:** facilita acesso sem abrir portas, mas termina o TLS em um intermediário de terceiros capaz de inspecionar o tráfego financeiro em claro.

## Consequências

- Migrar a instância de um computador local para um servidor caseiro ou VM resume-se a copiar `infra/`, manter a `master_key` e restaurar o backup do `restic` (ADR-029).
- Nenhuma porta pública precisa ser aberta na configuração padrão, e o tráfego na tailnet permanece criptografado ponta a ponta sem intermediário de terminação TLS.
- Quem optar por domínio público com `compose.caddy.yaml` assume explicitamente o firewall restrito (somente 80/443) e a obrigatoriedade do 2FA TOTP (ADR-024).
