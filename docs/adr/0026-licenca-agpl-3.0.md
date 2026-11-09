# ADR-026: Licença AGPL-3.0

- **Status:** Aceito
- **Data:** 2026-11-09

## Contexto

O GranaPaCá é open source e serve de portfólio: qualquer pessoa pode usar o código e rodar a própria instância. O app lida com dados financeiros pessoais, e oferecê-lo como serviço para terceiros está fora do escopo do projeto. A licença precisa permitir uso amplo sem abrir espaço para um serviço fechado que trate dados financeiros de outras pessoas sem transparência.

## Decisão

Todo o repositório é licenciado sob a GNU Affero General Public License v3.0 (AGPL-3.0), a mesma licença do Firefly III.

## Alternativas consideradas

- **MIT:** máxima liberdade de reuso, inclusive em produtos fechados e SaaS. Não exige que melhorias voltem nem que um serviço hospedado mostre o código que trata os dados de quem usa. É a licença do Actual Budget.
- **Apache-2.0:** permissiva como a MIT, com concessão explícita de patentes, e com a mesma lacuna para serviços hospedados.

## Consequências

- Qualquer pessoa pode usar, estudar, modificar e hospedar o app, inclusive para a própria família.
- Quem oferecer uma versão modificada como serviço em rede precisa disponibilizar o código-fonte dessa versão a quem a usa.
- As dependências previstas (Apache-2.0, MIT, BSD e LGPL) são compatíveis com a AGPL-3.0. Cada dependência nova tem a licença conferida no review.
- Algumas empresas evitam reaproveitar código AGPL. Para um projeto pessoal de portfólio, o efeito é pequeno.
- Contribuições entram sob a mesma licença (ver o guia de contribuição).
