# ADR-013: Dinheiro em centavos (BIGINT)

- **Status:** Aceito
- **Data:** 2026-11-12

## Contexto

Soma em ponto flutuante erra centavos. O valor passa por PostgreSQL, C#, JSON e Dart, e o Dart não tem tipo decimal: um número com casas decimais vira `double` no app.

## Decisão

- Centavos inteiros, com sinal, de ponta a ponta: `bigint` no banco, `long` no C#, inteiro no JSON (`amountCents`) e `int` no Dart. Todo campo de valor termina em `_cents` ou `Cents`.
- Negativo é dinheiro saindo da conta, inclusive no cartão: a compra é negativa e o pagamento recebido pelo cartão é positivo. A ingestão normaliza o sinal de cada provedor [Conferir: sinal das transações de cartão na Pluggy].
- Moeda única, o real (`CHECK (currency = 'BRL')`).
- Na entrada, o valor do provedor é lido como `decimal`, nunca como `double`, e multiplicado por 100. Se sobrar fração, o registro é recusado e o erro vai para o log [Conferir: tipo do campo amount na Pluggy].
- Percentuais, médias e 50/30/20 são calculados em `decimal` e arredondados só para mostrar. Na divisão em partes (RN-24), as partes somam exatamente o total, e o centavo que sobra vai para a maior parte.

## Alternativas consideradas

- **`numeric(15,2)` com `decimal` no C#:** é exato no servidor, mas o JSON e o Dart voltariam a carregar casas decimais.
- **`double`:** descartado, porque erra centavos.

## Consequências

- Nenhuma conta perde centavo, e a formatação em reais acontece só na tela.
- A demo web roda Dart como JavaScript, com inteiro exato até 2^53 centavos (cerca de R$ 90 trilhões), folga de sobra.
