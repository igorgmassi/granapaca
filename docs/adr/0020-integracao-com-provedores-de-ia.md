# ADR-020: Integração com provedores de IA via HttpClient tipado

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O GranaPaCá é self-hosted e trata a IA como recurso opcional pós-MVP: cada pessoa traz a própria chave da **OpenAI**, **Anthropic** ou **Google**, ou aponta a instância para um modelo local rodando no **Ollama**. O módulo `GranaPaCa.Modules.Assistant` precisa suportar categorização assistida (após as regras determinísticas do ADR-021), visão opcional para comprovantes sem XML/QR (ADR-022) e chat financeiro com ferramentas somente leitura e streaming via SSE (ADR-018). Todas as chaves ficam apenas no backend, cifradas em envelope (ADR-016), e toda chamada externa passa antes por minimização e pseudonimização (ADR-023).

## Decisão

Adotar uma **abstração interna enxuta sobre `HttpClient` tipado (`IHttpClientFactory`)** no módulo `GranaPaCa.Modules.Assistant` para falar diretamente com **OpenAI, Anthropic, Google e Ollama**, mantendo o contrato interno alinhado às primitivas de `Microsoft.Extensions.AI` para migração futura sem retrabalho, e **deixar o Semantic Kernel fora**:

- **Adaptadores HTTP finos por provedor:** cada provedor é um cliente tipado usando `System.Text.Json`, com DTOs mínimos para completion, chamadas de ferramentas (tool calling), streaming de tokens e visão opcional.
- **Caminho aberto para `Microsoft.Extensions.AI`:** a interface interna de conversa (mensagens com papéis, definição de ferramentas somente leitura e resposta em streaming) espelha o modelo conceitual de `IChatClient`, permitindo trocar os adaptadores HTTP pelos pacotes oficiais quando todos os quatro provedores tiverem suporte estável e uniforme.
- **Segurança e observabilidade controladas:** o cliente controla explicitamente timeouts, limite de tokens, cabeçalhos de autenticação e captura de erro, garantindo que chaves de API e textos de extrato nunca apareçam em logs e que o pipeline do ADR-023 envolva 100% das chamadas.
- **Ferramentas estritamente somente leitura:** o chat só expõe consultas agregadas e minimizadas ao modelo; nenhuma ferramenta altera transações, regras ou dados bancários.

## Alternativas consideradas

- **Semantic Kernel:** framework pesado de orquestração (planners, conectores de memória vetorial e plugins dinâmicos) com alta rotatividade de API e árvore grande de dependências para um assistente enxuto com poucas ferramentas fixas somente leitura.
- **Adotar imediatamente os SDKs de cada provedor + `Microsoft.Extensions.AI`:** puxa múltiplos pacotes externos em ritmos de versão distintos (com lacunas históricas nos adaptadores oficiais para Anthropic e Google) antes mesmo de estabilizarmos nossos fluxos de privacidade e streaming.
- **Gateway externo de modelos (como LiteLLM):** exige mais um contêiner Python no `infra/compose.yaml`, eleva o uso de memória em máquinas pequenas e amplia a superfície de ataque.

## Consequências

- Superfície mínima de dependências, imagem Docker menor e testes determinísticos com `HttpMessageHandler` falso, seguindo o mesmo padrão já adotado para a Pluggy (ADR-004).
- O pipeline de minimização e pseudonimização (ADR-023) atua numa única fronteira antes da serialização JSON, sem risco de um SDK oculto enviar metadados extras.
- O custo é manter manualmente os poucos payloads HTTP de OpenAI, Anthropic, Google e Ollama conforme evoluem — esforço pequeno e isolado que pode ser substituído pelos pacotes de `Microsoft.Extensions.AI` quando amadurecerem.
