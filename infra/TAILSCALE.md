# Acesso privado com Tailscale (recomendado) e proxy reverso opcional com Caddy

Por padrão, o `infra/compose.yaml` publica a API do GranaPaCá **somente em `127.0.0.1:8080`** e não abre nenhuma porta do PostgreSQL (ADR-009). A forma recomendada de acessar a sua instância do celular ou de outro computador é pela rede privada do **Tailscale**, sem abrir portas para a internet.

## 1. Acesso privado via Tailscale (padrão recomendado)

Com o Tailscale, o tráfego entre o app e a sua instância passa por um túnel WireGuard criptografado ponta a ponta, acessível apenas pelos dispositivos autenticados na sua *tailnet*, e o próprio Tailscale emite certificado HTTPS válido para um endereço `*.ts.net`.

### Pré-requisitos

- A instância já está rodando localmente e saudável (`curl http://127.0.0.1:8080/health` responde `Healthy`, conforme [infra/README.md](README.md)).
- O Tailscale está instalado e conectado na máquina onde o Docker roda e nos aparelhos onde você usa o app GranaPaCá (Android, iOS, Windows, macOS ou Linux).
- No painel administrativo do Tailscale (**DNS**), habilite **MagicDNS** e **HTTPS Certificates**.

### Publicar a API somente na sua tailnet

Na máquina onde o GranaPaCá está rodando, execute:

```bash
tailscale serve --bg http://127.0.0.1:8080
```

O comando `tailscale serve` cria um proxy HTTPS automático na porta `443` **apenas dentro da sua tailnet**, encaminhando as requisições para `http://127.0.0.1:8080` na própria máquina, sem abrir nenhuma porta no roteador ou no firewall da nuvem.

> **Importante:** nunca use `tailscale funnel` para o GranaPaCá, pois o Funnel expõe o serviço para a internet pública.

### Conferir se funcionou

Verifique o endereço HTTPS gerado:

```bash
tailscale serve status
```

A partir de outro aparelho conectado à mesma tailnet (substitua pelo nome da sua máquina e da sua tailnet):

```bash
curl --fail https://servidor-casa.tailnet-exemplo.ts.net/health
curl --fail https://servidor-casa.tailnet-exemplo.ts.net/api/v1/server-info
```

Para interromper a exposição na tailnet quando quiser:

```bash
tailscale serve --bg off
```

### Boas práticas na tailnet

- Restrinja o acesso à porta `443` da máquina da instância via ACLs/Grants do Tailscale apenas aos seus próprios dispositivos.
- Mantenha a porta `8080` vinculada exclusivamente a `127.0.0.1` no `compose.yaml`.
- Nunca exponha o PostgreSQL (`5432`) fora da rede interna do Docker Compose.

## 2. Apontando o app GranaPaCá para a sua instância (RF-01)

1. Conecte o celular ou computador à mesma tailnet no app do Tailscale.
2. Abra o app do GranaPaCá e acesse a tela de conexão com a instância (na primeira abertura ou em **Configurações -> Instância**).
3. Informe o endereço HTTPS do Tailscale, sem barra final:
   ```text
   https://servidor-casa.tailnet-exemplo.ts.net
   ```
4. O app valida a conexão consultando `/api/v1/server-info` (verificando versão e modo ativo, `pluggy` ou `synthetic`) e segue para o login com senha e segundo fator TOTP (`RF-02`, `RF-03`).

> **Nota sobre HTTPS:** o app só aceita HTTP sem TLS para endereços locais (`localhost` / `127.0.0.1`). Fora da própria máquina, use sempre `https://`.

## 3. Opção avançada: domínio público com Caddy (`compose.caddy.yaml`)

Se você não puder instalar o Tailscale em algum dispositivo (por exemplo, um aparelho com restrições de VPN) e precisar acessar a instância por um domínio público próprio, use o override opcional do **Caddy** em `infra/compose.caddy.yaml` com `infra/caddy/Caddyfile`.

> **Aviso de segurança:** publicar a instância na internet aumenta significativamente a superfície de ataque. Só use esta opção se mantiver **2FA TOTP obrigatório ativo** ([ADR-024](../docs/adr/0024-2fa-com-totp.md)), senha forte única, sistema operacional e imagens Docker atualizados regularmente e backup cifrado fora da máquina ([BACKUP.md](BACKUP.md)).

### Passo a passo

1. **Configure o DNS:** crie um registro `A` (e `AAAA`, se tiver IPv6) apontando o seu subdomínio — por exemplo `financas.exemplo.com` — para o IP público da VM.
2. **Defina o domínio no `infra/.env`:**
   ```dotenv
   GRANAPACA_DOMAIN=financas.exemplo.com
   ```
3. **Ajuste o firewall** (no sistema operacional e no painel do provedor de nuvem):
   - **Permitir:** `80/tcp` (desafio ACME Let's Encrypt e redirecionamento para HTTPS), `443/tcp` (HTTPS) e `443/udp` (HTTP/3).
   - **Restringir:** SSH (`22/tcp`) apenas ao seu IP ou pela própria tailnet.
   - **Bloquear sempre:** `8080/tcp` e `5432/tcp` (nunca expor diretamente).
   Exemplo com `ufw` em Linux:
   ```bash
   sudo ufw allow 80/tcp
   sudo ufw allow 443/tcp
   sudo ufw allow 443/udp
   sudo ufw status
   ```
4. **Suba a pilha com o override do Caddy:**
   ```bash
   cd infra
   docker compose -f compose.yaml -f compose.caddy.yaml up -d
   ```

O template [`infra/caddy/Caddyfile`](caddy/Caddyfile) emite e renova o certificado TLS automaticamente via Let's Encrypt, encaminha para `api:8080` pela rede interna do Compose, aplica cabeçalhos de segurança (`Strict-Transport-Security`, `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, sem cabeçalho `Server`) e limita o tamanho do corpo da requisição a `10MB`. Os certificados ficam nos volumes persistentes `caddy_data` e `caddy_config`.

### Conferir e voltar ao modo privado

Verifique o acesso pelo domínio:

```bash
curl --fail https://financas.exemplo.com/health
```

No app GranaPaCá (`RF-01`), informe `https://financas.exemplo.com` no lugar do endereço `*.ts.net`.

Para desligar o Caddy e voltar ao modo 100% privado (`127.0.0.1:8080`):

```bash
cd infra
docker compose -f compose.yaml up -d --remove-orphans
```
