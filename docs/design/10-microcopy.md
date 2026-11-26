# Parte 10: Guia de microcopy

As regras do tom de voz e os textos de cada situação do app. Quem escreve uma frase nova começa por aqui, e quem implementa copia daqui.

- **Data:** 2026-11-26
- **Para regenerar:** não há gerador. Esta parte é só texto.
- **De onde vem cada coisa:** o tom de voz do [briefing](00-briefing.md), as decisões da [Parte 1](01-revisao-das-decisoes.md), os componentes da [Parte 5](05-componentes.md), as telas das Partes [6](06-telas-a.md), [7](07-telas-b.md) e [8](08-telas-c.md) e os fluxos da [Parte 9](09-fluxos.md).
- **Marcas:** [Suposição] é texto proposto aqui, sem teste com pessoas. [Conferir: fonte] é fato externo a validar.
- **Idioma:** português do Brasil, com "você". O código e as chaves de tradução ficam em inglês.
- **Dados:** fictícios, como em todo o repositório.

## Voz

**Um amigo que entende de dinheiro, não um gerente de banco.**

| Princípio | Como fica | Evite |
|---|---|---|
| Fala com você | "Você já conectou o Banco Ipê." | "O usuário já conectou." |
| Frase curta, palavra do dia a dia | "Não deu para salvar." | "Ocorreu uma falha na persistência." |
| Termo técnico vem explicado | "Open Finance, o jeito oficial de seu banco compartilhar seus dados com você." | Sigla solta, como OFX ou NFC-e, sem uma frase de apoio na primeira vez. |
| Nunca julga | "Flexível." | "Supérfluo", "gastão", "você exagerou". |
| Sem culpa | "O delivery passou de R$ 300 este mês. Quer ver os pedidos?" | "Você gastou demais com delivery!" |
| Notícia ruim com calma e próximo passo | "A fatura veio maior que a média. Bora ver o que pesou?" | "Atenção! Fatura alta!" |
| Comemora com medida | "Meta batida! A Paçoca está dando pulinhos." | Confete e três pontos de exclamação. |
| Diz o que vai acontecer | "Desconectar o Banco Ipê?" e o botão "Desconectar". | "Tem certeza?" e os botões "Sim" e "Não". |

**Regras de ouro:**

1. **Uma brincadeira por tela, no máximo.** A graça mora nos estados vazios, nas comemorações e nas falas da Paçoca. Navegação, números e botões são diretos.
2. **Erro que envolve dinheiro não tem piada.** Isso vale para erro ao salvar, divergência de saldo, sincronização que falhou, divisão que não fecha e qualquer erro de valor. Nessas telas, a Paçoca não aparece brincando, e a frase fala o que aconteceu, que os dados estão seguros e qual é o próximo passo.
3. **Pontuação sóbria.** Ponto de exclamação só em comemoração, e um por frase. Nunca em erro ou alerta. [Suposição]
4. **Nada de "Ops", "Eita" ou "Ihh" em erro.** Esses são para o estado vazio e para a comemoração, quando cabem.
5. **Botão é verbo, e diz o que acontece:** "Conectar banco", "Salvar correção", "Apagar tudo". Nunca "OK" ou "Confirmar" sozinho.
6. **Título de diálogo é a pergunta,** e os botões respondem com o verbo: "Desconectar" e "Cancelar".
7. **Sem pressão.** Nada de "Só hoje", "Não perca" ou contagem de dias seguidos. Também não há ranking, pontos ou vidas ([Parte 1](01-revisao-das-decisoes.md), mudança 2).
8. **O app não se desculpa duas vezes.** "Desculpe" só aparece se o erro foi culpa do app, e uma vez só. [Suposição]
9. **Emoji fica fora da interface.** O personagem é a Paçoca, não um conjunto de carinhas. [Suposição]

## Formatos

