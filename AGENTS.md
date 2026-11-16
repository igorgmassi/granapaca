# Instruções para agentes de IA

Vale para qualquer assistente de código que trabalhe neste repositório: Claude Code, Codex, Cursor, Gemini e afins. O [CONTRIBUTING](CONTRIBUTING.md) traz as mesmas regras para pessoas.

## O projeto

O GranaPaCá é um app de finanças pessoais open source (AGPL-3.0), self-hosted e somente leitura. Ele junta as contas de vários bancos via Open Finance (Pluggy). Cada pessoa roda a própria instância, e os dados não saem de lá.

| Pasta | O que tem |
|---|---|
| `app/` | App Flutter (Android, iOS, Windows, macOS, Linux e demo web) |
| `backend/` | API em .NET 10 + ASP.NET Core, monólito modular, Dapper + DbUp, PostgreSQL 18 |
| `infra/` | `docker compose` da instância |
| `docs/adr/` | Decisões de arquitetura, uma por arquivo |
| `docs/design/` | Identidade visual e telas. Enquanto o PR #6 estiver aberto, o design vive na branch `docs/design-system` |

## Regras que não se negociam

- **Nada de dado real.** Nenhum extrato, CPF, número de conta, nome de terceiro, token ou credencial em código, teste, print, issue ou PR. Use sempre dados fictícios. O gitleaks roda em todo PR.
- **Idioma:**
  - Em inglês: código, nomes de tabela, rotas e mensagens de commit.
  - Em português do Brasil: documentação, ADRs e textos da interface.
- **Commits** no padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/), por exemplo `feat(app): ...` ou `docs(design): ...`. O título do PR segue o mesmo padrão, e o CI confere.
- **Sem assinatura de IA.** Nenhum `Co-Authored-By` de assistente, nenhum "Generated with ..." e nenhuma menção ao assistente em commits, PRs, issues ou comentários de código.
- **Tudo por PR.** A `main` é protegida: só aceita PR com os checks verdes, e o merge é por squash. Nunca faça push direto nem force push na `main`.
- **Decisão de arquitetura vira ADR** em `docs/adr/`, a partir do modelo `0000-template.md`.

## Antes de abrir o PR

| Mudou | Rode |
|---|---|
| `app/` | `flutter pub get --enforce-lockfile`, `flutter analyze --fatal-infos` e `flutter test`, dentro de `app/` |
| `backend/` | `dotnet restore --locked-mode`, `dotnet build` e `dotnet test`, dentro de `backend/` |
| `docs/design/` | o gerador da parte que mudou (cada arquivo da parte diz qual) e `node docs/design/tokens/check-contrast.mjs` |

## Design

Antes de mexer em design, leia `docs/design/README.md` e `DESIGN.md` na branch `docs/design-system`. Lá estão:

- o briefing de partida e as partes já prontas;
- quem cuida de cada parte;
- como mandar uma contribuição sem pisar no trabalho de outra pessoa.
