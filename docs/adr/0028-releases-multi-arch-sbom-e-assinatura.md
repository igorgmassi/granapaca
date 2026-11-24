# ADR-028: Releases multi-arch no GHCR com SBOM SPDX e assinatura keyless

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Quem hospeda o GranaPaCá roda a instância em máquinas `linux/amd64` (PCs e VMs tradicionais) ou `linux/arm64` (Raspberry Pi, mini-PCs ARM e VMs ARM na nuvem — ADR-009, ADR-010). Embora o `infra/compose.yaml` já permita compilar a API localmente a partir de `backend/Dockerfile`, publicar imagens oficiais pré-construídas acelera atualizações e facilita a adoção. Por se tratar de um sistema que lida com dados financeiros pessoais, cada imagem publicada precisa ser verificável quanto à origem (proveniência e assinatura) e transparente quanto às dependências incluídas (SBOM).

## Decisão

Publicar imagens multi-arch da API no **GitHub Container Registry (`ghcr.io/<owner>/granapaca-api`)** por meio do workflow `.github/workflows/release.yml`, disparado por **tags SemVer `v*.*.*`** (e com `workflow_dispatch` em modo *dry-run* por padrão):

- **Build multi-arquitetura (`linux/amd64` e `linux/arm64`):** usa `docker/setup-qemu-action`, `docker/setup-buildx-action` e `docker/build-push-action` sobre `backend/Dockerfile` (imagem chiseled, ADR-010), publicando um manifest list único para as duas arquiteturas.
- **Tags semânticas e metadados OCI:** `docker/metadata-action` gera as tags de versão (`X.Y.Z`, `X.Y`, `latest` apenas em releases estáveis e `sha-<commit>`) e labels OCI padrão com repositório, revisão e licença AGPL-3.0.
- **SBOM SPDX e proveniência SLSA:** `docker/build-push-action` gera e anexa diretamente ao índice OCI o SBOM em formato SPDX (`sbom: true`) e a attestation de proveniência (`provenance: true`).
- **Assinatura keyless via Cosign/Sigstore:** em releases por tag, `sigstore/cosign-installer` assina a imagem **pelo digest imutável (`@sha256:...`)** usando o token OIDC do GitHub Actions (`id-token: write`), sem armazenar chave privada estática nos segredos do repositório.
- **Cadeia de suprimentos endurecida:** todas as GitHub Actions no workflow são fixadas por SHA completo de commit, com `persist-credentials: false` e permissões mínimas (`contents: read`, `packages: write`, `id-token: write`, `attestations: write`).

## Alternativas consideradas

- **Publicar no Docker Hub:** exige manter credenciais estáticas separadas e impõe limites de pull mais rígidos para usuários anônimos, enquanto o GHCR integra-se nativamente ao `GITHUB_TOKEN` efêmero do repositório.
- **Assinar com chave privada Cosign/GPG guardada em Secrets:** introduz gestão de rotação e risco de comprometimento de chave de longa duração; a assinatura keyless via Fulcio + Rekor vincula a imagem diretamente ao workflow e ao commit exato no GitHub.
- **Automatizar cortes com `release-please` desde o início:** útil quando o ritmo de releases ficar frequente, mas disparar o pipeline por tag explícita `v*.*.*` dá controle direto sobre notas de versão e migrações agora, mantendo compatibilidade total caso o `release-please` passe a abrir PRs e criar as tags no futuro.

## Consequências

- Qualquer pessoa pode verificar a autenticidade da imagem antes de subir com `cosign verify` (conferindo emissor OIDC e workflow do repositório) e inspecionar o SBOM SPDX com `docker buildx imagetools inspect`.
- O acionamento manual (`workflow_dispatch`) roda por padrão em *dry-run*, validando o build multi-arch sem publicar nem poluir o log de transparência Sigstore.
- Toda release oficial exige uma tag SemVer `v*.*.*` e atualização periódica dos SHAs fixados das actions (já coberta pelo Dependabot em `.github/dependabot.yml`).
