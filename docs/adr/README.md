# Decisões de arquitetura (ADRs)

Cada decisão relevante vira um ADR curto: contexto, decisão, alternativas e consequências. Use o [modelo](0000-template.md) e nunca reescreva um ADR aceito: crie outro que o substitua.

Status possíveis: A escrever, Proposto, Aceito, Rejeitado e Substituído.

| ADR | Decisão | Status |
|---|---|---|
| [ADR-001](0001-dotnet-10-e-aspnet-core.md) | .NET 10 (LTS) + ASP.NET Core no backend | Aceito |
| [ADR-002](0002-monolito-modular.md) | Monólito modular em .NET, com um projeto por módulo e testes de arquitetura; microsserviços fora | Aceito |
| [ADR-003](0003-bank-provider-pluggy-arquivo-e-sintetico.md) | BankProvider: Pluggy (real e Sandbox), Arquivo OFX/CSV e Sintético | Aceito |
| [ADR-004](0004-cliente-pluggy-httpclient-tipado.md) | Cliente da Pluggy como HttpClient tipado, sem o SDK oficial | Aceito |
| [ADR-005](0005-jobs-em-segundo-plano.md) | Jobs em segundo plano com BackgroundService nativo no MVP; Hangfire e Quartz.NET adiados | Aceito |
| [ADR-006](0006-stack-do-app-flutter.md) | Stack do app Flutter: Material 3 (`material_ui`), `ChangeNotifier`/`InheritedNotifier`, gráficos `CustomPaint` e mapa de calor próprio | Aceito |
| [ADR-007](0007-offline-first-e-sincronizacao-por-cursor.md) | Offline-first com cache local cifrado e sincronização incremental por cursor | Aceito |
| [ADR-008](0008-modo-demo-sem-backend.md) | Modo demo sem backend, com o mesmo dataset sintético | Aceito |
| [ADR-009](0009-hospedagem-em-fases-e-rede-privada-tailscale.md) | Hospedagem em fases com o mesmo Compose, rede privada (Tailscale) por padrão e Caddy opcional | Aceito |
| [ADR-010](0010-runtime-em-imagem-chiseled.md) | Runtime padrão em imagem chiseled × Native AOT | Aceito |
| [ADR-011](0011-alertas-caixa-de-entrada.md) | Alertas: caixa de entrada no app (MVP) e push via ntfy (v1) | Aceito |
| [ADR-012](0012-dado-do-provedor-append-only-e-camada-de-ajustes.md) | Dado do provedor append-only e versionado + camada de ajustes | Aceito |
| [ADR-013](0013-dinheiro-em-centavos.md) | Dinheiro em centavos (BIGINT) | Aceito |
| [ADR-014](0014-entrada-simples-com-tipos-de-movimento.md) | Entrada simples com tipos de movimento × partidas dobradas | Aceito |
| [ADR-015](0015-tempo-e-competencia.md) | Tempo: UTC + America/Sao_Paulo; competência × caixa | Aceito |
| [ADR-016](0016-criptografia-de-campo-com-envelope.md) | Criptografia de campo com envelope (AES-GCM do .NET) e master key fora do banco | Aceito |
| [ADR-017](0017-persistencia-dapper-e-dbup.md) | Persistência: Dapper + DbUp (SQL-first) × EF Core, schema por módulo e UUIDv7 | Aceito |
| [ADR-018](0018-rest-e-openapi-3-1.md) | API REST (`/api/v1/*`) com OpenAPI 3.1 nativo do ASP.NET Core e SSE no chat | Aceito |
| [ADR-019](0019-tokens-opacos-e-refresh-rotativo.md) | Tokens opacos com refresh rotativo e detecção de reuso | Aceito |
| [ADR-020](0020-integracao-com-provedores-de-ia.md) | Integração com provedores de IA via HttpClient tipado (caminho aberto para Microsoft.Extensions.AI); Semantic Kernel fora | Aceito |
| [ADR-021](0021-categorizacao-em-camadas-por-regras.md) | Categorização em camadas com motor de regras único e cache por estabelecimento | Aceito |
| [ADR-022](0022-nfce-parser-por-estado-e-fallback-ia.md) | NFC-e: parser determinístico (XML SEFAZ 4.00 e QR por estado, ES primeiro) com fallback opcional de visão por IA | Aceito |
| [ADR-023](0023-minimizacao-e-pseudonimizacao-ia.md) | Minimização e pseudonimização reversível antes de qualquer chamada a provedor de IA | Aceito |
| [ADR-024](0024-2fa-com-totp.md) | 2FA com TOTP; passkeys adiadas | Aceito |
| [ADR-025](0025-comprovantes-em-volume-local-cifrado.md) | Comprovantes no volume local `appdata` cifrados por arquivo (AES-256-GCM via Keyring); MinIO fora | Aceito |
| [ADR-026](0026-licenca-agpl-3.0.md) | Licença AGPL-3.0 | Aceito |
| [ADR-027](0027-monorepo.md) | Monorepo | Aceito |
| [ADR-028](0028-releases-multi-arch-sbom-e-assinatura.md) | Releases multi-arch (`amd64`/`arm64`) no GHCR com SBOM SPDX e assinatura keyless via Cosign/Sigstore | Aceito |
| [ADR-029](0029-backup-cifrado-com-restic.md) | Backup diário cifrado fora da máquina com restic, separação da master key e restauração testada | Aceito |
| [ADR-030](0030-modo-local-no-aparelho-e-ia-gratuita.md) | Modo local no aparelho ("Só neste aparelho") e IA gratuita por padrão (Paçoca determinística, presets gratuitos e Ollama) | Aceito |
