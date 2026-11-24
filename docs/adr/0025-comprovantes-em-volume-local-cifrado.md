# ADR-025: Comprovantes em volume local cifrado por arquivo

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

O módulo `GranaPaCa.Modules.Receipts` armazena anexos enviados pela pessoa — fotos de cupons, PDFs de faturas/boletos e XMLs de NFC-e — que frequentemente carregam CPF, endereço e histórico detalhado de consumo. O `infra/compose.yaml` já mantém apenas dois serviços (`api` e `db`) para caber confortavelmente em computadores pessoais, Raspberry Pi e VMs pequenas, com um volume dedicado `granapaca_appdata` (`/var/lib/granapaca/files`) já contemplado pelo fluxo de backup cifrado com `restic` (ADR-029).

## Decisão

Armazenar todos os comprovantes no **volume local `granapaca_appdata` (`/var/lib/granapaca/files`), cifrados individualmente por arquivo com AES-256-GCM usando o módulo `Keyring` (ADR-016)**, e **deixar o MinIO (ou qualquer object store separado) fora da pilha**:

- **Cifragem em envelope por arquivo:** cada anexo é cifrado via `IEnvelopeEncryptor` com uma DEK dedicada da casa (finalidade `receipts`), nonce aleatório de 12 bytes, tag de autenticação de 16 bytes e AAD vinculando o blob à tabela `receipts.attachment`, coluna `content` e ao `receipt_id` (UUIDv7). Um arquivo copiado para outro identificador não decifra.
- **Nomes opacos em disco:** os arquivos são gravados em subdiretórios por casa usando apenas o UUIDv7 do registro (sem nome original nem extensão reveladora), mantendo tipo MIME, nome original, tamanho, hash SHA-256 e itens extraídos no PostgreSQL (`receipts.*`).
- **Limites e integridade:** a API valida tipo MIME permitido e limite de tamanho por arquivo (alinhado ao teto de `10MB` no `infra/caddy/Caddyfile`) antes de cifrar e gravar.
- **Backup e exclusão direta:** `infra/backup/backup.sh` já envia `granapaca_appdata` em fluxo direto para o `restic` (ADR-029); ao remover um anexo ou executar "apagar tudo" (RF-07), os arquivos são excluídos e a destruição da DEK torna eventuais cópias órfãs ilegíveis.

## Alternativas consideradas

- **MinIO (ou outro servidor S3 self-hosted) no Compose:** adiciona um terceiro contêiner permanente com consumo relevante de RAM/CPU em hardware modesto, exige credenciais S3 adicionais para gerenciar e aumenta a superfície de atualização e licenciamento para uma instância single-tenant com poucos gigabytes de arquivos.
- **Guardar os binários em colunas `bytea` no PostgreSQL:** infla o tamanho do banco, aumenta o custo de `WAL`/vacuum e torna `pg_dump` e `pg_restore` lentos à medida que anos de fotos e PDFs acumulam.
- **Gravar arquivos em texto claro no volume confiando só na criptografia do disco:** se o volume for copiado ou montado fora do host original, todos os cupons e boletos ficam expostos.

## Consequências

- O `infra/compose.yaml` continua enxuto (`api` + `db`), sem serviços extras de armazenamento nem novas credenciais para rotacionar.
- Os arquivos no disco são opacos sem a `master_key` (ADR-016), e como cada blob cifrado é imutável após gravado, a deduplicação do `restic` funciona com eficiência máxima.
- Isolar leitura e gravação atrás de uma interface pequena de armazenamento no módulo `Receipts` preserva o caminho para suportar S3 externo no futuro, se um cenário multi-máquina justificar.
