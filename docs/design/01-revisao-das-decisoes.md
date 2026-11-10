# Parte 1: Revisão das decisões

O briefing de identidade visual fica quase todo como está. Conceito, Paçoca, paleta da interface, tipografia, formas e princípios de acessibilidade seguem iguais. Mudam 17 pontos, por três motivos: as respostas às perguntas iniciais, regras do plano do projeto que o briefing não cobria e medições de cor que reprovaram a paleta dos gráficos.

- **Data:** 2026-11-10
- **Base:** briefing de identidade visual, respostas às cinco perguntas iniciais e o plano do projeto.
- **Marcas:** [Suposição] é decisão tomada aqui sem confirmação. [Conferir: fonte] é fato externo a validar na documentação oficial antes de implementar.

## O que fica

| Área | Decisão mantida | O que foi conferido |
|---|---|---|
| Conceito | A paca que junta tudo: o app é a toca da Paçoca, quente e brasileiro, longe do azul de banco. | — |
| Regra de ouro e tom | Diversão nos detalhes, clareza no que importa. Um amigo que entende de dinheiro. "Flexível", nunca "Supérfluo". No máximo uma brincadeira por tela, e nenhuma em erro que envolve dinheiro. | — |
| Paçoca | Aparência, expressões e onde ela não aparece. | Ganha uma expressão (mudança 13). |
| Paleta da interface | Os 11 tokens, nos temas claro e escuro. | 34 pares medidos: todos os textos passam de 4,5:1 e todas as bordas de 3:1. Milho só funciona como fundo com texto Cacau por cima (7,71:1); sozinho, como ícone ou borda sobre branco, fica em 2,14:1. |
| Dinheiro | Gasto na cor do texto, com "−". Receita em Mata, com "+". Vermelho só para alerta. | — |
| Essencialidade | Escala em tons de Caramelo, nunca verde e vermelho. | A escala passa no validador de cores nos dois temas. Flexível fica no limite (3,03:1 sobre a Superfície) e cai para 2,8:1 sobre o fundo Paçoca, então o marcador aparece só em cartões e folhas. |
| Tipografia | Fredoka na marca, nos títulos e nas falas da Paçoca. Inter na interface, com algarismos tabulares. Saldo em Inter SemiBold com centavos menores. | Muda a forma de carregar as fontes (mudança 11). |
| Formas | Cartões com 20 px, chips com 12 px, botões em pílula, espaçamento em múltiplos de 4, margem de 16 px no celular e pouca sombra. | — |
| Pintas | Ícone, carregamento, R$ ••• e indicador de passos. | Ganham um uso novo (mudança 7). |
| Ícones | Phosphor regular nas telas e duotone nas ilustrações. | [Conferir: pub.dev/packages/phosphor_flutter] na Parte 12. |
| Movimento | 150 a 250 ms nas microinterações, 300 a 400 ms nas transições, contagem do "Sobrou este mês", chuva de moedinhas, vibração ao salvar e respeito a "reduzir movimento". | A contagem só roda com os valores visíveis e sem "reduzir movimento". O leitor de tela recebe o valor final, nunca os números intermediários. |
| Navegação | Barra inferior no celular e trilho lateral no desktop, com o detalhe ao lado da lista. | Ajustes na mudança 10. |
| UX e acessibilidade | Todos os princípios do briefing. | A Parte 11 traz a tabela completa. |

## O que muda

### 1. O primeiro acesso vira a "Trilha até a toca"

O primeiro acesso é uma caminhada pela mata, do fim de tarde até a noite. Cada etapa leva a Paçoca um trecho adiante na trilha, e a última chega à toca, que é a tela inicial. Pacas são noturnas: a noite é a hora de chegar em casa.

- **Ritmo de Duolingo:** uma pergunta por tela, chips grandes, a Paçoca reage a cada resposta numa frase curta, as pegadas mostram o progresso e a chegada tem comemoração.
- **Etapas:** boas-vindas, servidor, entrar, código do autenticador, ocupação, casa, transporte, revisão das regras, conectar bancos e chegada à toca.
- **Cenário de fundo:** ilustração em camadas, com paralaxe leve entre as etapas. Formulários, números e botões ficam num cartão de Superfície, sérios como no resto do app. Com "reduzir movimento", o cenário troca de quadro sem deslizar.
- **Entrar:** campos com dicas de preenchimento automático, para o gerenciador de senhas funcionar, e erro em linguagem simples.

**Por quê:** é o pedido da resposta 2, um primeiro acesso bonito e funcional, como estar na floresta. A trilha dá sentido ao progresso, e terminar na toca amarra o conceito do app.

**Onde entra:** Partes 3, 6 e 9.

### 2. Nada de gamificação que cobra

Do Duolingo fica o ritmo e o carinho. Não entram ofensiva de dias seguidos, pontos, vidas ou ranking.

**Por quê:** num app de dinheiro, um contador de dias vira culpa ("você perdeu a ofensiva"), e o tom de voz proíbe culpa.

### 3. A demo passa pelo primeiro acesso inteiro, sem pedir credencial

