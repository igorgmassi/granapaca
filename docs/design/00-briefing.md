# Briefing original do design

Este é o briefing de identidade visual de 05/11/2026, o ponto de partida do design. Ele fica aqui como referência. Onde o briefing e as partes divergem, valem as partes: a [Parte 1](01-revisao-das-decisoes.md) lista as 17 mudanças e o porquê de cada uma. Exemplos: as fontes viraram Baloo 2 e Figtree, e a paleta dos gráficos foi refeita.

## Papel e objetivo

Você é um(a) designer de produto e de marca sênior, com experiência em apps financeiros, design systems, ilustração de mascotes e Flutter (Material 3). Sua tarefa é transformar as decisões criativas abaixo na **identidade visual e no design das telas** do Grana PaCá, prontos para eu implementar em Flutter.

As decisões deste documento são o ponto de partida. Você pode refiná-las, mas toda mudança precisa de uma justificativa curta. Onde houver dúvida real sobre o que eu quero, pergunte antes de assumir.

## Contexto do produto

- **O que é:** app de finanças pessoais que junta, via Open Finance, as contas de vários bancos num lugar só. O nome é um trocadilho: "grana pra cá" (o app traz o dinheiro de todos os bancos para um lugar) e "grana pra paca" (muito dinheiro). A pronúncia oficial é "pa-CÁ".
- **Slogan:** "Toda a sua grana, pra cá."
- **Plataformas:** Flutter para Android, iOS e desktop, mais uma demo pública em Flutter Web com dados fictícios.
- **Público:** pessoas comuns que querem entender para onde vai o dinheiro sem planilha, e recrutadores que vão ver o projeto no portfólio.
- **Privacidade:** cada pessoa roda o próprio servidor, e os dados não saem de lá. O visual precisa passar confiança sem parecer banco.
- **Funcionalidades que viram telas:**
  - guia inicial que traça o perfil (ocupação, casa, transporte e revisão das regras);
  - visão geral e uma seção por banco, mais a seção Dinheiro físico;
  - extrato com tipo e forma de pagamento, correção de lançamento com justificativa e histórico;
  - comprovantes: foto da nota fiscal, QR Code da NFC-e, PDF e divisão do valor em partes;
  - gráficos: rosca por categoria, ranking, evolução mensal, mês atual x média, mapa de calor no calendário, Essencial x Flexível e regra 50/30/20;
  - chat com IA;
  - orçamentos, metas e projeções;
  - alertas;
  - exportação e importação;
  - privacidade: biometria, esconder valores e apagar tudo;
  - modo demo.

## Conceito e personalidade

**Ideia central: a paca que junta tudo.** O app é a toca da Paçoca, uma paca que traz a grana de todos os bancos pra cá e ajuda a entender cada real. O visual é quente e brasileiro, com cores de fruta e de mata, longe do azul frio de banco.

**Regra de ouro: diversão nos detalhes, clareza no que importa.** Navegação, números e botões são sérios e diretos. A graça mora no mascote, nas mensagens, nos estados vazios e nas comemorações.

**Tom de voz:** um amigo que entende de dinheiro, não um gerente de banco.

- Informal, com "você", frases curtas e palavras do dia a dia. Termo técnico vem explicado.
- Nunca julga: "Flexível", nunca "Supérfluo". Nada de culpa por gasto com delivery ou fumo.
- Comemora conquistas e dá notícia ruim com calma, sempre com o próximo passo.
- No máximo uma brincadeira por tela. Em erro que envolve dinheiro, nenhuma.

**Exemplos de mensagens:**

| Situação | Mensagem |
|---|---|
| Estado vazio | Nada por aqui ainda. Conecte um banco e traga sua grana pra cá. |
| Meta batida | Meta batida! A Paçoca está dando pulinhos. |
| Alerta | O delivery passou de R$ 300 este mês. Quer ver os pedidos? |
| Fatura alta | A fatura veio maior que a média. Bora ver o que pesou? |
| Sem internet | A Paçoca cochilou. Assim que a internet voltar, ela sincroniza. |
| Conexão vencendo | A conexão com o seu banco vence em 7 dias. Renove para não perder nada. |
| Erro ao salvar | Não deu para salvar. Seus dados estão seguros; tente de novo. |

## Mascote: Paçoca

