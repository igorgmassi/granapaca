# Como contribuir

Obrigado pelo interesse! O GranaPaCá está em planejamento, então issues com ideias, dúvidas e críticas à arquitetura já ajudam muito.

## A regra de ouro: nada de dados reais

Nunca inclua dados financeiros reais em issues, PRs, commits, prints ou fixtures de teste. Isso vale para extratos, faturas, comprovantes, CPF, nomes de terceiros, números de conta ou cartão, tokens, chaves de API e credenciais da Pluggy. Use sempre dados sintéticos.

Se algo real escapar, avise em sigilo pelo [relato privado de segurança](SECURITY.md) em vez de comentar em público.

## Antes de começar

- Para mudanças grandes, abra uma issue primeiro e combine a abordagem.
- Decisões de arquitetura viram ADR em [`docs/adr`](docs/adr), a partir do [modelo](docs/adr/0000-template.md).
- Código, nomes de tabelas, rotas e mensagens de commit em inglês; documentação, ADRs e textos da interface em português do Brasil.

## Fluxo de trabalho

1. Crie uma branch curta a partir da `main`: `feat/...`, `fix/...`, `docs/...` ou `chore/...`.
2. Faça commits no padrão [Conventional Commits](https://www.conventionalcommits.org/pt-br/v1.0.0/), por exemplo `feat(ledger): detect transfers between own accounts`.
3. Abra um PR para a `main` preenchendo o template. O merge é por squash.

## Proteção contra vazamento de segredos

O CI roda o [gitleaks](https://github.com/gitleaks/gitleaks) em todo push e PR. Para pegar o problema antes do commit, instale o hook local:

```bash
pip install pre-commit
pre-commit install
```

## Propondo um perfil para o guia inicial

Perfis (desenvolvedor, motorista de app, estudante...) geram regras de essencialidade e de marca. Eles ficam em YAML em [`profiles/`](profiles/) e serão validados por JSON Schema no CI.

1. Abra uma issue com o template **Propor um perfil** ou mande um PR com o arquivo YAML.
2. Cada regra precisa de uma explicação curta, que o app mostra para a pessoa.
3. Use só os níveis Essencial, Importante e Flexível. Nada de "Supérfluo" ou de rótulos com julgamento.
4. Pense em quem tem esse perfil de verdade: o que é ferramenta de trabalho para uma pessoa pode ser flexível para outra.

## Licença das contribuições

Ao contribuir, você concorda que a sua contribuição será licenciada sob a [AGPL-3.0](LICENSE), a mesma licença do projeto.
