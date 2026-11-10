# ADR-027: Monorepo

- **Status:** Aceito
- **Data:** 2026-11-09

## Contexto

O projeto tem app Flutter, backend ASP.NET Core, perfis em YAML, infraestrutura e documentação, mantidos por uma pessoa com cerca de 10 horas por semana. O app consome um cliente gerado do contrato OpenAPI do backend, e os perfis são lidos pelo backend e validados no CI.

## Decisão

Um único repositório, `granapaca`, com as pastas `app/`, `backend/`, `profiles/`, `infra/` e `docs/`.

## Alternativas consideradas

- **Um repositório por parte** (app, backend e perfis): releases independentes, mas três CIs, três listas de issues e o contrato da API sincronizado entre repositórios.

## Consequências

- Uma mudança de contrato atualiza backend, cliente Dart e app no mesmo PR.
- Issues, alertas de segurança e releases ficam num só lugar, que também é o que quem visita o portfólio encontra.
- Os workflows do CI filtram por caminho (`paths`) para não rodar tudo em toda mudança.
- Commits seguem Conventional Commits com o escopo da pasta ou do módulo, em branches curtas a partir da `main` (detalhes no guia de contribuição).