**Quem é:** a Paçoca, uma paca gordinha e simpática, que também é a assistente do chat com IA ("Pergunte pra Paçoca").

**Aparência:**

- corpo arredondado cor de caramelo, com focinho e barriga creme;
- fileiras de pintas creme nas laterais, desenhadas como moedinhas, que são a marca registrada dela;
- olhos grandes e brilhantes, orelhas pequenas e redondas, patinhas curtas;
- uma pochete, onde ela guarda a grana que traz pra cá;
- traço vetorial plano, formas redondas, sem contorno preto e no máximo 3 tons por cor.

**Expressões e quando usar:**

| Expressão | Quando aparece |
|---|---|
| Acenando | Boas-vindas e guia inicial |
| Comemorando, com moedinhas pulando | Meta batida, mês com sobra |
| Pensando, com a pata no queixo | IA processando, chat digitando |
| Com lupa | Lendo nota fiscal ou comprovante |
| Dormindo (pacas são noturnas) | Sem internet, sincronização pendente |
| Mergulhando (pacas nadam muito bem) | Atualizando os dados, ao puxar a tela para baixo |
| Preocupada, sem drama | Alertas e conexão vencendo |
| Segurando um cadeado | Telas de privacidade e segurança |

**Onde não aparece:** em listas de transações, ao lado de valores negativos em tom de piada, e mais de uma vez na mesma tela. Ela ajuda e nunca atrapalha a leitura dos números.

**Animação:** a Paçoca é animada no Rive, com uma máquina de estados (parada, feliz, pensando, dormindo e preocupada) que o app troca conforme a situação.

## Cores

**Paleta "Mata e Fruta":** tons quentes da paca e de frutas brasileiras, longe das cores dos bancos que aparecem dentro do app. Todos os pares de texto abaixo foram conferidos e passam do contraste mínimo de 4,5:1 (WCAG AA).

| Token | Claro | Escuro | Uso |
|---|---|---|---|
| Caramelo (marca) | #A0521A | #E8A066 | Botões principais, destaques e logo |
| Sobre Caramelo | #FFFFFF | #2A1407 | Texto sobre o botão principal |
| Paçoca (fundo) | #FBF5EC | #17110D | Fundo das telas |
| Superfície | #FFFFFF | #221A14 | Cartões e folhas |
| Cacau (texto) | #2A1C12 | #F7EFE6 | Texto principal |
| Cacau suave | #6B5546 | #C4B2A2 | Texto secundário |
| Borda de campo | #94816E | #86725F | Contorno de campos de formulário (3:1) |
| Mata | #2A7550 | #6CC596 | Receitas e valores positivos |
| Urucum | #B83A22 | #FF8B73 | Alertas, orçamento estourado e erros |
| Milho | #E5A62B | #F3C35A | Destaques e avisos, sempre com texto escuro por cima |
| Rio | #22649C | #7DB9EA | Informações e links |
| Jabuticaba | #6E4AA3 | #B9A0EE | Chat e IA |

**Como o dinheiro aparece:**

- Gastos na cor normal do texto, com sinal de menos. Vermelho fica só para alerta: um app cheio de vermelho dá ansiedade.
- Receitas em Mata, com sinal de mais.

**Essencialidade é uma escala, não um semáforo.** Os três níveis usam tons de Caramelo, do mais forte ao mais claro. Nada de verde e vermelho, que passam a ideia de certo e errado.

| Nível | Claro | Escuro |
|---|---|---|
| Essencial | #6F340E | #F5CBA4 |
| Importante | #A65E28 | #DA955C |
| Flexível | #C98545 | #B5733C |

Os três passam de 3:1 contra a superfície, mas são parecidos entre si. Por isso aparecem sempre com o nome do nível, ou com 2 px de separação entre as faixas dos gráficos.

**Gráficos por categoria:** Caramelo #C26A2A, Mata #2E8B5E, Milho #D99A1E, Jabuticaba #7B55B0, Rio #2F7FC1, Urucum #D0503A, Goiaba #D24F7A, Igarapé #1D8A8A e "Outros" em cinza quente #A3958A. Milho e Outros ficam abaixo de 3:1 contra o branco, então pedem contorno ou rótulo direto. Valide a paleta para daltonismo e crie as versões do tema escuro.

