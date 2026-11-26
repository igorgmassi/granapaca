# backend

API e jobs do GranaPaCá em .NET 10 (LTS) e ASP.NET Core, como monólito modular, com PostgreSQL 18, Dapper e DbUp. Só o backend fala com a Pluggy e com os provedores de IA, então segredos nunca chegam ao app.

## Estrutura

| Caminho | O que tem |
|---|---|
| `src/GranaPaCa.Api` | Host: configuração, validação de senha/segredos, autenticação por bearer opaco, OpenAPI 3.1, apagamento completo (`RF-07`), health check e migrações na subida |
| `src/GranaPaCa.Modules.Keyring` | Criptografia de campo em envelope AES-256-GCM e gestão de DEKs (schema `keyring`, ADR-016) |
| `src/GranaPaCa.Modules.Identity` | Setup do dono, login com Argon2id, 2FA TOTP, códigos de recuperação e sessões com refresh rotativo (schema `identity`, ADR-019, ADR-024) |
| `src/GranaPaCa.Modules.Banking` | Ledger *append-only* versionado, dinheiro físico, formas de pagamento, tags, divisões exatas, ajustes/desfazer, lote, transferências, cartões/faturas, `Synthetic`/`Pluggy`/OFX/CSV, sync por cursor e exportação CSV/JSON/HTML (schema `banking`, ADR-003, ADR-004, ADR-007, ADR-012..015) |
| `src/GranaPaCa.Modules.Categorization` | Motor determinístico em camadas (usuário > perfil > sistema), perfis YAML e fila de revisão (schema `categorization`, ADR-021) |
| `src/GranaPaCa.Modules.Alerts` | Caixa de entrada deduplicada de alertas com fechamento automático (schema `alerts`, ADR-011) |
| `src/GranaPaCa.Modules.Planning` | Orçamentos, metas, regra 50/30/20, projeção sem atípicas, comparação mês a mês, mapa de calor, detector de assinaturas e alertas personalizados (schema `planning`) |
| `src/GranaPaCa.Modules.Receipts` | Comprovantes cifrados em volume local (AES-256-GCM) e parser de NFC-e (SEFAZ-ES / 4.00) virando divisões da transação (schema `receipts`, ADR-022, ADR-025) |
| `src/GranaPaCa.Modules.Assistant` | Chat somente leitura com SSE, minimização/pseudonimização de PII, BYOK cifrado (OpenAI, Anthropic, Google, Ollama) e sugestões de categorização com confirmação (schema `assistant`, ADR-018, ADR-020, ADR-023) |
| `tests/GranaPaCa.Tests` | Testes de integração contra PostgreSQL 18 real (Testcontainers), testes de fronteira nos 8 módulos (ArchUnitNET) e verificação RNF-06 |

As decisões estão nos 29 ADRs em [`docs/adr`](../docs/adr/README.md).

## Como rodar

Precisa do SDK do .NET fixado em [`global.json`](global.json) e, para os testes de integração, de Docker.

```bash
dotnet restore --locked-mode
dotnet build --no-restore
dotnet test --no-build
```

Para subir a instância completa com PostgreSQL 18 e Docker secrets, veja [`infra/README.md`](../infra/README.md).

## Regras

- Cada módulo é um projeto `GranaPaCa.Modules.<Nome>`, com schema próprio e scripts em `Migrations/NNNN_descricao.sql`.
- Fora do próprio projeto, um módulo só é usado pela classe `<Nome>Module` e pelo namespace `Contracts`. O teste de arquitetura barra o resto.
- Um script aplicado nunca muda, nem o conteúdo nem o nome: a correção vira um script novo. O DbUp identifica cada script pelo nome completo do recurso (namespace do projeto, pasta `Migrations` e arquivo), e um nome novo roda de novo nas instâncias existentes.
- Todo script novo entra na lista `AppliedMigrations` de [`ApiTests`](tests/GranaPaCa.Tests/ApiTests.cs). O teste falha quando o journal do DbUp diverge dela.
- Dependência nova entra em `Directory.Packages.props`, com licença compatível com a AGPL-3.0, e os `packages.lock.json` vão no mesmo commit.
