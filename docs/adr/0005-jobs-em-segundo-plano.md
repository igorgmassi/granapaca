# ADR-005: Jobs em segundo plano com BackgroundService nativo

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O GranaPaCá é uma instância self-hosted single-tenant que precisa executar sincronização diária automática das conexões bancárias com retentativas e espera crescente (RF-13), além de tarefas periódicas leves como checagem de consentimentos perto do vencimento e alertas na caixa de entrada (ADR-011). A API roda em contêiner chiseled com pouca memória (ADR-010) e precisa permanecer simples de operar em computador pessoal, Raspberry Pi ou VM pequena.

## Decisão

Usar o **`BackgroundService` nativo do .NET (`IHostedService` + `PeriodicTimer`)** dentro do processo da API para os jobs recorrentes do MVP — começando pelo `DailySyncWorker` em `GranaPaCa.Modules.Banking` —, **adiando Hangfire e Quartz.NET** até haver necessidade real de fila distribuída, múltiplos workers ou agendas cron complexas por pessoa:

- **Execução isolada por ciclo:** `DailySyncWorker` aguarda um atraso inicial configurável (`Banking:InitialSyncDelaySeconds`), dispara no intervalo configurado (`Banking:SyncIntervalHours`, padrão de 24h) e abre um escopo de DI próprio (`IServiceScopeFactory`) para cada casa ao invocar `IBankingSyncTrigger`.
- **Resiliência sem estado extra:** falhas transitórias são retentadas com backoff exponencial (`MaxAttempts = 3`), sem registrar dados pessoais nos logs. Quando as tentativas se esgotam, o erro gera alerta na caixa de entrada do app (ADR-011).
- **Estado já persistido no PostgreSQL:** o estado de sincronização (`last_synced_at`, `consecutive_failures`, `first_failure_at`, `last_error_code`) fica em `banking.connection`, junto aos demais dados de domínio; se o contêiner reiniciar, o próximo ciclo retoma de forma idempotente.
- **Testabilidade:** a chave `Banking:EnableBackgroundSync` permite desligar o loop automático nos testes de integração e acionar ciclos sob demanda.

## Alternativas consideradas

- **Hangfire:** exige tabelas próprias no PostgreSQL, traz dashboard web que amplia a superfície de ataque (precisaria de proteção adicional) e adota licenciamento LGPLv3/comercial para recursos avançados, excessivo para um único job diário single-tenant.
- **Quartz.NET:** maduro para expressões cron sofisticadas, calendários e clustering com lock distribuído no banco, mas acrescenta dependência, schema de persistência e complexidade desnecessária enquanto houver apenas uma instância da API e ciclos fixos simples.
- **Cron externo no host chamando endpoint HTTP:** acopla lógica de agendamento ao sistema operacional da máquina, exige gerenciar token de serviço fora da API e quebra a experiência de subir tudo com um único `docker compose up`.

## Consequências

- Zero dependência externa de agendador, zero tabela extra de infraestrutura no banco e menor consumo de memória na imagem chiseled.
- Todo job em segundo plano precisa continuar idempotente e tolerante a reinícios do contêiner, apoiando-se no estado já salvo no PostgreSQL.
- Se na evolução pós-MVP surgirem filas assíncronas com alto volume, múltiplas réplicas ou agendamentos cron personalizados por pessoa, reavaliar Quartz.NET ou uma fila persistida no próprio PostgreSQL em um novo ADR.
