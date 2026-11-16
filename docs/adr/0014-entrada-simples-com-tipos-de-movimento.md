# ADR-014: Entrada simples com tipos de movimento × partidas dobradas

- **Status:** Aceito
- **Data:** 2026-11-12

## Contexto

O app só lê. Cada banco entrega o seu lado do movimento, e a pessoa quer gastos e ganhos sem dupla contagem (RN-14 a RN-21), e não um balanço contábil. Os saldos vêm prontos do banco.

## Decisão

Entrada simples. Cada transação pertence a uma conta, tem valor com sinal e um tipo de movimento entre oito: `expense`, `income`, `own_transfer`, `card_payment`, `refund`, `withdrawal`, `investment` (aplicação) e `redemption` (resgate).

- As duas pontas de uma transferência própria se ligam em `banking.transfer_link`, e cada transação entra em no máximo um par ativo.
- Os gastos somam só `expense` e `refund`; o estorno é positivo e abate (RN-18). As receitas somam só `income`.

## Alternativas consideradas

- **Partidas dobradas** (cada movimento com débito e crédito que se anulam): traz a checagem de balanço e trata a transferência naturalmente. Mas cada transação do banco pediria uma contrapartida inventada, e ajuste, divisão e estorno virariam lançamentos contábeis. É peso demais para um agregador somente leitura.

## Consequências

- O modelo e as consultas ficam simples. O tipo vira o campo mais importante da classificação e pode ser corrigido (RF-24).
- Não há invariante de balanço. Como diagnóstico, dá para comparar o saldo do banco (`banking.balance_snapshot`) com a soma das transações.
- Se o patrimônio (RF-69, Futuro) pedir mais, este ADR é revisto.
