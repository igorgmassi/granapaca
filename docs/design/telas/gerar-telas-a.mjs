// Telas A: o primeiro acesso ("Trilha até a toca") e o Início, nos temas claro e escuro, e o Início no desktop.
// Uso: node docs/design/telas/gerar-telas-a.mjs
import { c, usar, txt, linhas, marca, rr, icone, pintas, pacoca, botao, campo, chipGrande, cartao, valor, lancamento, nav, celular, grava, CEL } from "./kit.mjs";

// ---------- Cenário da trilha: do fim de tarde (etapa 1) até a noite (etapa 10) ----------
const CEU = ["#F6C27A", "#F4B26C", "#EFA063", "#E58C62", "#CF7A6B", "#A86C7C", "#7C5F86", "#55507E", "#343A63", "#1E2440"];
function cenario(etapa) {
  const k = etapa - 1, noite = k / 9, dia = etapa <= 6;
  const astro = dia ? `<circle cx="282" cy="${70 + k * 14}" r="26" fill="#F7D27A"/>`
    : `<circle cx="282" cy="${150 - (k - 5) * 18}" r="20" fill="#F7E6CC"/>` +
      [[40, 40], [92, 70], [150, 30], [210, 58], [330, 36], [20, 96]].slice(0, k - 3).map(([x, y]) => `<circle cx="${x}" cy="${y}" r="1.8" fill="#F7E6CC"/>`).join("");
  const arvore = (x, y, r, cor) => `<rect x="${x - 3}" y="${y}" width="6" height="${r * 1.1}" fill="#6F340E"/><circle cx="${x}" cy="${y}" r="${r}" fill="${cor}"/>`;
  const toca = etapa === 10 ? `<path d="M236 236 V196 A44 44 0 0 1 324 196 V236 Z" fill="#6F340E"/><path d="M250 236 V200 A30 30 0 0 1 310 200 V236 Z" fill="#F7D27A"/>` : "";
  // Pegadas: uma dupla por etapa já andada.
  const pegadas = Array.from({ length: k }, (_, i) => { const x = 150 - i * 15, y = 244 + (i % 2) * 5;
    return `<ellipse cx="${x}" cy="${y}" rx="4" ry="2.6" fill="#8E4A20" opacity="${Math.max(0.25, 0.9 - i * 0.08)}"/>`; }).join("");
  return `<rect width="360" height="290" fill="${CEU[k]}"/>${astro}` +
    `<path d="M0 150 C60 112 120 132 180 122 C240 112 300 92 360 132 V290 H0Z" fill="#6E9A72"/>` +
    arvore(52, 150, 20, "#3F7556") + arvore(118, 138, 15, "#3F7556") + arvore(338, 140, 18, "#3F7556") +
    `<path d="M0 186 C80 156 150 180 220 166 C280 154 330 170 360 160 V290 H0Z" fill="#3F7556"/>` +
    arvore(24, 188, 24, "#2A7550") + arvore(206, 172, 18, "#2A7550") + (etapa === 10 ? "" : arvore(316, 176, 22, "#2A7550")) +
    `<path d="M0 232 C90 216 270 216 360 232 V290 H0Z" fill="#D99A66"/>` + pegadas +
    `<rect width="360" height="290" fill="#17110D" opacity="${(noite * 0.42).toFixed(2)}"/>` + toca; // a luz da toca fica acesa por cima da noite
}
// Indicador de passos: dez pegadas no alto, as andadas preenchidas.
const passos = (etapa) => rr(100, 16, 160, 20, 10, "#17110D", { op: 0.35 }) + Array.from({ length: 10 }, (_, i) =>
  `<circle cx="${112 + i * 15}" cy="26" r="${i < etapa ? 4 : 3}" fill="${i < etapa ? "#F7E6CC" : "none"}" stroke="#F7E6CC" stroke-width="1.2"/>`).join("");