| O quê | Formato | Exemplo | Leitor de tela |
|---|---|---|---|
| Dinheiro | `R$` e espaço, ponto nos milhares, vírgula nos centavos | R$ 1.284,90 | "1.284 reais e 90 centavos" |
| Saída | Sinal de menos colado no `R$`, na cor do texto | -R$ 187,43 | "menos 187 reais e 43 centavos" |
| Entrada | Sinal de mais, em Mata | +R$ 6.200,00 | "mais 6.200 reais" |
| Valor oculto | `R$` e três pintas | R$ ••• | "valor oculto" |
| Percentual | Número inteiro e `%`, sem espaço | 12% | "12 por cento" |
| Data | Relativa quando ajuda, depois por extenso curto | hoje, ontem, 5 de nov. | "hoje", "ontem", "5 de novembro" |
| Período | Mês por extenso ou intervalo | novembro, 1 a 26 de nov. | "de 1 a 26 de novembro" |
| Hora | 24 horas, sem zero à esquerda desnecessário | 18:40 | "18 e 40" |

- Valores sempre com algarismos tabulares (`tnum`), para alinhar nas listas.
- Saída tem sinal de menos em toda parte: lista, detalhe, cartão do chat e gráfico com rótulo de valor. Receita tem sinal de mais.
- Nome de banco, estabelecimento e categoria é cortado com reticências se não couber. O valor nunca é cortado.
- Os níveis de essencialidade se chamam **Essencial**, **Importante** e **Flexível**, sempre com as pintas ●●●, ●●○ e ●○○. Nunca "Supérfluo".

## Rótulos fixos

Estes nomes não variam de tela para tela.

| Rótulo | Onde | Observação |
|---|---|---|
| Início, Extrato, Gastos, Paçoca | Barra e trilho | Sempre visíveis, não só o selecionado. |
| Gasto em dinheiro, Foto da nota fiscal, QR Code da NFC-e, Importar extrato | Folha do botão "+" | Nessa ordem. |
| Sobrou este mês | Início | Receitas menos gastos. |
| Para onde foi | Gastos e Início no desktop | Rosca por categoria. |
| Análise, Planejamento | Abas de Gastos | Duas abas. |
| A revisar | Fila: o Extrato com a chave "Só lançamentos a revisar" | O selo no item se chama "Revisar". |
| Dinheiro físico | Seção e cartão | Nunca "Carteira" ou "Caixa". |
| Dado do banco | Detalhe do lançamento | Dado original, só leitura, com o selo "Original preservado". |
| Modo demo · dados fictícios | Faixa fixa da demo | Texto igual em toda tela. |
| Pergunte pra Paçoca | Título do chat | |
| Pular por agora | Guia | Visível em cada tela do guia. |

## Estados vazios

Todo estado vazio segue o padrão `EstadoVazio`: a Paçoca, uma frase e a próxima ação. A pose é a que a situação pede, e nunca há mais de uma brincadeira.

| Tela | Pose | Título | Texto | Ação |
|---|---|---|---|---|
| Início, primeiro dia | Dormindo | Seus bancos estão a caminho | A primeira sincronização leva alguns minutos. Eu aviso quando chegar. | Conectar outro banco |
| Início, "Enquanto isso" | — | Enquanto isso | Registre um gasto em dinheiro ou leia uma nota fiscal pelo botão + aqui embaixo. | O botão + |
| Extrato, sem banco | Acenando | Nada por aqui ainda | Conecte um banco e traga sua grana pra cá. | Conectar banco |
| Extrato, filtro sem resultado | — | Nada com esses filtros | Tente tirar um filtro ou mudar o período. | Limpar filtros |
| Extrato, busca sem resultado | — | Não achei "padaria" | Confira a escrita ou tente outra palavra. | Limpar busca |
| Extrato, "Só lançamentos a revisar" vazio | Comemorando | Tudo revisado | Quando chegar algo que eu não tenha certeza, aparece aqui. | Ver extrato |
| Gastos, mês sem dados | Dormindo | Sem gastos em novembro ainda | Assim que chegar um lançamento, a rosca aparece aqui. | Ver outro mês |
| Gastos, menos de 2 meses de histórico | — | Ainda faltam meses para comparar | A evolução mostra os meses que existem. | — |
| Planejamento, sem orçamento | Pensando | Quanto você quer gastar com mercado? | Um orçamento mostra quanto ainda dá para gastar no mês. | Criar o primeiro orçamento |
| Planejamento, sem metas | Acenando | Que tal uma meta? | Guardar para uma viagem ou uma reserva. Você escolhe o valor e o prazo. | Criar meta |
| Alertas, sem alertas | Dormindo | Tudo calmo por aqui | Eu aviso quando algo precisar de você. | Criar alerta |
| Chat, sem histórico | Acenando | Oi, Bia! Pergunte sobre seus gastos. | Eu respondo com os números do app. | Chips de perguntas prontas |
| Chat, sem IA | Pensando | Sem IA · perguntas prontas | A IA está desligada. Use as perguntas prontas: eu calculo tudo aqui, sem enviar nada para fora. | Configurar IA |
| Dinheiro físico, sem gastos | — | Nenhum gasto em dinheiro | Pagou com notas e moedas? Registre em dois toques. | Registrar gasto |
| Comprovantes, sem anexos | — | Nenhum comprovante | Guarde a foto ou o PDF da nota junto do lançamento. | Anexar comprovante |
| Contas conectadas, vazio | Acenando | Nenhuma conta conectada | A conexão acontece no Meu Pluggy, sem digitar senha de banco aqui. | Abrir o Meu Pluggy |
| Sessões por aparelho | — | Só este aparelho | Se entrar em outro, ele aparece aqui para você desconectar. | — |