**Cores dos bancos:** cada banco aparece com a própria cor só numa faixa fina e no logo, para ser identificado. Use a cor e o logo que a Pluggy fornece para cada conector, em vez de guardar logos de bancos no repositório. Confira esses campos na documentação da Pluggy.

## Tipografia, formas, ícones e movimento

**Tipografia:**

- **Fredoka** no logo, nos títulos grandes, nas saudações e nas falas da Paçoca. É arredondada como o mascote.
- **Inter** em toda a interface e nos números, com algarismos tabulares (tnum) para os valores ficarem alinhados nas listas.
- O saldo principal aparece em Inter SemiBold, grande, com os centavos menores: R$ 1.234,56.
- As duas fontes são gratuitas (licença OFL) e estão no Google Fonts.

**Formas:**

- Cantos bem arredondados: cartões com 20 px, chips com 12 px e botões em formato de pílula.
- Espaçamento em múltiplos de 4 (4, 8, 12, 16, 24, 32 e 48), com margem lateral de 16 px no celular.
- Pouca sombra: os cartões se separam pela cor da superfície e por uma borda suave.

**As pintas como motivo:** as três pintas da paca são o elemento gráfico da marca. Aparecem no ícone, no carregamento (três pintas pulsando), no modo esconder valores (R$ •••) e no indicador de passos do guia inicial.

**Ícones:** Phosphor Icons, no estilo regular nas telas e duotone nas ilustrações e nos estados vazios. Cada categoria tem um ícone dentro de um círculo com a cor dela.

**Movimento:**

- Microinterações de 150 a 250 ms e transições de 300 a 400 ms, com as curvas padrão do Material.
- Ao abrir o app, o valor de "Sobrou este mês" sobe contando até o número final.
- Meta batida solta uma chuva curta de moedinhas.
- Vibração leve ao salvar um lançamento.
- Tudo respeita a opção de reduzir movimento do sistema.

## Logo e ícone do app

- **Logo:** "Grana PaCá" escrito em Fredoka, na cor Caramelo. O acento do Á é desenhado como uma moedinha caindo: o "pra cá" em forma de desenho.
- **Ícone do app:** a cabeça da Paçoca de perfil sobre fundo Caramelo, com as três pintas creme em linha. Precisa ser legível em 48 px e ter versão monocromática para os ícones temáticos do Android.
- **Variações:** colorida, monocromática, sobre fundo escuro e só o símbolo, com área de respiro e tamanho mínimo definidos.

## Navegação e telas

**Navegação:**

- **Celular:** barra inferior com Início, Extrato, um botão central "+", Gastos e Paçoca (o chat). Perfil e configurações ficam no avatar, no canto superior.
- **Desktop e tablet:** a mesma navegação vira um trilho lateral, e as listas abrem o detalhe ao lado, em duas colunas.
- **Botão "+":** abre gasto em dinheiro, foto de nota fiscal, leitura do QR Code da NFC-e e importação de extrato.

**Tela inicial:** responde "como estou este mês?" num relance.

1. Saudação e o botão de esconder valores.
2. Destaque **"Sobrou este mês"** (receitas menos gastos) em número grande, com uma barra do orçamento usado e uma frase curta da Paçoca.
3. Cartões dos bancos, cada um com a faixa da cor do banco, o saldo e a fatura atual, mais o cartão de Dinheiro físico.
4. Últimas transações.
5. Um cartão "A Paçoca percebeu", com o alerta ou a dica mais importante.

**Guia inicial:** parece uma conversa. A Paçoca faz uma pergunta por tela, e a pessoa responde tocando em chips (dá para marcar vários). O progresso aparece como pegadas de paca. A última tela mostra as regras geradas, cada uma com a explicação e um botão para desligar. A calibragem com dados reais usa cartões de estabelecimento com três botões: Essencial, Importante e Flexível.

**Demais telas:**

