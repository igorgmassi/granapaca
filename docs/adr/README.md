# Decisões de arquitetura (ADRs)

Cada decisão relevante vira um ADR curto: contexto, decisão, alternativas e consequências. Use o [modelo](0000-template.md) e nunca reescreva um ADR aceito: crie outro que o substitua.

Status possíveis: A escrever, Proposto, Aceito, Rejeitado e Substituído.

| ADR | Decisão | Status |
|---|---|---|
| [ADR-001](0001-dotnet-10-e-aspnet-core.md) | .NET 10 (LTS) + ASP.NET Core no backend | Aceito |
| [ADR-002](0002-monolito-modular.md) | Monólito modular em .NET, com um projeto por módulo e testes de arquitetura; microsserviços fora | Aceito |
| ADR-003 | BankProvider: Pluggy (real e Sandbox), Arquivo OFX/CSV e Sintético | A escrever |
| ADR-004 | Cliente da Pluggy como HttpClient tipado, sem o SDK oficial | A escrever |
| ADR-005 | Jobs persistidos no Postgres: Hangfire × Quartz.NET | A escrever |
| ADR-006 | Stack do app: Riverpod 3 × Bloc 9, go_router, fl_chart e mapa de calor próprio | A escrever |
| ADR-007 | Offline-first com drift + SQLCipher e sincronização por cursor | A escrever |
| ADR-008 | Modo demo sem backend, com o mesmo dataset sintético | A escrever |
| ADR-009 | Hospedagem em fases com o mesmo Compose e rede privada (Tailscale) por padrão | A escrever |
| [ADR-010](0010-runtime-em-imagem-chiseled.md) | Runtime padrão em imagem chiseled × Native AOT | Aceito |
| ADR-011 | Alertas: caixa de entrada no app (MVP) e push via ntfy (v1) | A escrever |
| [ADR-012](0012-dado-do-provedor-append-only-e-camada-de-ajustes.md) | Dado do provedor append-only e versionado + camada de ajustes | Aceito |
| [ADR-013](0013-dinheiro-em-centavos.md) | Dinheiro em centavos (BIGINT) | Aceito |
| [ADR-014](0014-entrada-simples-com-tipos-de-movimento.md) | Entrada simples com tipos de movimento × partidas dobradas | Aceito |
| [ADR-015](0015-tempo-e-competencia.md) | Tempo: UTC + America/Sao_Paulo; competência × caixa | Aceito |
| [ADR-016](0016-criptografia-de-campo-com-envelope.md) | Criptografia de campo com envelope (AES-GCM do .NET) e master key fora do banco | Aceito |
| [ADR-017](0017-persistencia-dapper-e-dbup.md) | Persistência: Dapper + DbUp (SQL-first) × EF Core, schema por módulo e UUIDv7 | Aceito |
| ADR-018 | REST + OpenAPI 3.1 com cliente Dart gerado e SSE no chat | A escrever |
| ADR-019 | Tokens opacos com refresh rotativo e detecção de reuso | A escrever |
| ADR-020 | Microsoft.Extensions.AI × Semantic Kernel | A escrever |
| ADR-021 | Categorização em camadas com motor de regras único e cache por estabelecimento | A escrever |
| ADR-022 | NFC-e: parser por estado (ES primeiro) com fallback de visão por IA | A escrever |
| ADR-023 | Minimização e pseudonimização antes de qualquer provedor de IA | A escrever |
| ADR-024 | 2FA com TOTP; passkeys adiadas | A escrever |
| ADR-025 | Comprovantes em volume local cifrado por arquivo; MinIO fora | A escrever |
| [ADR-026](0026-licenca-agpl-3.0.md) | Licença AGPL-3.0 | Aceito |
| [ADR-027](0027-monorepo.md) | Monorepo | Aceito |
| ADR-028 | Releases multi-arch assinadas, com SBOM e release-please | A escrever |
| ADR-029 | Backup cifrado com restic fora da Oracle, com restauração testada | A escrever |
