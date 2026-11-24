# ADR-023: Minimização e pseudonimização reversível antes da IA

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Um princípio inegociável do GranaPaCá é que nenhum dado financeiro bruto saia da instância para provedores externos de IA (OpenAI, Anthropic ou Google) sem minimização prévia. Descrições de extrato bancário, boletos e transferências Pix frequentemente contêm dados pessoais identificáveis da própria pessoa e de terceiros: CPF, CNPJ, e-mails, telefones, números de agência/conta, chaves Pix aleatórias e nomes reais de bancos e estabelecimentos.

## Decisão

Impor no módulo `GranaPaCa.Modules.Assistant` um **pipeline obrigatório de minimização e pseudonimização reversível** executado antes de qualquer serialização destinada a um provedor de IA (ADR-020):

- **Minimização de dados:** enviar apenas o recorte mínimo necessário para a operação — totais agregados por categoria/período nas consultas do chat, ou lotes curtos de descrições higienizadas na categorização —, nunca o extrato completo nem payloads brutos da Pluggy.
- **Redação determinística de PII:** detectar e remover antes do envio padrões de CPF, CNPJ, endereços de e-mail, telefones (incluindo formatos brasileiros com DDD), números de conta/agência/cartão e chaves Pix UUID, substituindo-os por marcadores neutros (`[CPF]`, `[CNPJ]`, `[EMAIL]`, `[TELEFONE]`, `[CONTA]`).
- **Pseudonimização reversível por sessão:** substituir nomes de bancos, contas e estabelecimentos por tokens efêmeros únicos daquela sessão/chamada (como `[BANCO_1]`, `[ESTAB_1]`). O mapa de correspondência vive apenas em memória na instância e é usado para restaurar os nomes legíveis quando a resposta volta para a pessoa.
- **Proteção padrão mesmo em modelo local:** o pipeline roda ligado por padrão inclusive quando o provedor configurado é o Ollama local, evitando vazamento de PII em logs do motor de inferência, com opção explícita de flexibilização apenas para host local confiável.
- **Sem persistência nem log do mapa:** o mapa de pseudônimos é descartado ao fim da sessão/requisição e nunca é gravado em banco ou log.

## Alternativas consideradas

- **Confiar apenas na política de "zero data retention" dos provedores:** transfere a privacidade da pessoa para termos de serviço externos sujeitos a mudança e continua transmitindo CPF e contas em claro pela rede.
- **Anonimização irreversível (apagar completamente nomes de estabelecimentos e bancos):** impede o modelo de relacionar recorrências no mesmo contexto e devolve respostas do chat cheias de lacunas difíceis de ler.
- **Aceitar somente modelos locais via Ollama:** elimina tráfego externo, mas inviabiliza o recurso em mini-PCs, Raspberry Pi e VMs pequenas sem memória ou GPU suficiente.

## Consequências

- A pessoa pode combinar a qualidade dos modelos de nuvem com proteção real contra exposição de documentos, contas e dados de terceiros, recebendo respostas naturais já restauradas no app.
- Testes automatizados de vazamento com fixtures sintéticas (CPF, CNPJ, e-mails, telefones e contas fictícias) validam que nenhum dado sensível cruza a fronteira HTTP do módulo `Assistant`.
- Variações regionais de descrições de Pix e extratos bancários exigem manutenção contínua das regras de detecção, sempre cobertas por novos casos de teste.
