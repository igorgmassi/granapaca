// Telas A (Identidade Toca Editorial): criação de conta animada com a Paçoca e tela Início (claro, escuro e desktop).
// Uso: node docs/design/telas/gerar-telas-a.mjs
import { c, usar, txt, linhas, marca, MARCA, rr, icone, pintas, pacoca, pacocaEditorial, botao, campo, chipGrande, cartao, valor, lancamento, nav, celular, grava, CEL } from "./kit.mjs";

// Indicador minimalista de 5 passos no topo (pintas limpas, sem barra escura pesada).
const passos5 = (ativo) =>
  Array.from({ length: 5 }, (_, i) => {
    const x = 148 + i * 16;
    const atual = i === ativo - 1;
    const feito = i < ativo - 1;
    return `<circle cx="${x}" cy="34" r="${atual ? 4.5 : 3.5}" fill="${atual ? c.primary : feito ? c.onSurfaceVariant : c.outline}"/>`;
  }).join("");

const X = 28, LW = 304;
const chips = (y, lista) => {
  let x = X, yy = y, s = "";
  for (const [l, sel] of lista) {
    const w = Math.round(l.length * 8.2 + 34);
    if (x + w > X + LW) { x = X; yy += 52; }
    s += chipGrande(x, yy, l, sel)[0];
    x += w + 8;
  }
  return s;
};
const pular = () => txt(180, 728, "Pular por agora", { p: 600, cor: c.primary, a: "middle" });

// Cartão limpo da criação de conta com a Paçoca apoiada diretamente na borda superior.
function telaOnboarding(etapa, totalGrupo, legenda, estadoPacoca, conteudo) {
  const cardY = 230;
  const patasFrente =
    estadoPacoca === "modo" || estadoPacoca === "email" || estadoPacoca === "pensando"
      ? `<ellipse cx="150" cy="${cardY + 2}" rx="13" ry="7.5" fill="#D9945C"/><ellipse cx="210" cy="${cardY + 2}" rx="13" ry="7.5" fill="#D9945C"/>`
      : "";
  return celular(
    0,
    0,
    passos5(totalGrupo) +
      pacocaEditorial(estadoPacoca, 180, cardY + 2, 1.05, { camada: "tras" }) +
      rr(14, cardY, 332, 514, 28, c.surfaceContainerLow, { borda: c.outlineVariant }) +
      patasFrente +
      pacocaEditorial(estadoPacoca, 180, cardY + 2, 1.05, { camada: "frente" }) +
      conteudo(),
    legenda,
    c.surface
  );
}

