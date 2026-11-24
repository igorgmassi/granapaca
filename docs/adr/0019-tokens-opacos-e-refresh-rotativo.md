# ADR-019: Tokens opacos com refresh rotativo e detecção de reuso

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Cada instância atende o dono em mais de um aparelho (celular e desktop) com sessões de longa duração. Ao escolher "Sair", a sessão daquele aparelho precisa morrer imediatamente no servidor (RF-03). Se um token de atualização for copiado ou roubado, o servidor precisa detectar o abuso e cortar o acesso sem esperar a expiração natural (RNF-02, RNF-03).

## Decisão

Adotar tokens opacos de alta entropia gerenciados pelo módulo `GranaPaCa.Modules.Identity` (schema `identity`):

- **Formato e armazenamento:** access token e refresh token são gerados com 32 bytes aleatórios via `RandomNumberGenerator` (Base64URL). O banco armazena apenas o hash SHA-256 de cada token (ADR-016), nunca o valor em claro, vinculado ao aparelho (`device_name`) e a uma família (`token_family_id`).
- **Curta duração + rotação:** access token expira em minutos (15 min) e refresh token em dias (30 dias). Cada renovação invalida o refresh token usado e emite um par novo na mesma família.
- **Detecção de reuso:** reapresentar um refresh token já rotacionado ou revogado aciona a revogação imediata de toda a família de sessões e registra evento de auditoria.
- **Contrato entre módulos:** a API autentica requisições Bearer via `IAuthTokenValidator`, que devolve `AuthenticatedSession` (`OwnerId`, `HouseholdId`, `SessionId`, `DeviceName`).

## Alternativas consideradas

- **JWT stateless:** não permite revogar sessões no ato ao sair ou em comprometimento sem manter uma lista de revogação no banco, anulando a vantagem de ser stateless e ainda expondo claims no cliente.
- **Cookies de sessão do ASP.NET Core:** funcionam bem em navegadores, mas complicam o cliente Flutter em Android, iOS e desktop frente ao cabeçalho `Authorization: Bearer`.

## Consequências

- "Sair" em um aparelho ou revogar sessões suspeitas surte efeito na requisição seguinte.
- Um dump vazado do banco não permite sequestrar sessões ativas, pois só contém hashes.
- Toda requisição autenticada faz uma leitura indexada por hash no PostgreSQL — latência mínima numa instância single-tenant, facilmente absorvida pelo pool de conexões.
