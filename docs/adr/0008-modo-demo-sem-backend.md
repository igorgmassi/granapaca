# ADR-008: Modo demo sem backend

- **Status:** Aceito
- **Data:** 2026-11-24

## Contexto

Quem descobre o GranaPaCá — para avaliar o app ou contribuir com design e código — precisa experimentar telas, filtros, gráficos, regras e correções antes de instalar Docker, subir o PostgreSQL ou criar conta na Pluggy (RF-63). Publicar uma demo navegável no GitHub Pages com zero infraestrutura de servidor elimina custo de hospedagem e evita manter um backend compartilhado exposto à internet.

## Decisão

Embutir o **modo demo diretamente no app Flutter**, alimentado por um dataset 100% sintético e determinístico, rodando sem nenhuma chamada de rede tanto no Flutter Web quanto nos aplicativos nativos:

- **Dataset determinístico compartilhado:** o conjunto fictício de bancos, contas, faturas e transações em `app/lib/demo/demo_data.dart` reproduz a mesma base do `SyntheticBankProvider` do backend (ADR-003), sem qualquer dado real.
- **Zero chamadas de rede:** no modo demo, o app nunca dispara requisições HTTP; consultas, filtros, correções manuais, criação de regras e aplicação de perfis operam localmente em memória durante a sessão.
- **Sinalização transparente:** um banner fixo no topo (`DemoBanner`) indica permanentemente que os dados exibidos são fictícios, e ações exclusivas de instância conectada (conectar banco via Pluggy, sincronizar servidor ou configurar 2FA) exibem aviso claro explicando que exigem a própria instância.
- **Publicação estática contínua:** o workflow `.github/workflows/demo-pages.yml` compila o bundle Flutter Web (`--base-href /granapaca/`) e publica diretamente no GitHub Pages a cada push na `main` que altera `app/`.

## Alternativas consideradas

- **Hospedar um backend público de demonstração:** exige servidor contínuo, isolamento contra abuso, reset periódico do banco e manutenção de segurança, contrariando o modelo sem servidor central do projeto.
- **Criar uma versão web separada com telas estáticas ou protótipos HTML:** duplica interface e diverge rapidamente do app Flutter real.
- **Permitir testar apenas subindo Docker localmente:** cria atrito alto demais para quem só quer conhecer o app em um minuto no navegador.

## Consequências

- A demo web no GitHub Pages custa zero, funciona offline após carregar e reflete exatamente os mesmos widgets e fluxos do app nativo.
- Os testes de widget do app reutilizam o mesmo dataset determinístico, garantindo previsibilidade sem depender de rede ou datas variáveis.
- Toda nova tela do MVP precisa funcionar sobre o modelo local de dados (ou sinalizar claramente quando depende da instância) para manter a demo navegável íntegra.
