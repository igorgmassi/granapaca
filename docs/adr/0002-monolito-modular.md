# ADR-002: Monólito modular em .NET, com um projeto por módulo e testes de arquitetura; microsserviços fora

- **Status:** Aceito
- **Data:** 2026-11-10

## Contexto

O backend junta assuntos com regras próprias: conexões bancárias, extrato, categorização, alertas, IA e comprovantes. Cada instância atende uma pessoa ou uma família (single-tenant) numa VM pequena, e uma pessoa mantém o projeto. As fronteiras entre esses assuntos precisam ficar claras sem o custo de operar serviços separados.

Na stack Java, o Spring Modulith verificava as fronteiras entre módulos. O .NET não tem um equivalente oficial.

## Decisão

O backend é um único processo ASP.NET Core (`GranaPaCa.Api`), que hospeda os módulos. Cada módulo é um projeto `GranaPaCa.Modules.<Nome>`, com:

- uma classe de entrada `<Nome>Module`, que o host usa para registrar os endpoints e os serviços do módulo;
- tipos `internal` por padrão;
- o namespace `GranaPaCa.Modules.<Nome>.Contracts` como a única parte que outros módulos podem usar;
- schema próprio no PostgreSQL e scripts de migração no próprio projeto (ADR-017).

Um teste de arquitetura com ArchUnitNET falha quando código de fora do módulo usa qualquer tipo dele além da classe de entrada e de `Contracts`. O teste encontra os módulos pelas referências do host, então um módulo novo entra na regra sem mudar o teste.

Microsserviços ficam fora.

## Alternativas consideradas

- **Microsserviços:** deploy, rede, observabilidade e consistência entre serviços custam caro para uma pessoa e uma VM, e nada no domínio pede escala independente.
- **Um projeto só, com uma pasta por módulo:** tem menos projetos, mas `internal` não separa pastas do mesmo assembly, e a fronteira passa a depender só de disciplina.
- **Quatro projetos por módulo (Domain, Application, Infrastructure e Contracts):** as fronteiras internas ficam mais rígidas, mas é cerimônia demais para módulos pequenos. Um módulo que crescer pode se dividir depois.
- **NetArchTest no lugar do ArchUnitNET:** o pacote não tem versão nova desde 2021. O ArchUnitNET (Apache-2.0) segue ativo.

## Consequências

- O compilador barra o uso de tipos `internal`. O teste de arquitetura cobre o que sobra: um tipo público usado fora do contrato.
- O host usa um `Main` comum, não *top-level statements*. O ArchUnitNET ignora o método que o compilador gera para eles e não veria como o host usa os módulos.
- O ArchUnitNET só lê todas as dependências num build de Debug, então o CI roda os testes em Debug.
- O módulo `Sample` é o molde, com schema `sample`, um script SQL e um endpoint com Dapper. Ele sai quando existir o primeiro módulo de verdade.
- A comunicação entre módulos fica para quando aparecer o primeiro caso: chamada a um contrato ou evento. Se pedir infraestrutura nova, como um outbox, ganha ADR próprio.