Na demo, as etapas de servidor, entrar e autenticador aparecem preenchidas com dados fictícios e bloqueadas, com o botão "Continuar". Do guia em diante, as perguntas são de verdade, e a revisão mostra as regras que o perfil geraria. Os dados da demo continuam os da pessoa fictícia [Suposição: aplicar as regras do guia aos dados da demo depende do ADR-008].

**Por quê:** as respostas 2 e 5 pedem que a demo mostre o primeiro acesso e o guia. Só que a demo é uma página pública sem backend (ADR-008). Pedir senha ali não valida nada e ensina a digitar senha em qualquer site.

### 4. O guia tem até 5 telas e "Pular por agora"

Ocupação (várias ao mesmo tempo, com "Outro" descrito em texto), casa, transporte e revisão das regras. A calibragem com os estabelecimentos reais é opcional e aparece depois que os bancos sincronizam, como um cartão no Início.

"Pular por agora" fica visível em cada tela do guia, e o guia pode ser refeito nas configurações. Servidor, entrar e autenticador não têm essa opção.

**Por quê:** é regra do plano. Um guia que não deixa pular perde quem já sabe o que quer.

### 5. Conectar bancos é uma ponte para o Meu Pluggy

A tela explica em três passos que a conexão acontece no site meu.pluggy.ai, abre o site num botão e volta com "Já conectei". Cada banco aparece no app quando o servidor sincroniza.

"Puxar para atualizar" sincroniza o app com o seu servidor e mostra quando o banco atualizou pela última vez. A Paçoca continua mergulhando, mas a frase deixa claro que o banco se atualiza sozinho uma vez por dia.

**Por quê:** no modo Meu Pluggy, conexão e renovação acontecem em meu.pluggy.ai, e a atualização é automática a cada 24 horas, sem como forçar pela API. São premissas do plano [Conferir: docs.pluggy.ai].

### 6. Categorias em 8 grupos e Outros

Alimentação, Moradia, Transporte, Saúde, Lazer, Compras, Educação, Assinaturas e serviços, e Outros. Cada grupo tem uma cor fixa nos gráficos. As categorias filhas herdam a cor do grupo e têm ícone próprio. Receitas e transferências ficam fora da rosca.

**Por quê:** é a resposta 3. Oito cores é o máximo que a rosca separa com segurança (mudança 8).

### 7. Marcador de essencialidade com pintas

| Nível | Marcador |
|---|---|
| Essencial | ●●● |
| Importante | ●●○ |
| Flexível | ●○○ |

O marcador vem sempre com o nome do nível. Onde o nome não cabe, como na célula do calendário e na legenda compacta, ficam as pintas, e o nome vai para o rótulo de acessibilidade.

**Por quê:** os três tons de Caramelo são parecidos entre si e quase somem com daltonismo ou com o brilho da tela baixo. A quantidade de pintas lê a escala sem depender da cor e usa o motivo da marca.

### 8. A paleta dos gráficos muda

