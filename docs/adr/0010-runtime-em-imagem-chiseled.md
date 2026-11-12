# ADR-010: Runtime padrão em imagem chiseled × Native AOT

- **Status:** Aceito
- **Data:** 2026-11-12

## Contexto

Cada pessoa sobe a própria instância com `docker compose up` numa máquina ou VM pequena, em amd64 ou arm64 (RF-64). A imagem da API precisa existir para as duas arquiteturas, rodar sem root e ter pouca superfície de ataque. Quem instala não precisa ter o SDK do .NET.

O acesso a dados usa Dapper, que gera código em tempo de execução, e o DbUp lê os scripts embutidos por reflexão (ADR-017).

## Decisão

A API roda numa imagem chiseled do runtime do ASP.NET (`mcr.microsoft.com/dotnet/aspnet:10.0-noble-chiseled`): sem shell, sem gerenciador de pacotes e com o usuário `app`, que não é root. A imagem sai de um `backend/Dockerfile` multi-stage.

- O estágio de build roda no SDK, na arquitetura de quem compila (`--platform=$BUILDPLATFORM`). Ele publica IL portável, dependente do framework.
- O estágio final só copia os arquivos para a imagem chiseled. Por isso, o `docker buildx build --platform linux/amd64,linux/arm64` gera as duas arquiteturas sem emulação.
- A imagem chiseled não tem `curl`. O healthcheck do contêiner roda `dotnet GranaPaCa.Api.dll healthcheck`, que chama o próprio `/health`.

## Alternativas consideradas

- **Native AOT:** dá um binário único e sobe mais rápido. Mas o Dapper exigiria o Dapper.AOT, o DbUp e a reflexão teriam de ser revistos, e o AOT compila para cada arquitetura com o toolchain nativo dela, o que pede emulação ou um runner arm64 no CI. Para uma instância que sobe poucas vezes, o ganho não paga o custo. Reavaliar se a memória ou a partida virarem problema.
- **Publish de contêiner do SDK** (`dotnet publish /t:PublishContainer`): dispensa o Dockerfile, mas exige o SDK do .NET em quem roda o compose, e o `build:` do compose espera um Dockerfile.
- **Imagem `aspnet` comum (Debian):** tem shell e `curl` para o healthcheck, mas é maior, tem mais pacotes a corrigir e roda como root por padrão.

## Consequências

- Quem instala só precisa do Docker. O `infra/compose.yaml` constrói a imagem a partir de `backend/`.
- Sem shell no contêiner, não dá para depurar com `docker exec ... sh`. Para isso, usar logs ou um contêiner de depuração ao lado.
- As tags `sdk:10.0` e `aspnet:10.0-noble-chiseled` acompanham os patches de segurança do .NET 10. Publicar imagens versionadas e assinadas fica para o ADR-028.
- O CI constrói as duas arquiteturas e sobe o compose a cada PR que mexe em `backend/` ou `infra/` (workflow `infra`).
