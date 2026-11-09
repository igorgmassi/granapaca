# Política de segurança

O GranaPaCá lida com dados financeiros pessoais. Relatos de vulnerabilidade são muito bem-vindos e tratados em sigilo.

## Como relatar

1. Abra um relato privado em **Security → Report a vulnerability** neste repositório ([link direto](https://github.com/igorgmassi/granapaca/security/advisories/new)).
2. Descreva o problema, o impacto e os passos para reproduzir.
3. **Não inclua dados reais**: extratos, CPF, números de conta, tokens, chaves de API ou credenciais da Pluggy. Use dados sintéticos.

Nunca abra issue pública, PR ou discussão sobre uma vulnerabilidade antes da correção.

## O que esperar

O projeto é mantido por uma pessoa, no tempo livre. A meta é confirmar o recebimento em até 7 dias e combinar com quem relatou o prazo de correção e de divulgação. Quem relatar recebe crédito no aviso de segurança, se quiser.

## Versões suportadas

O projeto está em planejamento e ainda não tem releases. Até a primeira versão estável, só a branch `main` recebe correções de segurança.

## Escopo

- **Dentro:** o código deste repositório (app, backend, perfis, infraestrutura e workflows) e a configuração padrão que ele entrega.
- **Fora:** a infraestrutura de cada pessoa que roda a própria instância e os serviços de terceiros (Pluggy, provedores de IA, GitHub). Falhas nesses serviços vão para os respectivos responsáveis.

## Quem roda a própria instância

O guia de resposta a incidentes para quem roda a própria instância (o que revogar, o que trocar e como restaurar) será publicado em [`docs/`](docs/) antes da primeira versão.