O validador de cores reprovou a paleta do briefing. Caramelo (#C26A2A) e Urucum (#D0503A) ficam a 6,5 de distância para visão normal, quando o mínimo é 15, e a 2,0 com deuteranopia, quando o mínimo é 8. O Igarapé (#1D8A8A) tem pouca saturação e lê como cinza.

Paleta nova do tema claro, validada em todos os pares:

| Cor | Antes | Depois |
|---|---|---|
| Caramelo | #C26A2A | #8B3E05 |
| Manga (substitui Urucum) | #D0503A | #FE903C |
| Milho | #D99A1E | #A78511 |
| Mata | #2E8B5E | #267E4E |
| Igarapé | #1D8A8A | #02A8AA |
| Rio | #2F7FC1 | #277BD0 |
| Jabuticaba | #7B55B0 | #7F4B9D |
| Goiaba | #D24F7A | #D54573 |
| Outros | #A3958A | #A3958A |

Resultado no tema claro, sobre a Superfície e sobre o fundo Paçoca:

| Checagem | Mínimo | Pior par |
|---|---|---|
| Visão normal | 15 | 15,6 (Rio × Igarapé) |
| Protanopia e deuteranopia | 8 | 8,3 (Mata × Caramelo) |
| Tritanopia | — | 7,5 |

- **Urucum sai das categorias:** vermelho fica só para alerta, como o próprio briefing manda. Manga, uma fruta laranja, ocupa o lugar.
- **Rótulo obrigatório:** Manga (2,27:1) e Igarapé (2,92:1) ficam abaixo de 3:1 contra o branco, como o Milho já ficava no briefing. Gráfico com essas cores sempre tem rótulo visível ou o ranking com os nomes logo abaixo.
- **Tema escuro:** dentro da faixa de luminosidade do escuro, oito cores chegam no máximo a 13,6 no par mais próximo. A Parte 2 define os tons escuros com três regras: rosca em ordem fixa de categorias, rótulo direto nas fatias e 2 px de separação entre elas.
- **A cor segue a categoria,** nunca a posição no ranking. A associação de cada grupo a uma cor sai na Parte 2.

**Por quê:** medido com o validador da skill de visualização de dados, que usa o espaço de cor OKLab e a simulação de daltonismo de Machado (2009).

### 9. A rosca mostra até 5 categorias e Outros

Tocar numa fatia, numa barra ou num dia abre as transações correspondentes. A regra 50/30/20 usa o agrupamento do plano: Necessidades é Essencial, Desejos é Importante mais Flexível, e Poupança é o que sobrou do mês, sem transferências entre contas próprias.

**Por quê:** são regras do plano. A resposta 4 confirmou a proposta anterior, que juntava Essencial e Importante. Se preferir aquela, muda só o agrupamento desse gráfico.

### 10. Navegação: "+" é ação, Planejamento fica em Gastos e alertas no sino

- **Barra:** 4 destinos (Início, Extrato, Gastos e Paçoca) e o "+" no meio, que abre a folha de ações e nunca fica selecionado. No desktop, o "+" vira o botão de ação no topo do trilho.
- **Gastos:** duas abas, "Análise" (gráficos) e "Planejamento" (orçamentos, metas e projeções).
- **Alertas:** sino no topo do Início, com contador.

**Por quê:** o briefing não dava lugar a Planejamento nem a Alertas. Orçamento responde "quanto ainda posso gastar?", que é uma pergunta de Gastos.

### 11. Fontes dentro do app

Fredoka e Inter vão empacotadas no app, com a licença OFL ao lado dos arquivos. O app nunca baixa fonte da internet ao abrir. Com o pacote google_fonts, isso é `GoogleFonts.config.allowRuntimeFetching = false` [Conferir: pub.dev/packages/google_fonts].

**Por quê:** privacidade, porque abrir o app não avisa ninguém de fora; funcionamento offline, que o plano exige; e texto certo já na primeira abertura.

### 12. Logo e cor de cada banco vêm do seu servidor

O backend lê a cor e o logo do conector na Pluggy, guarda uma cópia e entrega ao app [Conferir: campos do conector em docs.pluggy.ai].

**Por quê:** no plano, só o backend fala com a Pluggy. Se o app baixasse o logo direto, cada abertura contaria a um serviço de fora quais bancos você usa.

### 13. Paçoca com 9 expressões e um quadro parado de cada

A trilha do primeiro acesso pede uma expressão nova: andando. A máquina de estados do Rive cobre as 9; o briefing listava 5 estados para 8 expressões. Cada expressão também existe como SVG parado [Conferir: entradas da máquina de estados no pacote rive para Flutter].

**Por quê:** o quadro parado serve para "reduzir movimento", para os testes de golden e para a demo web carregar rápido.

### 14. Ícone do app com as variantes de cada sistema

No Android, ícone adaptativo com a camada monocromática que o briefing já pede. No iOS, as versões que o sistema usa em cada aparência: claro, escuro e tingido [Conferir: Apple Human Interface Guidelines, App icons, inclusive os ícones em camadas do iOS 26].

**Por quê:** sem essas versões, o sistema escurece ou tinge o ícone por conta própria, e a Paçoca pode sumir no fundo.

### 15. Nome escrito "GranaPaCá", inclusive no logo

O logo continua em Fredoka, Caramelo, com o acento do Á desenhado como moedinha. O P e o C maiúsculos marcam as duas palavras.

**Por quê:** é a grafia do repositório, do README e do plano. Numa palavra só, o nome também não quebra em duas linhas sob o ícone na tela do celular. Se preferir "Grana PaCá" com espaço, só o logo muda.

### 16. Mapa de calor com widget próprio

**Por quê:** o plano já propõe isso no ADR-006, para ter rótulo de acessibilidade por dia, o modo esconder valores e os tokens da marca. O pacote flutter_heatmap_calendar sai da lista da Parte 12.

### 17. Telas que vêm do plano

Entram nas Partes 7 e 8, sem mudar o número de partes:

- fila de revisão das categorias que a IA classificou com pouca confiança;
- consentimento para restrições alimentares, pedido só na primeira nota fiscal;
- alerta escrito em linguagem natural ("me avise quando o delivery passar de R$ 300");
- marcar despesa como atípica, para ela sair das projeções;
- sessões por aparelho, com opção de desconectar;
- tags;
- provedores de IA com a sua própria chave;
- comparação mês a mês;
- correção de várias transações de uma vez no extrato.

## Pendências

- **Primeira conta num servidor novo:** o plano ainda não diz como a conta do dono nasce. Isso define a variação "criar conta" da etapa Entrar [Conferir: Parte 8 do plano, Segurança].
- **Endereço do servidor por QR Code [Proposta]:** digitar o endereço do Tailscale no celular é o passo mais chato do primeiro acesso. Se o servidor mostrar um QR Code na instalação, o app lê com a câmera, e digitar fica como alternativa. Depende do backend (Partes 6 e 10 do plano).

## Próximo

Parte 2: design tokens em JSON e Dart, com as cores dos gráficos no tema escuro e a associação de cada grupo a uma cor.
