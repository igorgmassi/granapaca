# profiles

Perfis do guia inicial (RF-08) em YAML. Cada perfil representa uma realidade de ocupação, casa ou transporte e gera regras iniciais de essencialidade e marca, sempre acompanhadas de uma explicação curta exibida para a pessoa antes de ativar.

## Como funcionam

No primeiro acesso (ou ao refazer o guia nas configurações), a pessoa pode marcar mais de um perfil nos três grupos:

- **Ocupação (`occupation`):** `desenvolvedor`, `motorista-de-app`, `designer`, `estudante`, `professor`
- **Casa (`home`):** `casa-sozinho`, `casa-familia`, `casa-filhos`, `casa-pets`
- **Transporte (`transport`):** `transporte-carro-moto`, `transporte-publico`, `transporte-aplicativo`, `transporte-bicicleta-ape`

As regras de todos os perfis escolhidos entram na tela de revisão, onde a pessoa escolhe quais ativar. As regras do perfil rodam abaixo das correções manuais e das regras próprias da pessoa (ADR-021).

## Formato e JSON Schema

Todos os arquivos `.yaml` seguem [`schema.json`](schema.json) (JSON Schema Draft 2020-12):

| Campo | Obrigatório | Descrição |
|---|---|---|
| `id` | Sim | Identificador em `kebab-case`, igual ao nome do arquivo (sem `.yaml`) e único no catálogo |
| `group` | Sim | `occupation`, `home` ou `transport` |
| `label` | Sim | Rótulo curto em pt-BR exibido no guia inicial |
| `description` | Sim | Descrição curta em pt-BR de quem tem esse perfil |
| `rules` | Sim | Lista não vazia de regras |

Cada item de `rules`:

| Campo | Obrigatório | Descrição |
|---|---|---|
| `id` | Sim | Identificador em `kebab-case`, único em todo o catálogo |
| `name` | Sim | Nome curto da regra em pt-BR |
| `explanation` | Sim | Explicação empática e sem julgamento em pt-BR, mostrada no app |
| `essentiality` | Sim | Apenas `essential` (Essencial), `important` (Importante) ou `flexible` (Flexível) |
| `brand` | Não | Marca opcional em pt-BR (ex.: `Trabalho`, `Estudo`, `Casa`, `Pets`, `Transporte`) |
| `match` | Sim | Objeto com `categories` e/ou `keywords` usados pelo motor determinístico |

Categorias válidas em `match.categories`: `housing`, `food`, `transport`, `health`, `education`, `leisure`, `shopping`, `services`, `other`.

### Regras editoriais

- Use somente os três níveis (`essential`, `important`, `flexible`). Palavras com julgamento moral são rejeitadas automaticamente pelo validador.
- Nunca inclua dados reais, CPFs, nomes de terceiros ou extratos.

## Validar localmente

Requer apenas Node.js 22 (sem dependências externas):

```bash
node profiles/validate-profiles.mjs
```

O script confere a sintaxe YAML, valida cada arquivo contra `profiles/schema.json`, garante IDs únicos em todo o catálogo e barra termos com julgamento.

Para propor um novo perfil, siga o [guia de contribuição](../CONTRIBUTING.md#propondo-um-perfil-para-o-guia-inicial).
