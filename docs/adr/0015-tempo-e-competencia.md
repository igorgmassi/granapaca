# ADR-015: Tempo: UTC + America/Sao_Paulo; competência × caixa

- **Status:** Aceito
- **Data:** 2026-11-12

## Contexto

O mês do app é o mês civil no Brasil (RN-25), e o servidor roda em UTC. Algumas datas do banco são dias do calendário, sem hora. A compra parcelada no cartão tem três datas candidatas: a da compra, a da parcela e a do pagamento da fatura.

## Decisão

- Instantes em `timestamptz`, gravados em UTC; a sessão do banco usa `TimeZone = 'UTC'`.
- Dias do calendário em `date`: data da transação, fechamento e vencimento da fatura.
- O fuso da instância é America/Sao_Paulo por padrão, com uma configuração para quem mora em outro fuso do Brasil [Suposição]. O .NET usa o id IANA do fuso.
- Data que chega como meia-noite em UTC é um dia do calendário: vale a parte da data, sem converter, senão o dia volta um. Data com hora é convertida para o fuso da instância [Conferir: formato do campo date na Pluggy].
- Competência: os totais do mês usam `occurred_on`, a data da transação. Na compra parcelada, cada parcela usa a própria data de cobrança, e a data da compra fica em `purchase_on`, só para mostrar. Isso fecha a RN-19. O pagamento da fatura (caixa) não entra nos totais (RN-17).

## Alternativas consideradas

- **Tudo pela data da compra:** o mês da compra levaria o valor de todas as parcelas, contra a RN-19.
- **Caixa pela fatura:** casa com a saída da conta-corrente, mas leva cada compra do cartão para o mês do vencimento.
- **Só `timestamptz`:** obriga a converter o fuso em toda consulta e cria o erro do dia anterior.

## Consequências

- As consultas de mês comparam `date` com `date`, sem conversão de fuso no SQL.
- Se a Pluggy mandar a data da compra em todas as parcelas [Conferir], a ingestão calcula a data da parcela n como a data da compra mais n − 1 meses [Suposição].
- A imagem do servidor precisa da base de fusos (tzdata) [Conferir: imagem chiseled do .NET, ADR-010].
