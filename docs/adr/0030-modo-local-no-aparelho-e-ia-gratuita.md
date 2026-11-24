# ADR-030: Modo local no aparelho e IA gratuita por padrão

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Subir Docker Compose com PostgreSQL 18, configurar rede privada no Tailscale (ADR-009) e contratar uma chave paga de API de IA cria uma barreira alta para quem só quer organizar as finanças pessoais sem experiência em servidores nem custo mensal recorrente.

O app Flutter já conta com modo demo 100% local (ADR-008), base de cache local cifrado (ADR-007) e categorização determinística em camadas (ADR-021). Faltava, porém, um caminho persistente para usar dados reais direto no aparelho — sem nenhum servidor — e uma arquitetura explícita para que a assistente **Paçoca** entregue valor imediato com custo zero, mantendo opções gratuitas ou econômicas para quem desejar IA generativa.

## Decisão

Adotar uma **progressão em três degraus no mesmo app** combinada a uma **estratégia de IA gratuita por padrão**, sem criar servidor central nem abrir mão da privacidade:

### 1. Três degraus de uso no mesmo aplicativo

- **Demo:** dados sintéticos determinísticos no navegador (GitHub Pages) ou no app, sem cadastro e sem chamadas de rede (ADR-008), para experimentar o produto em segundos.
- **Só neste aparelho (local-first, sem servidor):** banco local cifrado dentro do próprio celular ou desktop — começando com armazenamento local cifrado autenticado com chave protegida pelo cofre seguro do sistema operacional e evolução planejada para SQLite/`drift` + SQLCipher conforme ADR-007. Inclui bloqueio por PIN/biometria, lançamento rápido de despesas (incluindo dinheiro físico), importação de extratos OFX/CSV (ADR-003) e notas NFC-e (ADR-022), motor local de regras e perfis, e backup/restauração completos em JSON com 1 toque — sem Docker, sem PostgreSQL e sem servidor.
- **Instância própria (self-hosted):** o modelo completo em Docker Compose + PostgreSQL 18 + Tailscale (ADR-009), destinado a quem deseja sincronização automática diária via Open Finance (Pluggy, ADR-003 e ADR-004), sincronia incremental entre múltiplos aparelhos (ADR-007), 2FA TOTP (ADR-024) e backup diário cifrado fora da máquina com `restic` (ADR-029).

### 2. IA gratuita ou de custo mínimo sem esforço de implantação

- **Padrão zero-conta e 100% gratuito:** o motor determinístico local da **Paçoca** combina as regras em camadas (ADR-021) com respostas financeiras estruturadas sobre saldo, categorias, estabelecimentos, orçamentos, metas, regra 50/30/20, projeções e assinaturas. Funciona inteiramente offline no próprio aparelho e também no backend com `provider = "none"`, sem exigir cadastro, cartão de crédito nem chave de API.
- **Alternativas gratuitas ou econômicas opcionais:** sobre os adaptadores HTTP tipados do módulo `GranaPaCa.Modules.Assistant` (ADR-020), oferecer presets prontos para:
  - **Google Gemini Flash** (camada gratuita via Google AI Studio);
  - **Groq** (camada gratuita em API compatível com OpenAI);
  - **OpenRouter** (modelos com sufixo `:free`);
  - **Ollama local** (100% gratuito rodando na própria máquina do usuário);
  - mantendo caminho aberto para **SLMs embarcados no próprio aparelho** (como Gemma on-device, Android AICore e Apple Foundation Models) à medida que o suporte multiplataforma amadurecer.
- **Privacidade preservada em camadas gratuitas:** toda chamada a provedor externo — inclusive em tiers gratuitos — passa obrigatoriamente pelo pipeline de minimização e pseudonimização reversível de PII (ADR-023). Antes de ativar qualquer camada gratuita de terceiros, a interface deve exibir aviso transparente sobre eventuais políticas de retenção ou uso de prompts do provedor escolhido.

## Alternativas consideradas

- **Exigir instância Docker para qualquer uso com dados reais:** bloqueia a adoção por pessoas não técnicas e obriga manter um servidor ativo mesmo quando o uso se resume a lançamentos manuais e importação de extratos OFX/CSV.
- **Manter uma nuvem gratuita ou proxy de IA hospedado pelo projeto:** viola o princípio de ausência de servidor central, gera custo contínuo de operação e expõe dados financeiros de terceiros sob responsabilidade dos mantenedores.
- **Exigir chave paga de IA ou Ollama local para habilitar a Paçoca:** impõe custo mensal (API paga) ou hardware dedicado (inferência local), deixando quem usa apenas o celular ou máquinas modestas sem assistente financeira.
- **Persistir o modo "Só neste aparelho" em JSON ou SQLite sem criptografia:** simplifica a implementação, mas deixa saldos e lançamentos expostos em backups do aparelho ou acesso local ao disco, contrariando o padrão de segurança do ADR-007.

## Consequências

- Qualquer pessoa consegue baixar o app, escolher **"Só neste aparelho"** e começar a organizar as finanças imediatamente sem configurar Docker, banco de dados ou conta de IA, podendo evoluir depois para uma instância própria via backup/restauração JSON.
- Os limites do modo **"Só neste aparelho"** ficam explícitos na interface e na documentação: não há sincronização automática com bancos via Pluggy (que exige backend e jobs periódicos, ADR-004 e ADR-005), não há sincronia entre múltiplos aparelhos nem backup automático fora da máquina via `restic` até migrar para uma instância própria.
- No modo local, a guarda periódica do arquivo de backup JSON fora do aparelho é responsabilidade da pessoa usuária; o app deve facilitar a exportação em 1 toque e emitir lembretes discretos de backup.
- A evolução do armazenamento local autenticado para SQLite/`drift` + SQLCipher deve preservar compatibilidade de migração transparente dos dados locais já salvos.
- Presets de camadas gratuitas de provedores externos (Gemini Flash, Groq, OpenRouter `:free`) podem sofrer ajustes de limites de taxa ou troca de identificadores de modelo ao longo do tempo e exigem manutenção leve e aviso claro sobre termos de retenção junto ao indicador de minimização ativa (ADR-023).