const ETAPAS = [
  // Etapas 1 a 5: Criação de conta com as 5 animações aprovadas da Paçoca
  ["1. Modo", 1, "modo", () =>
    marca(180, 278, "Como prefere acessar?", { t: 22, a: "middle" }) +
    rr(X, 304, 146, 72, 16, c.surfaceContainer, { borda: c.outlineVariant }) +
    txt(X + 73, 336, "Meu servidor", { t: 14, p: 600, a: "middle" }) +
    txt(X + 73, 356, "Self-hosted", { t: 12, cor: c.onSurfaceVariant, a: "middle" }) +
    rr(X + 158, 304, 146, 72, 16, c.surfaceContainer, { borda: c.outlineVariant }) +
    txt(X + 231, 336, "Explorar demo", { t: 14, p: 600, a: "middle" }) +
    txt(X + 231, 356, "Dados fictícios", { t: 12, cor: c.onSurfaceVariant, a: "middle" }) +
    rr(X, 388, LW, 72, 16, c.secondaryContainer, { borda: c.primary, lb: 2 }) +
    `<circle cx="${X + 24}" cy="424" r="9" fill="none" stroke="${c.primary}" stroke-width="2"/><circle cx="${X + 24}" cy="424" r="4.5" fill="${c.primary}"/>` +
    txt(X + 44, 419, "No meu celular", { t: 15, p: 600, cor: c.onSecondaryContainer }) +
    txt(X + 44, 439, "Sem servidor · cofre criptografado", { t: 12, cor: c.onSurfaceVariant }) +
    txt(180, 494, "A Paçoca vira o olhar para a opção escolhida.", { t: 12, cor: c.onSurfaceVariant, a: "middle" }) +
    botao(X, 668, LW, "Continuar")],

  ["2. E-mail", 2, "email", () =>
    marca(180, 278, "Quem está chegando?", { t: 22, a: "middle" }) +
    txt(180, 304, "Seus dados ficam sob seu controle.", { t: 13, cor: c.onSurfaceVariant, a: "middle" }) +
    campo(X, 344, LW, "Seu nome ou e-mail", "bia@exemplo.com", { foco: true }) +
    txt(180, 428, "O olhar da Paçoca acompanha a digitação.", { t: 12, cor: c.onSurfaceVariant, a: "middle" }) +
    botao(X, 668, LW, "Próximo")],

  ["3. Senha", 3, "senha", () =>
    marca(180, 278, "Crie sua senha", { t: 22, a: "middle" }) +
    txt(180, 304, "A Paçoca tampa os olhos por privacidade.", { t: 13, cor: c.onSurfaceVariant, a: "middle" }) +
    campo(X, 344, LW, "Senha ou PIN", "••••••••••", { foco: true }) +
    icone("olho", X + LW - 38, 360, c.onSurfaceVariant, 22) +
    txt(X, 424, "Ao tocar no olho, ela dá uma espiadinha.", { t: 12, cor: c.onSurfaceVariant }) +
    icone("cadeado", 74, 622, c.onSurfaceVariant, 15) +
    txt(194, 634, "Seus dados ficam só com você", { t: 12, cor: c.onSurfaceVariant, a: "middle" }) +
    botao(X, 668, LW, "Confirmar")],

  ["4. Segurança", 4, "seguranca", () =>
    marca(180, 278, "Ative a segurança", { t: 22, a: "middle" }) +
    linhas(180, 306, ["Digite o código do autenticador ou", "ative a biometria do aparelho."], { t: 13, cor: c.onSurfaceVariant, a: "middle" }, 18) +
    [0, 1, 2, 3, 4, 5].map((i) =>
      rr(X + i * 52, 356, 44, 54, 12, c.surfaceContainerLowest, { borda: i === 3 ? c.primary : c.outline, lb: i === 3 ? 2 : 1 }) +
      (i < 3 ? txt(X + i * 52 + 22, 391, "481"[i], { t: 20, p: 600, a: "middle" }) : "")
    ).join("") +
    rr(X, 434, LW, 48, 16, c.surfaceContainer, { borda: c.outlineVariant }) +
    icone("cadeado", X + 16, 448, c.mata, 20) +
    txt(X + 46, 463, "Ativar biometria do aparelho", { t: 14, p: 600 }) +
    botao(X, 668, LW, "Ativar")],

  ["5. Toca pronta!", 5, "pronto", () =>
    marca(180, 296, "Tudo pronto, Bia", { t: 26, a: "middle" }) +
    linhas(180, 332, ["A sua toca já está montada.", "Agora dá para acompanhar cada real", "com calma e sem planilha."], { t: 15, cor: c.onSurfaceVariant, a: "middle" }, 22) +
    rr(X, 432, LW, 72, 16, c.surfaceContainer, { borda: c.outlineVariant }) +
    txt(X + 16, 462, "Perfil inicial pronto", { t: 14, p: 600 }) +
    txt(X + 16, 484, "Você pode personalizar regras quando quiser.", { t: 12, cor: c.onSurfaceVariant }) +
    botao(X, 668, LW, "Entrar na toca")],

  // Etapas 6 a 10: Guia rápido de perfil (opcional)
  ["6. Ocupação", 1, "pensando", () =>
    marca(X, 278, "O que você faz hoje?", { t: 22 }) +
    txt(X, 304, "Pode marcar mais de uma.", { t: 13, cor: c.onSurfaceVariant }) +
    chips(332, [["Carteira assinada", true], ["Autônomo", false], ["Estudante", true], ["Aposentado", false], ["Empresa própria", false], ["Outro", false]]) +
    botao(X, 636, LW, "Continuar") + pular()],

  ["7. Casa", 2, "modo", () =>
    marca(X, 278, "Como é a sua casa?", { t: 22 }) +
    txt(X, 304, "Isso ajuda a separar o que é essencial.", { t: 13, cor: c.onSurfaceVariant }) +
    chips(332, [["Aluguel", true], ["Financiada", false], ["Própria quitada", false], ["Moro com a família", false]]) +
    botao(X, 636, LW, "Continuar") + pular()],

  ["8. Transporte", 3, "email", () =>
    marca(X, 278, "Como você se desloca?", { t: 22 }) +
    txt(X, 304, "Pode marcar mais de uma.", { t: 13, cor: c.onSurfaceVariant }) +
    chips(332, [["Carro próprio", false], ["Ônibus ou metrô", true], ["Aplicativo", true], ["Moto", false], ["Bicicleta ou a pé", false]]) +
    botao(X, 636, LW, "Continuar") + pular()],

  ["9. Revisão das regras", 4, "pensando", () =>
    marca(X, 278, "Olha o que eu entendi", { t: 22 }) +
    txt(X, 304, "Dá para mudar quando quiser.", { t: 13, cor: c.onSurfaceVariant }) +
    [["Aluguel", "Essencial", 3, c.essencial], ["Ônibus e metrô", "Essencial", 3, c.essencial], ["Aplicativo", "Importante", 2, c.importante], ["Streaming", "Flexível", 1, c.flexivel]]
      .map(([n, nivel, q, cor], i) => {
        const y = 330 + i * 56;
        return cartao(X, y, LW, 48) + txt(X + 14, y + 30, n, { t: 14, p: 600 }) + pintas(X + 188, y + 25, q, cor) + txt(X + LW - 14, y + 30, nivel, { t: 12, a: "end", cor: c.onSurfaceVariant });
      }).join("") +
    botao(X, 636, LW, "Está certo") + txt(180, 728, "Ajustar as regras", { p: 600, cor: c.primary, a: "middle" })],

  ["10. Conectar bancos", 5, "pronto", () =>
    marca(X, 278, "Hora de trazer a grana", { t: 22 }) +
    [["Abra o Meu Pluggy", "O site abre fora do app."], ["Conecte seus bancos por lá", "Open Finance, sem senha aqui."], ["Volte e toque em Já conectei", "Ou importe OFX / CSV no celular."]]
      .map(([a, b], i) => {
        const y = 312 + i * 64;
        return `<circle cx="${X + 16}" cy="${y + 18}" r="15" fill="${c.secondaryContainer}"/>` +
          txt(X + 16, y + 23, i + 1, { p: 600, a: "middle", cor: c.onSecondaryContainer }) +
          txt(X + 42, y + 14, a, { t: 14, p: 600 }) + txt(X + 42, y + 34, b, { t: 12, cor: c.onSurfaceVariant });
      }).join("") +
    rr(X, 576, LW, 48, 24, c.primary) + txt(170, 605, "Abrir o Meu Pluggy", { p: 600, cor: c.onPrimary, a: "middle" }) + icone("fora", 252, 589, c.onPrimary, 20) +
    botao(X, 636, LW, "Já conectei", "contorno") + pular()],
];

