# ADR-017: Persistência: Dapper + DbUp (SQL-first) × EF Core, schema por módulo e UUIDv7

- **Status:** Aceito
- **Data:** 2026-11-10

## Contexto

O modelo de dados do plano é escrito em SQL e usa recursos do PostgreSQL. O dado que vem do banco é preservado, e as correções ficam numa camada própria (ADR-012). Cada pessoa roda a própria instância, então o schema precisa se atualizar sozinho, sem passo manual. Uma migração que falha não pode deixar a API no ar com o schema antigo.

## Decisão

Dapper + DbUp, com SQL escrito à mão. EF Core fica fora.

- **Acesso a dados:** Dapper sobre o Npgsql, com um único `NpgsqlDataSource` registrado no host.
- **Migrações:** DbUp, com scripts SQL numerados (`Migrations/NNNN_descricao.sql`) embutidos no assembly de cada módulo.
  - O host aplica os scripts pendentes na subida, antes de atender requisições.
  - Cada script roda na própria transação. Se um script falha, a API não sobe.
  - O DbUp registra os scripts aplicados na tabela `schemaversions`.
  - Um script aplicado nunca muda: a correção vira um script novo.
- **Schema por módulo:** cada módulo tem o próprio schema (o de exemplo usa `sample`), e só ele lê e escreve nas próprias tabelas. Um script nunca depende de tabela de outro módulo, porque o DbUp ordena os scripts pelo nome completo, que começa pelo módulo.
- **Chaves:** UUIDv7 gerado pela aplicação com `Guid.CreateVersion7()`, ordenável pelo momento da criação.

## Alternativas consideradas

- **EF Core com migrações:** gera as migrações e facilita o CRUD, mas o modelo em C# vira a fonte da verdade no lugar do SQL do plano. Os recursos do PostgreSQL ficam mais difíceis de usar, e as consultas de relatório acabariam em SQL de qualquer forma.
- **Migrações num passo separado** (comando ou contêiner antes da API): dá mais controle sobre quando o schema muda, mas é um passo a mais na instalação de cada pessoa. Com uma instância só, rodar na subida basta.
- **UUIDv4 ou sequência:** o UUIDv4 espalha as inserções pelo índice. A sequência expõe a contagem de registros e obriga a ir ao banco para saber o id.

## Consequências

- O SQL é a fonte da verdade e passa pela revisão do PR como qualquer código.
- O mapeamento é manual: cada consulta lista as colunas. Os testes de integração rodam contra um PostgreSQL real (Testcontainers, imagem `postgres:18-alpine`), então um erro de SQL quebra o CI.
- O DbUp não desfaz migrações. Para reverter, escreve-se um script novo.
- Duas réplicas subindo juntas disputariam o mesmo script. Hoje cada pessoa roda uma instância só. Mais réplicas pediriam um lock, como o advisory lock do PostgreSQL.
- O Dapper gera código em tempo de execução. Native AOT pediria o Dapper.AOT, e isso entra na conta do ADR-010.
