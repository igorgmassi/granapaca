# ADR-007: Offline-first e sincronização por cursor

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Quem usa o GranaPaCá consulta saldos, extratos, faturas e gráficos em momentos sem internet ou fora da rede privada (Tailscale), esperando abertura instantânea e leitura disponível mesmo offline (RF-62). Ao mesmo tempo, armazenar o histórico financeiro em texto claro no aparelho expõe dados sensíveis, e introduzir resolução distribuída de conflitos no MVP adicionaria complexidade desnecessária antes mesmo da primeira versão utilizável.

## Decisão

Adotar leitura offline-first com **cache local cifrado** no aparelho e **sincronização incremental por cursor** com a instância, mantendo o servidor como única fonte de verdade no MVP:

- **Cache local cifrado:** nos apps nativos (Android, iOS, Windows, macOS e Linux), os dados sincronizados ficam em banco local cifrado (SQLite via `drift` + SQLCipher), com a chave de cifra protegida pelo cofre seguro do sistema operacional (Keychain, Keystore ou libsecret). Na demo web, apenas dados sintéticos rodam em memória sem persistência sensível.
- **Sincronização por cursor:** o app busca apenas alterações incrementais em `GET /api/v1/sync/changes?cursor=<token>`, recebendo contas, transações, ajustes, regras e alertas alterados desde o último cursor salvo em ordem monotônica. Se o cursor expirar ou ficar inválido, o servidor sinaliza ressincronização completa.
- **Leitura offline e escrita bloqueada até RF-44:** toda consulta (início, extrato, gastos, faturas e alertas) funciona offline sobre o cache local com indicação clara da data da última sincronização. Ações de escrita (correções manuais, regras e conexões) ficam bloqueadas com aviso claro enquanto não houver conexão com o servidor, adiando a fila offline de escrita para quando o lançamento de gastos em dinheiro físico (RF-44) entrar.

## Alternativas consideradas

- **App puramente online (sem cache local):** quebra o uso sem rede ou fora da tailnet, adiciona latência perceptível a cada tela e desperdiça banda reenviando meses de extrato.
- **Sincronização bidirecional com fila offline e resolução de conflitos já no MVP:** multiplica estados de erro, exige merge de regras/ajustes concorrentes entre dispositivos e atrasa o MVP sem necessidade imediata.
- **Cache local em JSON ou SQLite sem cifra:** deixa transações e saldos legíveis em backups do aparelho ou acesso local ao disco.

## Consequências

- O app abre imediatamente com os últimos dados sincronizados e consome pouca banda nas atualizações diárias.
- O backend precisa expor e manter um marcador monotônico de alterações no endpoint `GET /api/v1/sync/changes`, incluindo exclusões lógicas (*tombstones*) quando aplicável.
- Ao sair da conta ou trocar de instância, o app deve apagar o cache local e a chave correspondente no cofre do sistema operacional.
- Quando RF-44 for implementado, uma fila local idempotente para lançamentos em dinheiro físico será acrescentada sobre a mesma base sem reescrever o fluxo de leitura.