// ---------- Início (Toca Editorial) ----------
function inicio({ oculto, vazio } = {}) {
  let s = marca(20, 62, "Boa noite, Bia", { t: 26 }) + icone("sino", 314, 38, c.onSurface) +
    (vazio ? "" : `<circle cx="334" cy="40" r="9" fill="${c.error}"/>` + txt(334, 44, "2", { t: 11, p: 600, cor: c.onError, a: "middle" }));
  if (vazio) {
    s += cartao(16, 88, 328, 300) + pacoca("dormindo", 180, 218, 94) +
      marca(180, 260, "Seus bancos estão a caminho", { t: 18, a: "middle" }) +
      linhas(180, 288, ["A primeira sincronização leva alguns", "minutos. Eu aviso quando chegar."], { a: "middle", cor: c.onSurfaceVariant }) +
      botao(84, 326, 192, "Conectar outro banco", "contorno");
    s += cartao(16, 404, 328, 116) + txt(32, 434, "Enquanto isso", { t: 16, p: 600 }) +
      linhas(32, 460, ["Registre um gasto em dinheiro ou leia uma", "nota fiscal pelo botão + aqui embaixo."], { cor: c.onSurfaceVariant });
    return s + nav(676, "Início");
  }
  // Cartão hero: Sobrou este mês + badge verde sutil + barra 100% caramelo.
  s += cartao(16, 86, 328, 194) +
    txt(32, 116, "Sobrou este mês", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    (!oculto ? rr(234, 100, 60, 24, 12, c.mata, { op: 0.16 }) + txt(264, 116, "+12%", { t: 12, p: 600, cor: c.mata, a: "middle" }) : "") +
    icone("olho", 304, 98, c.onSurfaceVariant) +
    (oculto
      ? txt(32, 166, "R$", { t: 38, p: 700 }) + [0, 1, 2].map((k) => `<circle cx="${104 + k * 20}" cy="153" r="6.5" fill="${c.onSurface}"/>`).join("")
      : valor(32, 166, "1.284", "90")) +
    txt(32, 194, oculto ? "Entrou R$ ••• · Saiu R$ •••" : "Entrou R$ 6.200,00 · Saiu R$ 4.915,10", { t: 12, cor: c.onSurfaceVariant }) +
    rr(32, 212, 296, 9, 4.5, c.surfaceContainerHighest) +
    rr(32, 212, 134, 9, 4.5, c.essencial) + rr(168, 212, 60, 9, 0, c.importante) + rr(230, 212, 42, 9, 0, c.flexivel) +
    [["Essencial", 3, c.essencial, 28], ["Importante", 2, c.importante, 132], ["Flexível", 1, c.flexivel, 246]]
      .map(([n, q, cor, x]) => pintas(x + 4, 248, q, cor) + txt(x + 40, 252, n, { t: 11 })).join("");

  // Cartão editorial da fala da Paçoca (superfície limpa + retrato sem pochete).
  s += cartao(16, 294, 328, 90) +
    pacocaEditorial("retrato", 62, 384, 0.7) +
    linhas(108, 332, ["Mercado ficou 12% abaixo do", "mês passado. Bom ritmo!"], { t: 14, p: 500, f: MARCA, cor: c.onSurface }, 22);

  // Últimos lançamentos
  s += txt(18, 416, "Últimos lançamentos", { t: 15, p: 600 }) + txt(342, 416, "Ver tudo", { t: 13, p: 600, cor: c.primary, a: "end" }) +
    cartao(16, 430, 328, 196) +
    lancamento(28, 438, 302, "Mercado da Vila", "Alimentação · Débito", oculto ? "R$ •••" : "-R$ 187,43") + `<path d="M28 500H332" stroke="${c.outlineVariant}"/>` +
    lancamento(28, 500, 302, "Posto Estrela", "Transporte · Crédito", oculto ? "R$ •••" : "-R$ 210,00", { cat: "transporte", banco: c.rio, ic: "carro" }) + `<path d="M28 562H332" stroke="${c.outlineVariant}"/>` +
    lancamento(28, 562, 302, "Salário", "Entrada · Pix", oculto ? "+R$ •••" : "+R$ 6.200,00", { entrada: true, ic: "seta" });
  return s + nav(676, "Início");
}

function inicioDesktop() {
  const W = 1280, H = 800;
  let s = rr(0, 0, W, H, 0, c.surface) + rr(0, 0, 88, H, 0, c.surfaceContainer) + `<path d="M88 0V${H}" stroke="${c.outlineVariant}"/>` +
    rr(16, 24, 56, 56, 16, c.primary) + icone("mais", 32, 40, c.onPrimary, 24, 2.2);
  [["casa", "Início", true], ["lista", "Extrato"], ["pizza", "Gastos"], ["balao", "Paçoca"]].forEach(([ic, l, sel], i) => {
    const y = 112 + i * 64;
    s += (sel ? rr(16, y, 56, 30, 15, c.secondaryContainer) : "") + icone(ic, 32, y + 3, sel ? c.onSecondaryContainer : c.onSurfaceVariant) +
      txt(44, y + 48, l, { t: 12, p: 600, a: "middle", cor: sel ? c.onSurface : c.onSurfaceVariant });
  });
  s += icone("engrenagem", 32, H - 56, c.onSurfaceVariant);
  s += marca(120, 66, "Boa noite, Bia", { t: 30 }) + icone("sino", 1216, 40, c.onSurface) + `<circle cx="1236" cy="42" r="9" fill="${c.error}"/>` + txt(1236, 46, "2", { t: 11, p: 600, cor: c.onError, a: "middle" });

  // Coluna esquerda: resumo, fala editorial da Paçoca e contas conectadas.
  s += cartao(120, 96, 520, 224) + txt(144, 132, "Sobrou este mês", { p: 600, cor: c.onSurfaceVariant }) +
    rr(520, 114, 62, 24, 12, c.mata, { op: 0.16 }) + txt(551, 130, "+12%", { t: 12, p: 600, cor: c.mata, a: "middle" }) +
    icone("olho", 592, 112, c.onSurfaceVariant) +
    valor(144, 190, "1.284", "90", 46) +
    txt(144, 222, "Entrou R$ 6.200,00 · Saiu R$ 4.915,10", { t: 13, cor: c.onSurfaceVariant }) +
    rr(144, 244, 472, 11, 5.5, c.surfaceContainerHighest) + rr(144, 244, 212, 11, 5.5, c.essencial) + rr(358, 244, 94, 11, 0, c.importante) + rr(454, 244, 67, 11, 0, c.flexivel) +
    [["Essencial", 3, c.essencial, 144, "R$ 2.790,00"], ["Importante", 2, c.importante, 306, "R$ 1.240,10"], ["Flexível", 1, c.flexivel, 470, "R$ 885,00"]]
      .map(([n, q, cor, x, v]) => pintas(x + 4, 284, q, cor) + txt(x + 42, 288, n, { t: 13 }) + txt(x + 42, 304, v, { t: 12, cor: c.onSurfaceVariant })).join("");

  s += cartao(120, 340, 520, 108) +
    pacocaEditorial("retrato", 174, 446, 0.82) +
    linhas(232, 386, ["Mercado ficou 12% abaixo do mês passado.", "Bom ritmo!"], { t: 16, p: 500, f: MARCA, cor: c.onSurface }, 24);

  s += cartao(120, 468, 520, 300) + txt(144, 504, "Contas conectadas", { t: 16, p: 600 });
  [["Banco Ipê", "Conta corrente", "3.412", "08", c.tertiary], ["Banco Jatobá", "Cartão de crédito · fatura aberta", "1.130", "55", c.rio]].forEach(([b, t, i, d, cor], k) => {
    const y = 524 + k * 96;
    s += rr(144, y, 4, 64, 2, cor) + txt(164, y + 22, b, { t: 16, p: 600 }) + txt(164, y + 42, t, { t: 12, cor: c.onSurfaceVariant }) + valor(616, y + 34, i, d, 24, { a: "end" }) +
      `<circle cx="168" cy="${y + 58}" r="4" fill="${c.mata}"/>` + txt(180, y + 62, "Sincronizado hoje às 18:40", { t: 12, cor: c.onSurfaceVariant });
  });
  s += txt(144, 742, "Conectar outro banco", { p: 600, cor: c.primary });

  // Coluna direita: lançamentos e rosca.
  s += cartao(672, 96, 576, 352) + txt(696, 132, "Últimos lançamentos", { t: 16, p: 600 }) + txt(1224, 132, "Ver tudo", { p: 600, cor: c.primary, a: "end" });
  [["Mercado da Vila", "Alimentação · Débito · Banco Ipê", "-R$ 187,43", {}],
    ["Posto Estrela", "Transporte · Crédito · Banco Jatobá", "-R$ 210,00", { cat: "transporte", banco: c.rio, ic: "carro" }],
    ["Salário", "Entrada · Pix · Banco Ipê", "+R$ 6.200,00", { entrada: true, ic: "seta" }],
    ["Loja 0387", "Compras · Crédito · Banco Jatobá", "-R$ 64,90", { cat: "compras", banco: c.rio, ic: "sacola" }]]
    .forEach(([n, i, v, o], k) => { const y = 148 + k * 68; s += lancamento(696, y, 528, n, i, v, o) + (k < 3 ? `<path d="M696 ${y + 62}H1224" stroke="${c.outlineVariant}"/>` : ""); });

  const gastos = [["moradia", "Moradia", 1800], ["alimentacao", "Alimentação", 960], ["transporte", "Transporte", 520], ["compras", "Compras", 420], ["saude", "Saúde", 310], ["outros", "Outros", 905.1]];
  const tot = gastos.reduce((a, g) => a + g[2], 0), R = 70, C = 2 * Math.PI * R;
  let ini = 0;
  s += cartao(672, 468, 576, 300) + txt(696, 504, "Para onde foi", { t: 16, p: 600 }) + txt(1224, 504, "Ver análise", { p: 600, cor: c.primary, a: "end" });
  for (const [id, , v] of gastos) {
    const L = (v / tot) * C;
    s += `<circle cx="800" cy="638" r="${R}" fill="none" stroke="${c.g[id]}" stroke-width="28" stroke-dasharray="${(L - 2).toFixed(1)} ${C.toFixed(1)}" stroke-dashoffset="${(-ini).toFixed(1)}" transform="rotate(-90 800 638)"/>`;
    ini += L;
  }
  s += txt(800, 636, "R$ 4.915,10", { t: 15, p: 600, a: "middle" }) + txt(800, 654, "em novembro", { t: 11, a: "middle", cor: c.onSurfaceVariant });
  gastos.forEach(([id, n, v], k) => {
    const y = 546 + k * 34;
    s += `<circle cx="928" cy="${y}" r="6" fill="${c.g[id]}"/>` + txt(946, y + 5, n, { t: 14 }) + txt(1224, y + 5, `R$ ${v.toFixed(2).replace(".", ",").replace(/\B(?=(\d{3})+(?!\d))/g, ".")}`, { t: 14, p: 600, a: "end" });
  });
  return { W, H, s };
}

const G = 32, LEG = 44;
for (const tema of ["claro", "escuro"]) {
  usar(tema);
  for (const [nome, de] of [["trilha-1", 0], ["trilha-2", 5]]) {
    const corpo = [0, 1, 2, 3, 4].map((i) => {
      const [legenda, passo, pose, conteudo] = ETAPAS[de + i];
      return `<g transform="translate(${G + i * (CEL.w + G)} ${G})">${telaOnboarding(de + i + 1, passo, legenda, pose, conteudo)}</g>`;
    }).join("");
    grava(import.meta.url, `${nome}-${tema}`, 5 * (CEL.w + G) + G, CEL.h + G + LEG + 12, corpo, `Criação de conta e guia inicial, etapas ${de + 1} a ${de + 5}, tema ${tema}`);
  }
  const telas = [[inicio(), "Início"], [inicio({ oculto: true }), "Início com os valores ocultos"], [inicio({ vazio: true }), "Início no primeiro dia"]];
  grava(import.meta.url, `inicio-${tema}`, 3 * (CEL.w + G) + G, CEL.h + G + LEG + 12,
    telas.map(([t, l], i) => `<g transform="translate(${G + i * (CEL.w + G)} ${G})">${celular(0, 0, t, l)}</g>`).join(""), `Início no celular, tema ${tema}`);
  const d = inicioDesktop();
  grava(import.meta.url, `inicio-desktop-${tema}`, d.W, d.H, d.s, `Início no desktop, tema ${tema}`);
}
console.log("8 folhas gravadas em docs/design/telas");
