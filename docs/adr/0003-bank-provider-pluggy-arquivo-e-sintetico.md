# ADR-003: BankProvider: Pluggy (real e Sandbox), Arquivo OFX/CSV e Sintético

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O GranaPaCá é somente leitura e precisa buscar contas, saldos, transações e faturas sem acoplar o domínio bancário a um único fornecedor. Em produção no Brasil a origem principal é o Open Finance via Meu Pluggy (RF-12, RF-13), mas quem sobe a própria instância sem credenciais da Pluggy (RF-64) ou testa o sistema em CI precisa de dados fictícios confiáveis. Além disso, quem não quer usar Open Finance precisa de um caminho futuro por importação de arquivos OFX/CSV.

## Decisão

Definir uma interface única `IBankProvider` no módulo `GranaPaCa.Modules.Banking` que devolve contas, transações, faturas e snapshots de saldo já normalizados (centavos inteiros em BRL, ADR-013; tipo de movimento, ADR-014; datas em calendário/UTC, ADR-015), entrando todos pelo mesmo pipeline append-only e deduplicado (ADR-012):

- **Pluggy (produção e Sandbox):** ativa quando `PLUGGY_CLIENT_ID` e `PLUGGY_CLIENT_SECRET` estão configurados na instância, usando o cliente HTTP tipado (ADR-004).
- **Sintético:** gerador determinístico embutido, ativado automaticamente quando não há credenciais da Pluggy (RF-64). Compartilha a mesma base de dados fictícios da demo offline (ADR-008, RF-63).
- **Arquivo (OFX/CSV):** planejado sobre o mesmo contrato, com origem própria (`source`) em `banking.transaction_source` para evitar duplicatas com sincronizações bancárias.

O endpoint `/api/v1/server-info` expõe o `providerMode` ativo (`pluggy` ou `synthetic`) para o app adaptar o fluxo de conexão.

## Alternativas consideradas

- **Acoplar o módulo `Banking` direto aos DTOs da Pluggy:** reduz tradução no curto prazo, mas trava o domínio na API de um provedor e impede o modo sintético ou OFX/CSV sem reescrever a ingestão.
- **Integrar vários agregadores pagos no MVP (ex.: Belvo, Klavi):** multiplica contrato, manutenção e testes sem ganho real para uma instância self-hosted individual.
- **Deixar dados sintéticos só em mocks de teste:** impede subir a instância com um comando sem conta na Pluggy (RF-64) e quebra a validação ponta a ponta no CI.

## Consequências

- O pipeline de versionamento, deduplicação, pareamento de transferências e categorização independe de onde o extrato veio.
- Uma instância recém-subida já funciona imediatamente em modo sintético, sem vazar nem exigir credenciais externas no CI.
- Toda origem nova precisa mapear o sinal de compras/pagamentos de cartão (ADR-013) e gerar uma chave externa estável por conta para `banking.transaction_source`.
