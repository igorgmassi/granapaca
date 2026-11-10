# backend

API e jobs do GranaPaCá em .NET 10 (LTS) e ASP.NET Core, como monólito modular, com PostgreSQL, Dapper e DbUp. Só o backend fala com a Pluggy e com os provedores de IA, então segredos nunca chegam ao app.

## Estrutura

| Caminho | O que tem |
|---|---|
| `src/GranaPaCa.Api` | Host: configuração, health check e migrações na subida |
| `src/GranaPaCa.Modules.Sample` | Módulo de exemplo e molde dos próximos: schema `sample`, script SQL embutido e um endpoint com Dapper |
| `tests/GranaPaCa.Tests` | Testes com PostgreSQL real (Testcontainers) e teste de arquitetura (ArchUnitNET) |

As decisões estão nos ADRs [001](../docs/adr/0001-dotnet-10-e-aspnet-core.md), [002](../docs/adr/0002-monolito-modular.md) e [017](../docs/adr/0017-persistencia-dapper-e-dbup.md).

## Como rodar

Precisa do SDK do .NET fixado em [`global.json`](global.json) e, para os testes de integração, de Docker.

```bash
dotnet build
dotnet test
```

A API precisa de um PostgreSQL. Ela aplica as migrações pendentes antes de atender e responde em `GET /health`:

```bash
ConnectionStrings__Postgres="Host=localhost;Database=granapaca;Username=granapaca;Password=<senha>" dotnet run --project src/GranaPaCa.Api
```

## Regras

- Cada módulo é um projeto `GranaPaCa.Modules.<Nome>`, com schema próprio e scripts em `Migrations/NNNN_descricao.sql`.
- Fora do próprio projeto, um módulo só é usado pela classe `<Nome>Module` e pelo namespace `Contracts`. O teste de arquitetura barra o resto.
- Um script aplicado nunca muda: a correção vira um script novo.
- Dependência nova entra em `Directory.Packages.props`, com licença compatível com a AGPL-3.0, e os `packages.lock.json` vão no mesmo commit.