// Cada etapa: [legenda, pose da Paçoca, altura da Paçoca, conteúdo do cartão].
const X = 24, LW = 312;
const chips = (y, lista) => { let x = X, yy = y, s = ""; for (const [l, sel] of lista) { const w = Math.round(l.length * 8.4 + 36);
  if (x + w > X + LW) { x = X; yy += 54; } s += chipGrande(x, yy, l, sel)[0]; x += w + 8; } return s; };
const pular = () => txt(180, 734, "Pular por agora", { p: 600, cor: c.primary, a: "middle" });
const ETAPAS = [
  ["1. Boas-vindas", "acenando", 150, () => marca(X, 338, "Vem pra toca", { t: 36 }) +
    linhas(X, 376, ["Toda a sua grana, num lugar só.", "Eu sou a Paçoca e vou com você até lá."], { t: 16, cor: c.onSurfaceVariant }, 24) +
    botao(X, 626, LW, "Começar") + botao(X, 684, LW, "Ver a demonstração", "texto")],
  ["2. Servidor", "lupa", 130, () => marca(X, 332, "Onde fica a sua toca?", { t: 26 }) +
    linhas(X, 360, ["É o endereço do servidor que você instalou."], { cor: c.onSurfaceVariant }) +
    campo(X, 404, LW, "Endereço do servidor", "toca.exemplo.ts.net", { foco: true }) +
    rr(X, 478, LW, 48, 24, "none", { borda: c.outline }) + icone("qr", 110, 490, c.primary) + txt(196, 507, "Ler o QR Code", { p: 600, cor: c.primary, a: "middle" }) +
    botao(X, 684, LW, "Continuar")],
  ["3. Entrar", "cadeado", 130, () => marca(X, 332, "Quem está chegando?", { t: 26 }) +
    campo(X, 380, LW, "E-mail", "bia@exemplo.com") + campo(X, 470, LW, "Senha", "••••••••••") + icone("olho", 296, 486, c.onSurfaceVariant) +
    txt(X, 556, "Esqueci a senha", { p: 600, cor: c.primary }) + botao(X, 684, LW, "Entrar")],
  ["4. Autenticador", "cadeado", 130, () => marca(X, 332, "Só mais uma checagem", { t: 26 }) +
    linhas(X, 360, ["Digite o código de 6 números do seu", "aplicativo autenticador."], { cor: c.onSurfaceVariant }) +
    [0, 1, 2, 3, 4, 5].map((i) => rr(X + i * 53, 412, 46, 56, 12, c.surfaceContainerLowest, { borda: i === 3 ? c.primary : c.outline, lb: i === 3 ? 2 : 1 }) +
      (i < 3 ? txt(X + i * 53 + 23, 448, "481"[i], { t: 22, p: 600, a: "middle" }) : "")).join("") +
    botao(X, 684, LW, "Confirmar")],
  ["5. Ocupação", "pensando", 130, () => marca(X, 332, "O que você faz hoje?", { t: 26 }) +
    txt(X, 358, "Pode marcar mais de uma.", { cor: c.onSurfaceVariant }) +
    chips(380, [["Carteira assinada", true], ["Autônomo", false], ["Estudante", true], ["Aposentado", false], ["Empresa própria", false], ["Outro", false]]) +
    botao(X, 638, LW, "Continuar") + pular()],
  ["6. Casa", "frente", 130, () => marca(X, 332, "Como é a sua casa?", { t: 26 }) +
    txt(X, 358, "Isso me ajuda a saber o que é essencial.", { cor: c.onSurfaceVariant }) +
    chips(380, [["Aluguel", true], ["Financiada", false], ["Própria quitada", false], ["Moro com a família", false]]) +
    botao(X, 638, LW, "Continuar") + pular()],
  ["7. Transporte", "perfil", 92, () => marca(X, 332, "Como você se desloca?", { t: 26 }) +
    txt(X, 358, "Pode marcar mais de uma.", { cor: c.onSurfaceVariant }) +
    chips(380, [["Carro próprio", false], ["Ônibus ou metrô", true], ["Aplicativo", true], ["Moto", false], ["Bicicleta ou a pé", false]]) +
    botao(X, 638, LW, "Continuar") + pular()],
  ["8. Revisão das regras", "lupa", 130, () => marca(X, 332, "Olha o que eu entendi", { t: 26 }) +
    txt(X, 358, "Dá para mudar quando quiser.", { cor: c.onSurfaceVariant }) +
    [["Aluguel", "Essencial", 3, c.essencial], ["Ônibus e metrô", "Essencial", 3, c.essencial], ["Aplicativo de corrida", "Importante", 2, c.importante], ["Streaming", "Flexível", 1, c.flexivel]]
      .map(([n, nivel, q, cor], i) => { const y = 378 + i * 58;
        return cartao(X, y, LW, 50, { }) + txt(X + 16, y + 31, n, { t: 15, p: 600 }) + pintas(X + 196, y + 26, q, cor) + txt(X + LW - 14, y + 31, nivel, { t: 13, a: "end", cor: c.onSurfaceVariant }); }).join("") +
    botao(X, 638, LW, "Está certo") + txt(180, 734, "Ajustar as regras", { p: 600, cor: c.primary, a: "middle" })],
  ["9. Conectar bancos", "tres-quartos", 130, () => marca(X, 332, "Hora de trazer a grana", { t: 26 }) +
    [["Abra o Meu Pluggy", "O site abre fora do app."], ["Conecte seus bancos por lá", "Com o Open Finance, sem senha aqui."], ["Volte e toque em Já conectei", "Cada banco aparece quando sincronizar."]]
      .map(([a, b], i) => { const y = 362 + i * 66;
        return `<circle cx="${X + 16}" cy="${y + 18}" r="16" fill="${c.primaryContainer}"/>` + txt(X + 16, y + 23, i + 1, { p: 600, a: "middle", cor: c.onPrimaryContainer }) +
          txt(X + 44, y + 14, a, { t: 15, p: 600 }) + txt(X + 44, y + 34, b, { t: 13, cor: c.onSurfaceVariant }); }).join("") +
    rr(X, 580, LW, 48, 24, c.primary) + txt(170, 609, "Abrir o Meu Pluggy", { p: 600, cor: c.onPrimary, a: "middle" }) + icone("fora", 250, 593, c.onPrimary, 22) +
    botao(X, 638, LW, "Já conectei", "contorno") + pular()],
  ["10. Chegada à toca", "comemorando", 150, () => marca(X, 338, "Chegamos!", { t: 36 }) +
    linhas(X, 376, ["A sua toca está pronta.", "Os bancos aparecem aqui assim que", "sincronizarem."], { t: 16, cor: c.onSurfaceVariant }, 24) +
    botao(X, 684, LW, "Entrar na toca")],
];
function telaTrilha(i) {
  const [legenda, pose, alt, conteudo] = ETAPAS[i], etapa = i + 1;
  const px = etapa === 10 ? 150 : 180;
  return celular(0, 0, cenario(etapa) + passos(etapa) + pacoca(pose, px, 252, alt) +
    rr(0, 272, 360, 520, 28, c.surface) + conteudo(), legenda);
}