- **Extrato:** cada item tem o ícone da categoria, o nome limpo do estabelecimento, o marcador de essencialidade, o logo pequeno do banco e o valor alinhado à direita. Deslizar o item corrige a categoria ou anexa um comprovante.
- **Detalhe da transação:** valor, estabelecimento, data, banco e forma de pagamento. Abaixo, categoria e essencialidade editáveis, justificativa, comprovantes em miniatura, divisão em partes e o histórico de alterações em linha do tempo.
- **Correção:** folha inferior com a grade de categorias, a escala de essencialidade, o campo de justificativa e a pergunta "vale para todas as semelhantes?".
- **Gastos:** seletor de mês e filtros por banco e forma de pagamento. Primeiro a rosca, com o total no centro, depois o ranking em barras. Os outros gráficos ficam abaixo, em cartões.
- **Chat com a Paçoca:** sugestões de perguntas em chips. As respostas trazem cartões com números, o período e o link "ver transações". Um aviso discreto mostra o que vai para a IA.
- **Nota fiscal:** câmera com moldura para o QR Code, a Paçoca com lupa durante a leitura e, no fim, a lista de itens com categoria e essencialidade.
- **Gasto em dinheiro:** teclado numérico grande, categorias recentes em chips e foto opcional. Salva em dois toques e funciona offline.
- **Planejamento:** orçamentos por categoria em barras de progresso, e metas com quanto falta e o prazo.
- **Alertas, conexões e configurações:** status de cada banco e de quando o consentimento vence, provedores de IA, exportação e uma zona de perigo com "apagar tudo".
- **Modo demo:** faixa fixa "Modo demo · dados fictícios" e uma pessoa fictícia com dados sintéticos.

## Princípios de UX e acessibilidade

- **Uma pergunta por tela:** cada tela responde a uma dúvida principal e tem uma ação principal.
- **Números em primeiro lugar:** valores grandes, alinhados e no formato brasileiro (R$ 1.234,56). Datas relativas quando ajudam ("hoje", "ontem").
- **Esconder valores em todo lugar:** com o modo ligado, os valores viram R$ ••• e os gráficos mostram só percentuais.
- **Material 3 com cara própria:** a base é o Material 3 do Flutter, mas com os tokens desta marca, para não parecer app genérico. Os layouts se adaptam a celular, tablet e desktop.
- **Contraste:** texto com pelo menos 4,5:1 e componentes com pelo menos 3:1, nos dois temas.
- **Cor nunca sozinha:** categorias, essencialidade e alertas sempre têm nome, ícone ou rótulo junto da cor.
- **Leitores de tela:** cada gráfico tem um resumo em texto ("Alimentação, 32% dos gastos") e cada ícone tem rótulo.
- **Texto ampliável** até 200% sem quebrar o layout, e áreas de toque de pelo menos 48 dp.
- **Tema escuro de primeira classe:** a paca é noturna, e muita gente confere as contas à noite.
- **Confiança:** um cadeado e a frase "seus dados ficam no seu servidor" no guia inicial e nas telas de privacidade. O conteúdo do app fica oculto no seletor de apps.

## Entregáveis

Na ordem em que viraram as 12 partes do [índice](README.md):

1. **Revisão das decisões:** o que manteve, o que mudou e por quê.
2. **Design tokens:** cores (claro e escuro), tipografia, espaçamento, raios, sombras e movimento, em JSON e em Dart (ColorScheme do Material 3, ThemeData e ThemeExtension para os tokens próprios).
3. **Mascote:** folha de modelo da Paçoca (frente, perfil e costas), as 8 expressões, as regras de uso e a especificação da máquina de estados no Rive.
4. **Logo e ícone:** todas as variações, com área de respiro e tamanhos mínimos.
5. **Biblioteca de componentes, com estados:** botões, chips, cartão de banco, item de transação, marcador de essencialidade, campos, folhas inferiores, gráficos, avisos, estados vazios e faixa do modo demo.
6. **Telas:** todas as da seção Navegação e telas, nos temas claro e escuro. A tela inicial, o extrato e os gráficos também em desktop.
7. **Fluxos:** guia inicial, correção de lançamento, nota fiscal, gasto em dinheiro e chat.
8. **Guia de microcopy:** as regras do tom de voz e as mensagens de cada tela.
9. **Checagem de acessibilidade:** tabela de contraste e lista do que foi verificado.
10. **Passagem para o Flutter:** estrutura de widgets sugerida e os pacotes google_fonts, phosphor_flutter, rive, fl_chart e flutter_heatmap_calendar. Marque o que eu preciso conferir na documentação de cada um.

Os textos, as telas e as imagens do design usam português do Brasil e os nomes dos tokens deste documento.