[Suposição] As poses são sugestões. A regra firme é a [Parte 3](03-mascote.md): uma vez por tela e nunca na lista de lançamentos.

## Offline e sincronização

| Situação | Texto | Observação |
|---|---|---|
| Sem internet, modo servidor | A Paçoca cochilou. Assim que a internet voltar, ela sincroniza. | Faixa discreta com a Paçoca dormindo. Esta é a brincadeira da tela. |
| Sem internet, ação que precisa de rede | Precisa de internet. Conecte e tente de novo. | O botão fica desabilitado, e a frase diz o motivo. |
| Modo local | Tudo fica no seu celular e funciona sem internet. | Sem faixa de offline, porque não é falta de nada. |
| Última sincronização | Sincronizado hoje às 18:40 | Em cada conta conectada. Ontem: "Sincronizado ontem às 18:40". |
| Sincronizando | Sincronizando o Banco Ipê | As três pintas pulsam. Com "reduzir movimento", ficam paradas. |
| Puxar para atualizar | Atualizando com o seu servidor | A Paçoca mergulha. Depois: "O Banco Ipê se atualiza sozinho uma vez por dia. Última vez: hoje, 06:10." |
| Servidor sem resposta | Não consegui falar com o seu servidor. O que já veio continua aqui. | Com o botão "Tentar de novo". Sem piada: pode ser dinheiro que ainda não chegou. |
| Falha de sincronização do banco | O Banco Ipê não atualizou hoje. Seus dados estão seguros. | Com o botão "Ver conexão". |
| Salvo no aparelho | Salvo no aparelho. Vai para o servidor quando a internet voltar. | Selo no item, para gasto em dinheiro feito offline. |
| Voltou a conexão | Sincronizado. 3 lançamentos novos. | Aviso rápido, 4 segundos. |
| Chat sem internet | O chat com IA precisa de internet. As perguntas prontas continuam aqui. | Os chips seguem ativos. |

**Status de cada conexão** (Configurações, Bancos e consentimento):

| Status | Texto | Sinal | Ação |
|---|---|---|---|
| Ativo | Consentimento até 12 mar 2027 | Visto | — |
| Vencendo | Vence em 7 dias | Selo em Milho, com texto Cacau | Renovar |
| Vencida | Conexão vencida | Ícone de alerta | Renovar no Meu Pluggy |
| Sincronizando | Sincronizando | Pintas pulsando | — |

## Avisos rápidos

O aviso rápido (`SnackBar`) confirma o que acabou de acontecer, some em 4 segundos e pode ter "Desfazer". Não carrega erro importante: erro vai na própria tela.

| Quando | Texto | Ação |
|---|---|---|
| Depois de salvar uma correção | Correção salva | Desfazer |
| Depois de salvar um gasto em dinheiro | Gasto salvo | Desfazer [Suposição] |
| Exportação em andamento | Preparando a sua cópia… | Compartilhar, quando termina |
| Voltou a conexão | Sincronizado. 3 lançamentos novos. | — |

