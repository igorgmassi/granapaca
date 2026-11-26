# ADR-004: Cliente da Pluggy como HttpClient tipado, sem o SDK oficial

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O módulo `Banking` fala com a API REST da Pluggy para autenticar com `clientId`/`clientSecret`, listar itens do Meu Pluggy, acompanhar o vencimento do consentimento (RF-14) e sincronizar contas, transações e faturas paginadas (RF-12, RF-13). Precisamos de leitura monetária exata em `decimal` (ADR-013), captura do JSON bruto para cifragem em envelope (ADR-012, ADR-016), retentativas com espera crescente em falhas transitórias e logs sem dados pessoais ou segredos (RF-13, RNF-06).

## Decisão

Implementar um cliente próprio (`PluggyClient`) como `HttpClient` tipado registrado via `IHttpClientFactory` dentro de `GranaPaCa.Modules.Banking`, sem instalar pacote SDK da Pluggy:

- **Autenticação:** troca `clientId`/`clientSecret` em `POST /auth` por `X-API-KEY` temporária, mantida em cache em memória e renovada antes de vencer.
- **Serialização e payload bruto:** usa `System.Text.Json` com DTOs mínimos só dos campos consumidos, lendo valores como `decimal` e preservando o JSON bruto de cada transação/fatura para gravar cifrado em `banking.transaction_version`.
- **Resiliência:** usa `Microsoft.Extensions.Http.Resilience` (timeouts curtos e backoff exponencial com jitter para 429 e 5xx).
- **Segurança nos logs:** nunca registra `clientSecret`, `X-API-KEY`, cabeçalhos de autenticação nem descrições/nomes do extrato em logs de erro.

## Alternativas consideradas

- **SDK oficial/comunitário da Pluggy no NuGet:** pouco acompanhado frente ao .NET 10, puxa dependências transitivas próprias, costuma desserializar valores em `double` e esconde o acesso ao JSON bruto necessário para a trilha append-only.
- **Gerar cliente automático via OpenAPI (Kiota ou NSwag):** produz centenas de tipos para endpoints que o GranaPaCá não usa e quebra com pequenas divergências da especificação da Pluggy.

## Consequências

- Superfície mínima de dependências, licença limpa compatível com AGPL-3.0 (ADR-001) e controle total sobre paginação, timeouts e novos campos da Pluggy (como `consentExpiresAt` e `USER_AUTHORIZATION_EXPIRED`).
- Testes de contrato rodam rápido e determinísticos com `HttpMessageHandler` falso e fixtures sintéticas, sem tocar a rede.
- O custo é atualizar manualmente os poucos DTOs e endpoints quando a API da Pluggy evoluir.
