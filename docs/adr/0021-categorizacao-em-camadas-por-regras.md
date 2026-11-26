# ADR-021: Categorização em camadas com motor de regras único e cache por estabelecimento

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

As transações precisam chegar já classificadas em categoria, essencialidade (`essential`, `important` ou `flexible`, nunca termos com julgamento) e marca opcional, de maneira determinística, explicável e com zero envio de dados para provedores de IA no MVP (RF-08, RF-26, RF-27, RF-30, RF-31, RN-30, RNF-38). Alterar o perfil ou desativar uma regra deve reclassificar transações sem jamais sobrescrever correções feitas manualmente pela pessoa.

## Decisão

Centralizar toda a classificação no módulo `GranaPaCa.Modules.Categorization` (schema `categorization`), por meio de um único motor determinístico (`ICategorizationEngine`) avaliado em camadas ordenadas — a primeira que casar vence:

1. **Correções manuais da transação** (`banking.adjustment`, ADR-012): têm precedência absoluta e não são alteradas pela reclassificação.
2. **Regras da pessoa** (criadas manualmente ou via "aplicar às semelhantes" no RF-26): avaliadas por prioridade e especificidade, com correspondência por CNPJ normalizado antes de descrição normalizada.
3. **Regras do perfil** escolhidas no guia inicial (RF-08, catálogo YAML validado por JSON Schema em `profiles/`), ativáveis e desativáveis individualmente.
4. **Regras do sistema e cache/dicionário por estabelecimento:** chaves normalizadas por `MerchantNormalizer` (CNPJ com 14 dígitos; descrição em minúsculas sem acentos nem ruído).
5. **Sem categoria:** quando nenhuma camada casa, a transação vai para a fila "A revisar" (RF-31) sem desaparecer dos totais.

Cada classificação grava `deciding_layer`, `deciding_rule_id` e a explicação curta exibida no detalhe da transação (RF-27, RF-30). Mudanças em regras ou perfil acionam `ITransactionReclassifier`.

## Alternativas consideradas

- **Classificação por IA/LLM como padrão no MVP:** viola o requisito de nenhum dado sair para IA no MVP (RF-30), introduz custo variável e quebra determinismo.
- **Usar apenas a categoria vinda da Pluggy:** varia muito entre instituições, não resolve essencialidade personalizada por perfil e não explica por que uma decisão foi tomada.
- **Motores separados para perfil e regras manuais:** dificulta garantir precedência consistente e explicar qual regra venceu quando há sobreposição.

## Consequências

- Rodar o motor de novo sobre a mesma transação com as mesmas regras gera exatamente o mesmo resultado.
- A pessoa sempre vê qual camada e qual regra decidiu cada gasto e pode desativar qualquer regra sem perder correções manuais.
- Na v1, a sugestão por IA entra como camada opcional após as regras determinísticas, passando pela minimização e pseudonimização do ADR-023.
