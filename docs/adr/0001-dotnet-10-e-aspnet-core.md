# ADR-001: .NET 10 (LTS) + ASP.NET Core no backend

- **Status:** Aceito
- **Data:** 2026-11-10

## Contexto

O backend expõe a API REST para o app, vai rodar os jobs de sincronização e é a única parte que fala com o PostgreSQL, com a Pluggy e com os provedores de IA. Uma pessoa mantém o projeto, com cerca de 10 horas por semana, e cada instância roda numa VM pequena, em amd64 ou arm64.

O plano começou com Java 25, Spring Boot 4.1 e Spring Modulith. Em 10/11/2026, quem mantém o projeto trocou a stack para .NET, para concentrar o portfólio e a prática numa plataforma só.

O projeto é AGPL-3.0 (ADR-026), então cada dependência precisa de licença compatível. Em 2025 e 2026, alguns pacotes populares do .NET passaram a ter licença comercial ou restrita.

## Decisão

O backend usa .NET 10 (LTS, com suporte até 14/11/2028), ASP.NET Core e C#. O SDK fica fixado em `backend/global.json` (`10.0.402`, com `rollForward: latestPatch`), e os pacotes têm versão central em `Directory.Packages.props`, com lock files do NuGet.

## Alternativas consideradas

- **Java 25 + Spring Boot 4.1 + Spring Modulith:** a premissa original, madura e com verificação de módulos pronta. Saiu para alinhar o projeto à stack .NET.
- **.NET 11 (STS, lançado em 10/11/2026):** tem recursos mais novos e suporte até a mesma data do .NET 10 (14/11/2028). Ficou de fora porque as bibliotecas ainda estão chegando a ele, e o .NET 10 já tem um ano de correções.

## Consequências

- O próximo salto é o .NET 12 (LTS), antes de o suporte do .NET 10 acabar, em novembro de 2028.
- O CI instala o último patch da faixa do SDK fixado, então correções de segurança entram sem mudar o `global.json`. Mudar de faixa (por exemplo, para 10.0.5xx) é uma troca explícita.
- A licença de cada dependência nova é conferida no review. Ficam de fora MediatR e AutoMapper (RPL-1.5 ou licença comercial), MassTransit 9 (comercial) e FluentAssertions 8 (só para uso não comercial). O ASP.NET Core já traz injeção de dependência, minimal APIs e health checks, e o xUnit tem as próprias asserções.
- A imagem do runtime (chiseled × Native AOT) fica para o ADR-010.