## Alertas

Alerta é a única hora em que o Urucum aparece, e a Paçoca fica **preocupada, sem drama**. Cada alerta diz o quê, quanto e qual é o próximo passo.

| Situação | Título | Texto | Ação |
|---|---|---|---|
| Conexão vencendo | Conexão vencendo | A conexão com o Banco Jatobá vence em 7 dias. Renove para não perder nada. | Renovar no Meu Pluggy |
| Conexão vencida | Conexão vencida | A conexão com o Banco Jatobá venceu. O que já veio continua aqui. Renove para voltar a atualizar. | Renovar no Meu Pluggy |
| Fatura alta | Fatura acima da média | R$ 1.130,55 contra média de R$ 940,00. Bora ver o que pesou? | Ver compras |
| Categoria acima do limite combinado | Delivery passou de R$ 300 | Foram R$ 342,80 este mês. Quer ver os pedidos? | Ver pedidos |
| Orçamento chegando no limite | Alimentação chegou a 87% do orçamento | R$ 960,00 de R$ 1.100,00. Restam R$ 140,00. | Ver orçamento |
| Orçamento estourado | Transporte passou do orçamento | R$ 520,00 de R$ 450,00. Passou R$ 70,00. Dá para ajustar o limite ou seguir assim. | Ajustar orçamento |
| Gasto fora do padrão | Um gasto de -R$ 890,00 chamou atenção | Está bem acima do seu padrão em Compras. Marque como atípico se foi pontual. | Ver lançamento |
| Lançamentos para revisar | 4 lançamentos esperando revisão | Eu não tinha certeza da categoria. Leva um minuto. | Ver lançamentos |
| Meta batida | Meta batida! | Você completou a meta de outubro. A Paçoca está dando pulinhos. | Ver metas |

Conexão vencendo, fatura acima da média, delivery, orçamento estourado e meta batida aparecem nas telas da [Parte 8](08-telas-c.md). Os outros são propostas desta parte [Suposição].

**Regras:**

- **Sem culpa:** o texto descreve o fato e oferece o passo. Não diz "você deveria".
- **Orçamento estourado não é erro.** A barra vira Urucum e ganha o ícone de alerta com a frase "Passou R$ 70,00". A cor nunca é o único sinal, e o texto não faz vergonha.
- **Meta batida é a comemoração do app.** É onde cabe a chuva de moedas e a brincadeira, uma vez por tela.
- **Alerta escrito em linguagem natural:** o campo "Escreva do seu jeito" aceita "Me avise quando o delivery passar de R$ 300 por mês". O app mostra "Entendi assim" em quatro linhas (onde, quanto, período e como avisar), cada uma com o lápis para ajustar, antes de "Criar alerta". Só o texto da frase vai para a IA.
- **Contador do sino:** "Alertas: 2 novos". Passa de 9, mostra "9+".

## Privacidade

### Valores ocultos

| Onde | Texto |
|---|---|
| Chave em Configurações, Privacidade | "Esconder valores", com o apoio "Mostra R$ ••• em todo o app" |
| Olho no topo, ao esconder | "Esconder valores" |
| Olho no topo, ao mostrar | "Mostrar valores" |
| Valor na tela | R$ ••• |
| Leitor de tela | "valor oculto" |
| Gráficos | Só percentuais: "Alimentação, 20% dos gastos". |
| Extrato | A busca por valor fica desligada. |
| Cartão do chat | "Mercado · 1 a 26 de novembro: R$ •••, 12% abaixo de outubro." |
| Chave "Tela oculta no seletor" | "Fica em branco ao trocar de app" |

O modo vale em todo lugar de uma vez, e o app lembra a escolha.

### O que vai para a IA

A regra é a [Parte 9](09-fluxos.md), Fluxo 5. Os textos:

