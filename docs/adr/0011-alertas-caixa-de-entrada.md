# ADR-011: Alertas: caixa de entrada no app (MVP) e push via ntfy (v1)

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Eventos operacionais exigem ação do dono da instância: autorização bancária a 30 dias ou menos de vencer, conexão vencida (`USER_AUTHORIZATION_EXPIRED`), sincronização falhando há mais de 48 horas (RF-14, RF-56, RNF-25) e falha de backup cifrado (RF-65). Como o projeto é self-hosted e não tem servidor central, o mecanismo de aviso no MVP não pode depender de serviços proprietários de notificação nem expor dados financeiros fora da instância.

## Decisão

Criar o módulo `GranaPaCa.Modules.Alerts` (schema `alerts`) implementando uma caixa de entrada persistida no PostgreSQL no MVP, acessada pelos demais módulos apenas pelo contrato `IAlertPublisher` (`RaiseAsync` e `ResolveAsync`):

- **Um alerta por evento:** cada alerta aberto tem uma chave de deduplicação (`dedup_key`) única por casa. Repetir o mesmo problema atualiza o alerta aberto sem inundar a caixa.
- **Fechamento automático:** quando a condição se normaliza (conexão renovada, sincronização bem-sucedida ou backup concluído), o módulo emissor chama `ResolveAsync` e o alerta fecha sozinho (RF-56).
- **Experiência no app:** a tela inicial mostra a contagem de não lidos no sino; abrir um alerta marca como lido e navega para `action_target` (ex.: tela de conexões).
- **Push opcional na v1:** envio de avisos genéricos (sem valores, estabelecimentos nem nomes de banco) para um servidor `ntfy` configurado pela pessoa, plugado como canal secundário no mesmo publicador.

## Alternativas consideradas

- **Push nativo via Firebase (FCM) e Apple (APNs) no MVP:** exige conta de desenvolvedor, chaves centralizadas e envia tráfego de notificação por servidores de terceiros, contra a proposta self-hosted.
- **E-mail via SMTP obrigatório:** adiciona atrito alto de configuração (servidor, senha de app, entregabilidade) para quem só quer subir a instância com um comando.

## Consequências

- O MVP entrega alertas confiáveis, deduplicados e auditáveis sem nenhuma dependência externa além do PostgreSQL.
- Até a chegada do `ntfy` na v1, a pessoa só vê novos alertas ao abrir o app.
- Qualquer módulo novo (como backup ou alertas de fatura) pode abrir e fechar avisos pelo mesmo contrato `IAlertPublisher`, mantendo as fronteiras de módulo (ADR-002).