// ---------- Início ----------
function inicio({ oculto, vazio } = {}) {
  let s = marca(16, 62, "Boa noite, Bia", { t: 28 }) + icone("sino", 316, 38, c.onSurface) + (vazio ? "" : `<circle cx="336" cy="40" r="9" fill="${c.error}"/>` + txt(336, 44, "2", { t: 11, p: 600, cor: c.onError, a: "middle" }));
  if (vazio) {
    s += cartao(16, 88, 328, 300) + pacoca("dormindo", 180, 220, 96) + marca(180, 264, "Seus bancos estão a caminho", { t: 20, a: "middle" }) +
      linhas(180, 292, ["A primeira sincronização leva alguns", "minutos. Eu aviso quando chegar."], { a: "middle", cor: c.onSurfaceVariant }) +
      botao(92, 328, 176, "Conectar outro banco", "contorno");
    s += cartao(16, 404, 328, 116) + txt(32, 434, "Enquanto isso", { t: 16, p: 600 }) +
      linhas(32, 460, ["Registre um gasto em dinheiro ou leia uma nota", "fiscal pelo botão + aqui embaixo."], { cor: c.onSurfaceVariant });
    return s + nav(676, "Início");
  }
  s += cartao(16, 88, 328, 196) + txt(32, 118, "Sobrou este mês", { p: 600, cor: c.onSurfaceVariant }) + icone("olho", 304, 100, c.onSurfaceVariant) +
    (oculto ? txt(32, 166, "R$", { t: 40, p: 600 }) + [0, 1, 2].map((k) => `<circle cx="${108 + k * 22}" cy="153" r="7" fill="${c.onSurface}"/>`).join("")
      : valor(32, 166, "1.284", "90")) +
    txt(32, 194, oculto ? "Entrou R$ ••• · Saiu R$ •••" : "Entrou R$ 6.200,00 · Saiu R$ 4.915,10", { t: 12, cor: c.onSurfaceVariant }) +
    rr(32, 210, 296, 10, 5, c.surfaceContainerHighest) + rr(32, 210, 133, 10, 5, c.essencial) + rr(167, 210, 59, 10, 0, c.importante) + rr(228, 210, 42, 10, 0, c.flexivel) +
    [["Essencial", 3, c.essencial, 32], ["Importante", 2, c.importante, 138], ["Flexível", 1, c.flexivel, 250]].map(([n, q, cor, x]) => pintas(x + 4, 248, q, cor) + txt(x + 42, 252, n, { t: 12 })).join("");
  s += pacoca("acenando", 46, 384, 84) + `<path d="M100 304h224a20 20 0 0 1 20 20v40a20 20 0 0 1-20 20H86a6 6 0 0 1-6-6v-54a20 20 0 0 1 20-20Z" fill="${c.primaryContainer}"/>` +
    linhas(98, 334, ["Mercado ficou 12% abaixo do", "mês passado. Bom ritmo!"], { t: 15, p: 500, f: "'Baloo 2', ui-rounded, system-ui, sans-serif", cor: c.onPrimaryContainer }, 22);
  s += txt(16, 424, "Últimos lançamentos", { t: 16, p: 600 }) + txt(344, 424, "Ver tudo", { p: 600, cor: c.primary, a: "end" }) + cartao(16, 438, 328, 188) +
    lancamento(28, 444, 300, "Mercado da Vila", "Alimentação · Débito", oculto ? "R$ •••" : "R$ 187,43") + `<path d="M28 504H332" stroke="${c.outlineVariant}"/>` +
    lancamento(28, 504, 300, "Posto Estrela", "Transporte · Crédito", oculto ? "R$ •••" : "R$ 210,00", { cat: "transporte", banco: c.rio, ic: "carro" }) + `<path d="M28 564H332" stroke="${c.outlineVariant}"/>` +
    lancamento(28, 564, 300, "Salário", "Entrada · Pix", oculto ? "+R$ •••" : "+R$ 6.200,00", { entrada: true, ic: "seta" });
  return s + nav(676, "Início");
}
function inicioDesktop() {
  const W = 1280, H = 800;
  let s = rr(0, 0, W, H, 0, c.surface) + rr(0, 0, 88, H, 0, c.surfaceContainer) + `<path d="M88 0V${H}" stroke="${c.outlineVariant}"/>` + rr(16, 24, 56, 56, 16, c.primary) + icone("mais", 32, 40, c.onPrimary, 24, 2.2);
  [["casa", "Início", true], ["lista", "Extrato"], ["pizza", "Gastos"], ["balao", "Paçoca"]].forEach(([ic, l, sel], i) => { const y = 112 + i * 64;
    s += (sel ? rr(16, y, 56, 30, 15, c.secondaryContainer) : "") + icone(ic, 32, y + 3, sel ? c.onSecondaryContainer : c.onSurfaceVariant) + txt(44, y + 48, l, { t: 12, p: 600, a: "middle", cor: sel ? c.onSurface : c.onSurfaceVariant }); });
  s += icone("engrenagem", 32, H - 56, c.onSurfaceVariant);
  s += marca(120, 68, "Boa noite, Bia", { t: 32 }) + icone("sino", 1216, 40, c.onSurface) + `<circle cx="1236" cy="42" r="9" fill="${c.error}"/>` + txt(1236, 46, "2", { t: 11, p: 600, cor: c.onError, a: "middle" });
  // Coluna esquerda: resumo e fala. Coluna direita: lançamentos e rosca.
  s += cartao(120, 96, 520, 220) + txt(144, 132, "Sobrou este mês", { p: 600, cor: c.onSurfaceVariant }) + icone("olho", 592, 112, c.onSurfaceVariant) + valor(144, 190, "1.284", "90", 48) +
    txt(144, 222, "Entrou R$ 6.200,00 · Saiu R$ 4.915,10", { t: 13, cor: c.onSurfaceVariant }) +
    rr(144, 244, 472, 12, 6, c.surfaceContainerHighest) + rr(144, 244, 212, 12, 6, c.essencial) + rr(358, 244, 94, 12, 0, c.importante) + rr(454, 244, 67, 12, 0, c.flexivel) +
    [["Essencial", 3, c.essencial, 144, "R$ 2.790,00"], ["Importante", 2, c.importante, 306, "R$ 1.240,10"], ["Flexível", 1, c.flexivel, 470, "R$ 885,00"]]
      .map(([n, q, cor, x, v]) => pintas(x + 4, 284, q, cor) + txt(x + 42, 288, n, { t: 13 }) + txt(x + 42, 304, v, { t: 12, cor: c.onSurfaceVariant })).join("");
  s += pacoca("acenando", 166, 440, 104) + `<path d="M236 348h384a20 20 0 0 1 20 20v52a20 20 0 0 1-20 20H222a6 6 0 0 1-6-6v-66a20 20 0 0 1 20-20Z" fill="${c.primaryContainer}"/>` +
    linhas(240, 384, ["Mercado ficou 12% abaixo do mês passado.", "Bom ritmo!"], { t: 17, p: 500, f: "'Baloo 2', ui-rounded, system-ui, sans-serif", cor: c.onPrimaryContainer }, 26);
  s += cartao(120, 472, 520, 296) + txt(144, 508, "Contas conectadas", { t: 16, p: 600 });
  [["Banco Ipê", "Conta corrente", "3.412", "08", c.tertiary], ["Banco Jatobá", "Cartão de crédito · fatura aberta", "1.130", "55", c.rio]].forEach(([b, t, i, d, cor], k) => { const y = 528 + k * 96;
    s += rr(144, y, 4, 64, 2, cor) + txt(164, y + 22, b, { t: 16, p: 600 }) + txt(164, y + 42, t, { t: 12, cor: c.onSurfaceVariant }) + valor(616, y + 34, i, d, 24, { a: "end" }) +
      `<circle cx="168" cy="${y + 58}" r="4" fill="${c.mata}"/>` + txt(180, y + 62, "Sincronizado hoje às 18:40", { t: 12, cor: c.onSurfaceVariant }); });
  s += txt(144, 744, "Conectar outro banco", { p: 600, cor: c.primary });
  s += cartao(672, 96, 576, 348) + txt(696, 132, "Últimos lançamentos", { t: 16, p: 600 }) + txt(1224, 132, "Ver tudo", { p: 600, cor: c.primary, a: "end" });
  [["Mercado da Vila", "Alimentação · Débito · Banco Ipê", "R$ 187,43", {}], ["Posto Estrela", "Transporte · Crédito · Banco Jatobá", "R$ 210,00", { cat: "transporte", banco: c.rio, ic: "carro" }],
    ["Salário", "Entrada · Pix · Banco Ipê", "+R$ 6.200,00", { entrada: true, ic: "seta" }], ["Loja 0387", "Compras · Crédito · Banco Jatobá", "R$ 64,90", { cat: "compras", banco: c.rio, ic: "sacola" }]]
    .forEach(([n, i, v, o], k) => { const y = 148 + k * 68; s += lancamento(696, y, 528, n, i, v, o) + (k < 3 ? `<path d="M696 ${y + 62}H1224" stroke="${c.outlineVariant}"/>` : ""); });
  // Rosca: até 5 categorias e Outros.
  const gastos = [["moradia", "Moradia", 1800], ["alimentacao", "Alimentação", 960], ["transporte", "Transporte", 520], ["compras", "Compras", 420], ["saude", "Saúde", 310], ["outros", "Outros", 905.1]];
  const tot = gastos.reduce((a, g) => a + g[2], 0), R = 70, C = 2 * Math.PI * R;
  let ini = 0;
  s += cartao(672, 472, 576, 296) + txt(696, 508, "Para onde foi", { t: 16, p: 600 }) + txt(1224, 508, "Ver análise", { p: 600, cor: c.primary, a: "end" });
  for (const [id, , v] of gastos) { const L = (v / tot) * C;
    s += `<circle cx="800" cy="640" r="${R}" fill="none" stroke="${c.g[id]}" stroke-width="28" stroke-dasharray="${(L - 2).toFixed(1)} ${C.toFixed(1)}" stroke-dashoffset="${(-ini).toFixed(1)}" transform="rotate(-90 800 640)"/>`; ini += L; }
  s += txt(800, 638, "R$ 4.915,10", { t: 15, p: 600, a: "middle" }) + txt(800, 656, "em novembro", { t: 11, a: "middle", cor: c.onSurfaceVariant });
  gastos.forEach(([id, n, v], k) => { const y = 548 + k * 34;
    s += `<circle cx="928" cy="${y}" r="6" fill="${c.g[id]}"/>` + txt(946, y + 5, n, { t: 14 }) + txt(1224, y + 5, `R$ ${v.toFixed(2).replace(".", ",").replace(/\B(?=(\d{3})+(?!\d))/g, ".")}`, { t: 14, p: 600, a: "end" }); });
  return { W, H, s };
}

