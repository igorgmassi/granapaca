# ADR-012: Dado do provedor append-only e versionado + camada de ajustes

- **Status:** Aceito
- **Data:** 2026-11-12

## Contexto

A premissa do plano diz que o dado do banco é imutável. Mas a Pluggy pode mudar valor, descrição e às vezes o id de uma transação pendente quando ela é lançada, e remover pré-autorizações canceladas [Conferir: docs.pluggy.ai]. Se a linha for sobrescrita, o histórico some. Se a correção da pessoa se prender ao id do provedor, ela se perde quando o id muda (RN-08).

## Decisão

- Cada transação tem um id interno estável (`banking.transaction`). Ajustes, classificação e pares de transferência se prendem a ele.
- Todo id externo que já apontou para a transação fica em `banking.transaction_source`. Isso também resolve a deduplicação (RN-12): a chave (conta, origem, id externo) é única.
- O conteúdo vem em versões numeradas (`banking.transaction_version`). Uma versão nova só nasce quando o hash do conteúdo muda. Um sumiço vira uma versão com `is_removed = true`.
- Correções ficam em `banking.adjustment`, um registro por campo alterado, só com inclusões. Desfazer é um registro novo, com `undoes_id` apontando para o desfeito. Em cada campo vale o ajuste mais recente; um ajuste sem valor devolve o campo às regras.
- As tabelas de dado do provedor e de ajustes são append-only: um trigger recusa UPDATE e DELETE. Só o apagar tudo (RF-07) remove linhas, numa transação que liga a variável `granapaca.purge`. A `banking.classification` é derivada e pode ser regravada.
- A view `banking.transaction_effective` junta a última versão, a classificação e os ajustes.
- Quando chega um id novo e, na mesma sincronização, some uma pendente da mesma conta, com o mesmo valor e até 3 dias de diferença [Suposição], o id novo entra como mais uma origem da transação existente. Sem esse par, nasce uma transação nova, e a pendente ganha a versão de remoção.

## Alternativas consideradas

- **Sobrescrever a linha e prender o ajuste ao id do provedor:** é simples, mas perde o histórico e solta o ajuste quando o id muda.
- **Histórico com validade** (`valid_from` e `valid_to`, SCD tipo 2): fechar a versão anterior exige UPDATE, o que quebra o append-only.
- **Event sourcing completo:** daria o mesmo histórico com bem mais código (projeções e reconstrução) num app de uma pessoa.

## Consequências

- Ler a transação atual exige achar a última versão, e a view faz isso. O desempenho é medido contra o RNF-16; se não bastar, entra uma coluna com a versão atual ou uma view materializada, num script novo.
- O banco só cresce quando algo muda, por causa do hash.
- O apagar tudo precisa de um caminho próprio, que libera o DELETE.
- Ligar o id novo à pendente que sumiu é heurístico. Quando não liga, os ajustes da pendente ficam no histórico dela, e não passam para a transação nova.
- O modelo e o DDL estão nas Partes 4 e 5 do plano.
