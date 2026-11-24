# ADR-018: API REST e OpenAPI 3.1

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O backend em .NET 10 + ASP.NET Core (ADR-001) atende o app Flutter multiplataforma e precisa de um contrato HTTP claro, versionado e fácil de inspecionar, depurar e testar de ponta a ponta. Também precisamos de uma especificação legível por máquina para detectar quebras de contrato e, quando o volume de endpoints crescer, gerar ou validar modelos do cliente Dart sem duplicação manual, além de suportar respostas em streaming no futuro chat com IA.

## Decisão

Adotar **REST sobre HTTP/JSON** sob o prefixo `/api/v1/*`, com especificação **OpenAPI 3.1** gerada diretamente pelo ASP.NET Core:

- **Endpoints versionados por rota:** cada módulo do monólito (ADR-002) registra suas Minimal APIs em `/api/v1/*` (como `/api/v1/server-info`, `/api/v1/auth/*`, `/api/v1/banking/*`, `/api/v1/sync/changes`), devolvendo JSON em `camelCase` e erros estruturados em `ProblemDetails` (RFC 9457).
- **OpenAPI 3.1 nativo:** o host gera a especificação OpenAPI 3.1 usando o suporte nativo do ASP.NET Core (`Microsoft.AspNetCore.OpenApi`) publicada em `/openapi/v1.json`, sem bibliotecas externas de geração de schema.
- **Evolução para cliente gerado e SSE:** `/openapi/v1.json` funciona como contrato único de referência para geração futura do cliente Dart tipado, e o streaming de respostas do chat com IA usará Server-Sent Events (SSE) sobre o mesmo protocolo HTTP/REST.

## Alternativas consideradas

- **gRPC:** oferece serialização compacta e contratos `.proto`, mas exige suporte a HTTP/2 ponta a ponta (mais frágil em proxies e Flutter Web) e dificulta inspeção rápida com `curl` em instâncias self-hosted.
- **GraphQL:** traz complexidade de schema, autorização por campo, proteção contra consultas aninhadas e cache HTTP para um sistema com apenas um cliente oficial.
- **Swashbuckle / NSwag:** adicionam dependências de terceiros que ficam redundantes frente ao gerador OpenAPI 3.1 embutido no .NET 10.

## Consequências

- Qualquer pessoa consegue verificar e depurar a própria instância com ferramentas simples como `curl` e `jq`, além de testes de integração leves com `WebApplicationFactory`.
- Mudanças no contrato HTTP ficam visíveis no documento `/openapi/v1.json`, facilitando revisão de compatibilidade antes de quebrar clientes mais antigos.
- Todo novo endpoint deve declarar explicitamente seus tipos de entrada, saída e códigos de erro para manter o OpenAPI 3.1 completo e fiel à implementação.