const G = 32, LEG = 44;
for (const tema of ["claro", "escuro"]) {
  usar(tema);
  for (const [nome, de] of [["trilha-1", 0], ["trilha-2", 5]]) {
    const corpo = [0, 1, 2, 3, 4].map((i) => `<g transform="translate(${G + i * (CEL.w + G)} ${G})">${telaTrilha(de + i)}</g>`).join("");
    grava(import.meta.url, `${nome}-${tema}`, 5 * (CEL.w + G) + G, CEL.h + G + LEG + 12, corpo, `Trilha até a toca, etapas ${de + 1} a ${de + 5}, tema ${tema}`);
  }
  const telas = [[inicio(), "Início"], [inicio({ oculto: true }), "Início com os valores ocultos"], [inicio({ vazio: true }), "Início no primeiro dia"]];
  grava(import.meta.url, `inicio-${tema}`, 3 * (CEL.w + G) + G, CEL.h + G + LEG + 12,
    telas.map(([t, l], i) => `<g transform="translate(${G + i * (CEL.w + G)} ${G})">${celular(0, 0, t, l)}</g>`).join(""), `Início no celular, tema ${tema}`);
  const d = inicioDesktop();
  grava(import.meta.url, `inicio-desktop-${tema}`, d.W, d.H, d.s, `Início no desktop, tema ${tema}`);
}
console.log("8 folhas gravadas em docs/design/telas");