| Onde | Texto |
|---|---|
| Aviso discreto no chat | Só totais e categorias vão para a IA. (com o link "Saiba mais") |
| Título da folha | O que vai para a IA |
| Subtítulo | Só o necessário para responder. Você troca o provedor quando quiser. |
| Primeira lista, "Vai junto com a sua pergunta" | Totais por categoria e período. O rótulo de essencialidade. A sua pergunta, em texto. |
| Segunda lista, "Fica só no seu servidor" | Nome do estabelecimento e descrição. Banco, conta e número do cartão. Fotos e PDFs das notas fiscais. Seu nome e e-mail. |
| Chave "Enviar só percentuais" | Os valores em reais não saem daqui. |
| Botões | Entendi, Trocar provedor de IA |
| Provedor | Minha própria chave, "Guardada só neste aparelho" |
| Sem IA | A IA está desligada. Use as perguntas prontas: eu calculo tudo aqui, sem enviar nada para fora. |
| Leitor de tela | "Aviso de privacidade: o que vai para a IA" |

No modo local, "servidor" na segunda lista vira "aparelho" [Suposição].

### Consentimento e confiança

| Situação | Título | Texto | Botões |
|---|---|---|---|
| Restrições alimentares, na primeira NFC-e | Posso ler os itens da nota? | Os itens podem mostrar restrições alimentares, que são dados de saúde. Só uso para escolher a categoria de cada item. Fica no seu servidor. Dá para mudar em Configurações > Privacidade. | Permitir leitura dos itens, Agora não, usar só o total |
| Biometria | Biometria do aparelho | Pede digital ou rosto ao abrir. | Chave liga e desliga na hora |
| Biometria indisponível | Biometria do aparelho | Este aparelho não tem biometria cadastrada. | Chave desligada |
| Frase de confiança | Seus dados ficam só com você | Aparece no guia e nas telas de privacidade, com cadeado. | — |
| Servidor próprio | Seus dados ficam no seu servidor | Nada passa por nós. | — |
| Modo demo | Modo demo · dados fictícios | Bia é uma pessoa fictícia. Seus dados de verdade ficam só no seu servidor. | Sair da demo, Criar minha conta |

Na demo, a fala da Paçoca no Início, "Aqui tudo é de mentirinha. Pode mexer à vontade!", é a brincadeira da tela. Nenhuma tela da demo que mostre erro de dinheiro repete a piada.

## Confirmações destrutivas

O título é a pergunta. O corpo diz o que acontece e se tem volta. Os botões respondem com o verbo. A ação destrutiva usa o botão principal em Urucum e só aparece dentro de diálogo.

| Ação | Título | Corpo | Botões |
|---|---|---|---|
| Desconectar banco | Desconectar o Banco Ipê? | O que já veio continua no Extrato. Para voltar a atualizar, é só conectar de novo no Meu Pluggy. | **Desconectar**, Cancelar |
| Desconectar aparelho | Desconectar o Notebook · Windows? | Quem estiver nele sai da conta agora. Os dados não são apagados. O aparelho atual não aparece com esse botão. | **Desconectar**, Cancelar |
| Excluir gasto em dinheiro | Excluir este gasto de -R$ 25,00? | Ele sai do Extrato e dos totais. Dá para desfazer por 4 segundos. | **Excluir**, Cancelar |
| Remover comprovante | Remover este comprovante? | A foto some deste lançamento. O lançamento fica. | **Remover**, Cancelar |
| Apagar regra | Apagar a regra de Mercado da Vila? | Os lançamentos já corrigidos continuam como estão. Os próximos seguem as regras do perfil. | **Apagar regra**, Cancelar |
| Apagar tudo | Apagar tudo? | Isso remove lançamentos, ajustes, comprovantes e configurações deste servidor. Não tem volta. Dica: exporte uma cópia antes. | **Apagar tudo**, Cancelar |

- **Apagar tudo pede mais um passo:** o campo "Digite apagar para confirmar". O botão só fica ativo depois disso. No modo local, "deste servidor" vira "deste aparelho" [Suposição].
- **Sair da demo não é destrutivo:** nada é salvo na demo, então o botão "Sair da demo" volta direto para a escolha de modo, sem diálogo.
- **Nunca "Sim" e "Não"** nos botões, e nunca "OK".
- **Corrigir não é destruir.** Correção e regra têm "Desfazer" e não pedem diálogo.

