# ADR-029: Backup cifrado com restic fora da máquina

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

A instância do GranaPaCá acumula anos de extratos normalizados, correções manuais, regras personalizadas e anexos cifrados. Discos locais falham e VMs gratuitas em nuvem — como a Oracle Cloud Always Free, que pode reclamar instâncias ociosas — podem desaparecer sem aviso (RF-65, RNF-24). Ao mesmo tempo, gravar um dump do banco em texto claro no disco ou enviá-lo sem cifra para um armazenamento externo violaria a privacidade do projeto.

## Decisão

Adotar **`restic`** para backup diário cifrado fora da máquina (`infra/backup/backup.sh`, `infra/backup/restore.sh` e guia operacional em `infra/BACKUP.md`):

- **Stream direto sem arquivo em claro no disco:** o backup executa `pg_dump --format=custom --no-owner` dentro do contêiner `db` e encaminha a saída diretamente por pipe para `restic backup --stdin`, fazendo o mesmo em fluxo para o volume `granapaca_appdata`. Nenhum arquivo `.dump` sem cifra toca o sistema de arquivos do host.
- **Destino fora da máquina:** o repositório `restic` aponta para armazenamento externo ao servidor da instância (Cloudflare R2, Backblaze B2, S3 compatível ou outro host via SFTP), agendado diariamente via `systemd` timer ou `cron`.
- **Retenção, integridade e alerta:** aplica política padrão de 7 diários, 4 semanais e 6 mensais (`--prune`), executa `restic check` ao final e grava o status de falha para alerta na caixa de entrada do app (ADR-011) e webhook opcional.
- **Separação rigorosa das chaves:** tanto `RESTIC_PASSWORD_FILE` quanto `infra/secrets/master_key.txt` (ADR-016) **nunca** entram no repositório de backup; ficam guardadas separadamente em cofre de senhas ou mídia cifrada fora do servidor.
- **Restauração testada (RNF-24):** `infra/backup/restore.sh` e o runbook em `infra/BACKUP.md` documentam e automatizam a recuperação em máquina nova, validando tabelas, histórico de migrações (`schemaversions`) e decifragem efetiva do 2FA TOTP com a `master_key`.

## Alternativas consideradas

- **Snapshots de disco ou VM no próprio provedor de nuvem:** se a conta ou instância gratuita for suspensa ou reclamada, o snapshot desaparece junto com o servidor.
- **`pg_dump` para arquivo local + `gpg` + `rclone`:** gera cópia temporária em texto claro no disco, exige gerir rotação e deduplicação manualmente e não traz verificação criptográfica de integridade equivalente ao `restic check`.
- **Replicação contínua do PostgreSQL em um segundo servidor:** dobra custo e complexidade operacional para um serviço pessoal de um único usuário e ainda não protege contra exclusões acidentais sem política de retenção.

## Consequências

- A instância inteira pode ser reconstruída em outra máquina ou provedor em minutos com o mesmo `infra/compose.yaml` (ADR-009), usando poucos megabytes extras por dia graças à deduplicação do `restic`.
- A segurança da recuperação depende de o dono manter cópia segura e externa de `RESTIC_PASSWORD_FILE` e `master_key.txt`; sem a primeira os snapshots não abrem, e sem a segunda segredos TOTP e payloads cifrados não são decifrados.
- Testar periodicamente o runbook de restauração em ambiente limpo passa a fazer parte da rotina recomendada de operação.