## Erros

O erro aparece na tela, perto de onde aconteceu. O aviso rápido não carrega erro importante. Toda mensagem tem três partes: o que aconteceu, o que está seguro e o próximo passo.

| Situação | Texto | Ação |
|---|---|---|
| Erro ao salvar | Não deu para salvar. Seus dados estão seguros; tente de novo. | Tentar de novo |
| Campo obrigatório | Falta o valor. | — |
| Valor inválido | Confira o valor: use só números, com vírgula nos centavos. | — |
| Senha curta | Use pelo menos 8 caracteres. Uma frase com espaços funciona bem. [Suposição] | — |
| Senha errada | A senha não bateu. Tente de novo ou use o código de recuperação. | Tentar de novo |
| Código do autenticador errado | O código não bateu. Confira o aplicativo autenticador e digite o novo. | — |
| Biometria recusada | Não reconheci. Dá para tentar de novo ou usar o PIN. | Usar PIN |
| Servidor não encontrado | Não achei esse servidor. Confira o endereço e tente de novo. | — |
| Câmera sem permissão | Preciso da câmera para ler o QR Code. Você também pode usar uma foto, um PDF ou digitar a chave. | Abrir permissões, Digitar a chave de acesso |
| QR Code não lido | Não consegui ler. Chegue um pouco mais perto ou digite a chave. | Digitar a chave de acesso |
| Nota fiscal não encontrada | Não encontrei essa nota. Ela pode levar um tempo para aparecer. | Tentar de novo |
| Nota repetida | Essa nota já está no seu extrato. | Ver lançamento |
| Divisão não fecha | Falta R$ 12,30 para fechar o valor. | — |
| Arquivo inválido | Não reconheci esse arquivo. Tente um OFX ou CSV do banco. | Escolher outro |
| IA indisponível | Não consegui falar com a IA agora. Nada saiu daqui além da pergunta. | Tentar de novo |
| Chave de IA inválida | A chave do provedor não funcionou. O app segue funcionando sem IA. | Trocar a chave |
| Sessão desconectada | Este aparelho foi desconectado. Entre de novo para continuar. | Entrar |

- **Sem piada.** Nenhuma destas mensagens tem brincadeira, e a Paçoca fica fora delas ou aparece séria e calma.
- **Sem jargão.** "Servidor" fica, "timeout", "500" e "exceção" não.
- **Sem culpar a pessoa.** "A senha não bateu", e não "Você digitou errado".
- **Erro de campo** aparece ao sair do campo, não a cada tecla, com a frase embaixo e a borda em Urucum.
- O leitor de tela anuncia o erro quando ele aparece.

## O que evitar

| Em vez de | Escreva |
|---|---|
| Supérfluo | Flexível |
| Você gastou demais | O delivery passou de R$ 300 este mês |
| Ops, algo deu errado | Não deu para salvar. Seus dados estão seguros; tente de novo. |
| Tem certeza? Sim, Não | Desconectar o Banco Ipê? Desconectar, Cancelar |
| Cuidado! | O que mudou e o que fazer |
| Parabéns, você economizou! | Meta batida! |
| R$ -187,43 | -R$ 187,43 |
| Em breve disponível | Ainda não dá para fazer isso. |
| Erro 500 | Não consegui falar com o seu servidor. |

## A conferir

- **Texto com pessoas:** todos os textos desta parte são propostas. Vale testar o aviso de minimização e as confirmações com 3 a 5 pessoas antes da Fase 1 [Suposição].
- **Tamanho do texto a 200%:** frases longas, como a do aviso de minimização, precisam quebrar sem cortar. Medir na [Parte 11](11-acessibilidade.md).
- **Tradução:** só há português do Brasil. As chaves de tradução ficam em inglês, e as frases, em ARB [Conferir: documentação de localização do Flutter].
- **Termos externos:** nome do site, texto de permissão e prazo de 7 dias vêm do que o Meu Pluggy e a Pluggy documentam [Conferir: docs.pluggy.ai].

## Próximo

[Parte 11](11-acessibilidade.md): checagem de acessibilidade.
