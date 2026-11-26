// Telas C (Identidade Toca Editorial): chat com a Paçoca, nota fiscal e dinheiro físico, planejamento e alertas,
// configurações e modo demo (claro e escuro).
// Uso: node docs/design/telas/gerar-telas-c.mjs
import { c, usar, txt, linhas, marca, MARCA, rr, icone, pintas, pacoca, pacocaEditorial, botao, campo, chipGrande, cartao, nav, celular, grava, CEL, ICONE_CATEGORIA, brl, lancamento } from "./kit.mjs";

const G = 32, LEG = 44;

// ---------- Peças comuns ----------
const risca = (x1, y, x2) => `<path d="M${x1} ${y}H${x2}" stroke="${c.outlineVariant}"/>`;
const escurecer = () => rr(0, 0, CEL.w, CEL.h, 0, c.scrim, { op: 0.5 });
const folhaInf = (y0) => rr(0, y0, CEL.w, CEL.h - y0 + 40, 28, c.surfaceContainerLow, { borda: c.outlineVariant }) + rr(150, y0 + 10, 60, 5, 2.5, c.outline);
const negGrande = (x, y, v, t, o = {}) => {
  const [i, d] = brl(v).split(",");
  return txt(x, y, `-R$ ${i}<tspan font-size="${Math.round(t * 0.56)}">,${d}</tspan>`, { t, p: 700, ...o });
};
const topo = (titulo, { subt, acao } = {}) =>
  icone("voltar", 14, 40, c.onSurface, 24, 2) + marca(52, 60, titulo, { t: 20 }) +
  (subt ? txt(52, 80, subt, { t: 12, cor: c.onSurfaceVariant }) : "") +
  (acao ? txt(344, 60, acao, { t: 14, p: 600, cor: c.primary, a: "end" }) : "");
const NIVEL = () => ({ Essencial: [3, c.essencial], Importante: [2, c.importante], "Flexível": [1, c.flexivel] });
const nivel = (x, y, nome) => { const [q, cor] = NIVEL()[nome]; return pintas(x + 4, y - 4, q, cor) + txt(x + 42, y, nome, { t: 11, cor: c.onSurfaceVariant }); };
const catCirculo = (cx, cy, cat, d = 28) =>
  `<circle cx="${cx}" cy="${cy}" r="${d / 2}" fill="${c.g[cat]}" opacity="0.14"/>` +
  icone(ICONE_CATEGORIA[cat], cx - d * 0.36, cy - d * 0.36, c.g[cat], Math.round(d * 0.72), 1.8);
const chave = (x, y, on) =>
  rr(x, y, 52, 32, 16, on ? c.primary : c.surfaceContainerHighest, { borda: on ? undefined : c.outline, lb: 2 }) +
  `<circle cx="${on ? x + 36 : x + 16}" cy="${y + 16}" r="${on ? 12 : 8}" fill="${on ? c.onPrimary : c.outline}"/>` +
  (on ? icone("check", x + 28, y + 8, c.primary, 16, 2.6) : "");
const fila = (x, y, lista) => {
  let xx = x, s = "";
  for (const [l, sel] of lista) { const [svg, w] = chipGrande(xx, y, l, sel); s += svg; xx += w + 8; }
  return s;
};
const chipCat = (x, y, label, cat, sel) => {
  const w = Math.round(label.length * 6.9 + 42);
  return [rr(x, y, w, 40, 12, sel ? c.secondaryContainer : "none", { borda: sel ? c.primary : c.outline, lb: sel ? 2 : 1 }) +
    `<circle cx="${x + 16}" cy="${y + 20}" r="6" fill="${c.g[cat]}"/>` +
    txt(x + 30, y + 25, label, { t: 13, p: sel ? 600 : 400, cor: sel ? c.onSecondaryContainer : c.onSurface }), w];
};
const linhaCfg = (x, y, ic, titulo, subt, fim = "") =>
  `<circle cx="${x + 20}" cy="${y + 28}" r="20" fill="${c.secondaryContainer}"/>` + icone(ic, x + 8, y + 16, c.onSecondaryContainer, 24, 1.8) +
  txt(x + 52, y + 25, titulo, { t: 14, p: 600 }) + txt(x + 52, y + 44, subt, { t: 12, cor: c.onSurfaceVariant }) + fim;
const fimDireita = (y) => icone("direita", 316, y, c.onSurfaceVariant, 20, 2);

// ---------- Chat ----------
const cabecaChat = (subt, extra = "") =>
  pacocaEditorial("retrato", 44, 79, 0.42) + marca(72, 50, "Pergunte pra Paçoca", { t: 18 }) +
  txt(72, 70, subt, { t: 12, cor: c.onSurfaceVariant }) + extra + icone("editar", 316, 36, c.onSurface, 24, 1.8) + risca(0, 92, 360);
const balaoPaco = (y, w, ls) => rr(16, y, w, ls.length * 20 + 22, 18, c.tertiaryContainer) + linhas(30, y + 27, ls, { t: 14, cor: c.onTertiaryContainer }, 20);
const balaoBia = (y, w, ls) => rr(344 - w, y, w, ls.length * 20 + 22, 18, c.primaryContainer) + linhas(358 - w, y + 27, ls, { t: 14, cor: c.onPrimaryContainer }, 20);
const avisoIA = (y) => icone("escudo", 16, y - 12, c.onSurfaceVariant, 14, 2) +
  txt(36, y, "Só totais e categorias vão para a IA.", { t: 11, cor: c.onSurfaceVariant }) + txt(344, y, "Saiba mais", { t: 11, p: 600, cor: c.primary, a: "end" });
const compositor = (texto, { parar } = {}) =>
  rr(16, 608, 268, 56, 12, c.surfaceContainerLowest, { borda: c.outline }) + txt(32, 642, texto, { t: 15, cor: c.onSurfaceVariant }) +
  (parar
    ? `<circle cx="320" cy="636" r="24" fill="none" stroke="${c.primary}" stroke-width="2"/>` + rr(311, 627, 18, 18, 4, c.primary)
    : `<circle cx="320" cy="636" r="24" fill="${c.primary}"/>` + icone("enviar", 308, 624, c.onPrimary, 24, 2));

function chat1() {
  const w = 306;
  return cabecaChat("Responde com os números do app") +
    balaoPaco(104, w, ["Oi, Bia! Pergunte sobre seus gastos.", "Eu respondo com os números do app."]) +
    balaoBia(178, 210, ["Quanto gastei com mercado", "em novembro?"]) +
    balaoPaco(252, w, ["Em novembro, o mercado ficou", "mais leve que em outubro."]) +
    cartao(16, 322, w, 176) +
    txt(32, 346, "Mercado · 1 a 26 de novembro", { t: 12, p: 600, cor: c.onSurfaceVariant }) +
    negGrande(32, 384, 612.3, 30) +
    txt(32, 406, "5 compras · 12% abaixo de outubro", { t: 12, cor: c.onSurfaceVariant }) +
    txt(32, 434, "Out", { t: 12, cor: c.onSurfaceVariant }) + rr(64, 425, 170, 10, 5, c.g.alimentacao, { op: 0.4 }) + txt(306, 434, "R$ 695,80", { t: 12, a: "end" }) +
    txt(32, 456, "Nov", { t: 12, cor: c.onSurfaceVariant }) + rr(64, 447, 150, 10, 5, c.g.alimentacao) + txt(306, 456, "R$ 612,30", { t: 12, p: 600, a: "end" }) +
    risca(32, 468, 306) + txt(32, 488, "Ver transações", { t: 13, p: 600, cor: c.primary }) + icone("direita", 132, 475, c.primary, 16, 2.2) +
    icone("cadeado", 18, 506, c.onSurfaceVariant, 14, 2) + txt(38, 517, "Números calculados no seu servidor", { t: 11, cor: c.onSurfaceVariant }) +
    fila(16, 534, [["Quanto sobrou?", false], ["Assinaturas", false], ["Delivery", false], ["Maior gasto", false]]) +
    avisoIA(598) + compositor("Pergunte sobre seus gastos") + nav(676, "Paçoca");
}

function chat2() {
  const w = 306;
  return cabecaChat("Pensando", pintas(142, 66, 2, c.tertiary, c.tertiary)) +
    balaoBia(104, 200, ["Quanto sobrou este mês?"]) +
    balaoPaco(158, w, ["Sobrou bastante em novembro."]) +
    cartao(16, 212, w, 104) +
    txt(32, 236, "Novembro · 1 a 26", { t: 12, p: 600, cor: c.onSurfaceVariant }) +
    txt(32, 274, "R$ 1.284<tspan font-size=\"17\">,90</tspan>", { t: 30, p: 700 }) +
    txt(32, 298, "Entrou R$ 6.200,00 · Saiu R$ 4.915,10", { t: 12, cor: c.onSurfaceVariant }) +
    balaoBia(332, 214, ["O que mais pesou no mês?"]) +
    rr(16, 386, 76, 44, 18, c.tertiaryContainer) + pintas(40, 408, 2, c.onTertiaryContainer, c.onTertiaryContainer) +
    txt(32, 452, "Montando a resposta com os totais do mês.", { t: 12, cor: c.onSurfaceVariant }) +
    avisoIA(598) + compositor("Pensando…", { parar: true }) + nav(676, "Paçoca");
}

function chat3() {
  const itens = ["Quanto sobrou este mês?", "Maiores gastos da semana", "Assinaturas do mês", "Comparar com outubro", "Faturas dos cartões"];
  return cabecaChat("Sem IA · perguntas prontas") +
    balaoPaco(104, 306, ["A IA está desligada. Use as perguntas", "prontas: eu calculo tudo aqui, sem", "enviar nada para fora."]) +
    txt(18, 214, "Perguntas prontas", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    cartao(16, 224, 328, 244) +
    itens.map((t, i) => {
      const y = 226 + i * 48;
      return txt(32, y + 29, t, { t: 14 }) + icone("direita", 312, y + 12, c.onSurfaceVariant, 20, 2) + (i < 4 ? risca(32, y + 48, 328) : "");
    }).join("") +
    cartao(16, 490, 328, 118) + icone("brilho", 32, 504, c.tertiary, 20, 1.8) +
    txt(60, 520, "Para escrever livremente, ligue um", { t: 13 }) + txt(60, 538, "provedor de IA com a sua chave.", { t: 13 }) +
    botao(32, 552, 168, "Configurar IA", "tonal") +
    `<g opacity="0.38">${rr(16, 616, 328, 48, 12, c.surfaceContainer, { borda: c.outline })}${txt(32, 646, "Escrever uma pergunta", { t: 15, cor: c.onSurfaceVariant })}</g>` +
    nav(676, "Paçoca");
}

function chat4() {
  const item = (y, ic, cor, t) => icone(ic, 16, y - 15, cor, 18, 2.2) + txt(44, y, t, { t: 13 });
  return cabecaChat("Responde com os números do app") +
    balaoPaco(104, 306, ["Oi, Bia! Pergunte sobre seus gastos.", "Eu respondo com os números do app."]) +
    escurecer() + folhaInf(112) +
    txt(16, 162, "O que vai para a IA", { t: 20, p: 600 }) +
    linhas(16, 186, ["Só o necessário para responder.", "Você troca o provedor quando quiser."], { t: 13, cor: c.onSurfaceVariant }, 18) +
    txt(16, 240, "Vai junto com a sua pergunta", { t: 13, p: 600 }) +
    item(266, "check", c.mata, "Totais por categoria e período") +
    item(292, "check", c.mata, "O rótulo de essencialidade") +
    item(318, "check", c.mata, "A sua pergunta, em texto") +
    txt(16, 358, "Fica só no seu servidor", { t: 13, p: 600 }) +
    item(384, "cadeado", c.onSurfaceVariant, "Nome do estabelecimento e descrição") +
    item(410, "cadeado", c.onSurfaceVariant, "Banco, conta e número do cartão") +
    item(436, "cadeado", c.onSurfaceVariant, "Fotos e PDFs das notas fiscais") +
    item(462, "cadeado", c.onSurfaceVariant, "Seu nome e e-mail") +
    rr(16, 484, 328, 56, 16, c.surfaceContainer, { borda: c.outlineVariant }) +
    txt(32, 508, "Enviar só percentuais", { t: 14, p: 600 }) + txt(32, 526, "Os valores em reais não saem daqui.", { t: 12, cor: c.onSurfaceVariant }) +
    chave(276, 496, false) +
    botao(16, 560, 328, "Entendi") + txt(180, 640, "Trocar provedor de IA", { t: 14, p: 600, cor: c.primary, a: "middle" });
}

// ---------- Nota fiscal e dinheiro físico ----------
function qrFalso(cx, cy) {
  const n = 17, cel = 9, x0 = cx - (n * cel) / 2, y0 = cy - (n * cel) / 2;
  let seed = 11, d = "";
  const rnd = () => (seed = (seed * 1664525 + 1013904223) % 4294967296) / 4294967296;
  const busca = (i, j) => (i < 7 && j < 7) || (i > n - 8 && j < 7) || (i < 7 && j > n - 8);
  for (let j = 0; j < n; j++) for (let i = 0; i < n; i++) {
    if (busca(i, j)) continue;
    if (rnd() > 0.5) d += `M${x0 + i * cel} ${y0 + j * cel}h${cel}v${cel}h-${cel}Z`;
  }
  const quina = (i, j) => {
    const x = x0 + i * cel, y = y0 + j * cel;
    return `<rect x="${x}" y="${y}" width="${7 * cel}" height="${7 * cel}" fill="${c.onSurfaceVariant}"/>` +
      `<rect x="${x + cel}" y="${y + cel}" width="${5 * cel}" height="${5 * cel}" fill="${c.surfaceContainerHighest}"/>` +
      `<rect x="${x + 2 * cel}" y="${y + 2 * cel}" width="${3 * cel}" height="${3 * cel}" fill="${c.onSurfaceVariant}"/>`;
  };
  return `<path d="${d}" fill="${c.onSurfaceVariant}"/>` + quina(0, 0) + quina(n - 7, 0) + quina(0, n - 7);
}
const moldura = (cx, cy, l, k) => {
  const x0 = cx - l / 2, y0 = cy - l / 2, x1 = cx + l / 2, y1 = cy + l / 2;
  const q = (d) => `<path d="${d}" fill="none" stroke="${c.primary}" stroke-width="4" stroke-linecap="round" stroke-linejoin="round"/>`;
  return q(`M${x0} ${y0 + k}V${y0}H${x0 + k}`) + q(`M${x1 - k} ${y0}H${x1}V${y0 + k}`) + q(`M${x0} ${y1 - k}V${y1}H${x0 + k}`) + q(`M${x1 - k} ${y1}H${x1}V${y1 - k}`);
};
const visor = () => rr(16, 150, 328, 280, 20, c.surfaceContainerHighest, { borda: c.outlineVariant }) + qrFalso(180, 282) + moldura(180, 282, 190, 28);

function nota1() {
  return topo("Ler nota fiscal") + fila(16, 92, [["QR Code", true], ["Foto", false], ["PDF", false]]) + visor() +
    txt(180, 420, "Aponte para o QR Code da nota", { t: 12, a: "middle", cor: c.onSurfaceVariant }) +
    cartao(16, 446, 328, 114) + pacoca("lupa", 66, 548, 96) +
    marca(116, 484, "Lendo a nota…", { t: 16 }) +
    linhas(116, 508, ["Quando o QR Code entrar na", "moldura, eu leio sozinha."], { t: 13, cor: c.onSurfaceVariant }, 18) +
    pintas(120, 546, 2, c.primary) +
    botao(16, 580, 328, "Digitar a chave de acesso", "contorno") +
    txt(180, 664, "Escolher da galeria", { t: 14, p: 600, cor: c.primary, a: "middle" });
}

function nota2() {
  const y0 = 312;
  return topo("Ler nota fiscal") + fila(16, 92, [["QR Code", true], ["Foto", false], ["PDF", false]]) + visor() +
    escurecer() + folhaInf(y0) +
    pacoca("cadeado", 62, y0 + 112, 92) +
    marca(110, y0 + 52, "Posso ler os", { t: 18 }) + marca(110, y0 + 76, "itens da nota?", { t: 18 }) +
    linhas(16, y0 + 148, ["Os itens podem mostrar restrições", "alimentares, que são dados de saúde.", "Só uso para escolher a categoria", "de cada item. Fica no seu servidor."], { t: 14 }, 20) +
    txt(16, y0 + 236, "Dá para mudar em Configurações > Privacidade.", { t: 12, cor: c.onSurfaceVariant }) +
    botao(16, y0 + 252, 328, "Permitir leitura dos itens") +
    botao(16, y0 + 308, 328, "Agora não, usar só o total", "contorno");
}

function nota3() {
  const itens = [
    ["alimentacao", "Arroz 5 kg", "Alimentação", "Essencial", 29.9],
    ["alimentacao", "Feijão 1 kg", "Alimentação", "Essencial", 8.49],
    ["alimentacao", "Frango, 2 bandejas", "Alimentação", "Essencial", 38.7],
    ["alimentacao", "Refrigerante, 2 un.", "Alimentação", "Flexível", 17.8],
    ["moradia", "Sabão em pó", "Moradia", "Importante", 21.9],
  ];
  let s = topo("Nota do Mercado da Vila", { subt: "NFC-e · 26 de novembro · Débito Banco Ipê" }) +
    cartao(16, 96, 328, 72) + txt(32, 122, "Total da nota", { t: 12, p: 600, cor: c.onSurfaceVariant }) + negGrande(32, 154, 187.43, 24) +
    `<circle cx="262" cy="140" r="11" fill="${c.mata}" opacity="0.16"/>` + icone("check", 256, 134, c.mata, 12, 3) +
    txt(280, 144, "Confere", { t: 12, p: 600, cor: c.mata }) +
    txt(18, 192, "9 itens", { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(16, 202, 328, 280);
  itens.forEach(([cat, nome, catNome, niv, v], i) => {
    const y = 204 + i * 46;
    s += catCirculo(44, y + 23, cat, 28) + txt(68, y + 20, nome, { t: 14, p: 600 }) +
      txt(68, y + 37, catNome, { t: 11, cor: c.onSurfaceVariant }) + nivel(148, y + 37, niv) +
      txt(328, y + 27, `-R$ ${brl(v)}`, { t: 14, p: 600, a: "end" }) + (i < 4 ? risca(32, y + 46, 328) : "");
  });
  s += risca(32, 434, 328) + txt(32, 463, "Mais 4 itens", { t: 14, p: 600, cor: c.primary }) +
    txt(300, 463, "-R$ 70,64", { t: 14, p: 600, a: "end" }) + icone("direita", 308, 449, c.onSurfaceVariant, 20, 2) +
    cartao(16, 494, 328, 128) + txt(32, 520, "Dividir por categoria", { t: 14, p: 600 }) +
    rr(32, 534, 296, 12, 6, c.surfaceContainerHighest) + rr(32, 534, 231, 12, 6, c.g.alimentacao) + rr(265, 534, 63, 12, 6, c.g.moradia) +
    `<circle cx="38" cy="570" r="6" fill="${c.g.alimentacao}"/>` + txt(52, 575, "Alimentação", { t: 13 }) + txt(328, 575, "-R$ 147,03 · 78%", { t: 13, p: 600, a: "end" }) +
    `<circle cx="38" cy="594" r="6" fill="${c.g.moradia}"/>` + txt(52, 599, "Moradia", { t: 13 }) + txt(328, 599, "-R$ 40,40 · 22%", { t: 13, p: 600, a: "end" }) +
    txt(32, 616, "O extrato mostra 2 linhas; o total não muda.", { t: 11, cor: c.onSurfaceVariant }) +
    botao(16, 636, 328, "Salvar divisão");
  return s;
}

function dinheiro() {
  const teclas = ["1", "2", "3", "4", "5", "6", "7", "8", "9", ",", "0", "apagar"];
  let s = topo("Gasto em dinheiro", { subt: "Sai de Dinheiro físico" }) +
    txt(180, 118, "Quanto foi?", { t: 13, a: "middle", cor: c.onSurfaceVariant }) +
    txt(180, 168, "-R$ 23<tspan font-size=\"25\">,50</tspan>", { t: 44, p: 700, a: "middle" });
  let x = 16;
  for (const [l, cat, sel] of [["Alimentação", "alimentacao", true], ["Transporte", "transporte", false], ["Lazer", "lazer", false]]) {
    const [svg, w] = chipCat(x, 188, l, cat, sel); s += svg; x += w + 8;
  }
  s += campo(16, 262, 328, "Onde foi? (opcional)", "Padaria Sol Nascente") +
    rr(16, 334, 328, 48, 12, "none", { borda: c.outline }) + icone("camera", 32, 346, c.primary, 24, 1.8) +
    txt(68, 364, "Anexar foto do recibo (opcional)", { t: 14, p: 600, cor: c.primary });
  teclas.forEach((k, i) => {
    const kx = 16 + (i % 3) * 112, ky = 398 + Math.floor(i / 3) * 56;
    s += rr(kx, ky, 104, 48, 12, c.surfaceContainerHigh) +
      (k === "apagar" ? icone("voltar", kx + 40, ky + 12, c.onSurface, 24, 2) : txt(kx + 52, ky + 32, k, { t: 22, p: 600, a: "middle" }));
  });
  s += botao(16, 624, 328, "Salvar") +
    rr(16, 684, 328, 52, 14, c.surfaceContainer, { borda: c.outlineVariant }) + icone("semRede", 30, 698, c.onSurfaceVariant, 22, 1.8) +
    linhas(64, 706, ["Sem internet? Tudo bem: fica salvo no", "aparelho e segue quando a rede voltar."], { t: 12, cor: c.onSurfaceVariant }, 17);
  return s;
}

// ---------- Planejamento e alertas ----------
function planejamento() {
  const orc = [["alimentacao", "Alimentação", 960, 1100], ["transporte", "Transporte", 520, 450], ["compras", "Compras", 420, 600], ["saude", "Saúde", 310, 400]];
  let s = marca(20, 62, "Gastos", { t: 26 }) +
    rr(16, 78, 328, 44, 22, "none", { borda: c.outline }) + rr(182, 80, 160, 40, 20, c.secondaryContainer) +
    txt(98, 105, "Análise", { t: 14, p: 600, a: "middle", cor: c.onSurfaceVariant }) +
    icone("check", 200, 91, c.onSecondaryContainer, 18, 2.4) + txt(268, 105, "Planejamento", { t: 14, p: 600, a: "middle", cor: c.onSecondaryContainer }) +
    icone("voltar", 16, 134, c.onSurfaceVariant, 20, 2) + txt(180, 150, "Novembro 2026", { t: 15, p: 600, a: "middle" }) + icone("direita", 324, 134, c.onSurfaceVariant, 20, 2) +
    cartao(16, 162, 328, 272) + txt(32, 192, "Orçamentos do mês", { t: 16, p: 600 }) + txt(328, 192, "Editar", { t: 13, p: 600, cor: c.primary, a: "end" });
  orc.forEach(([cat, nome, gasto, lim], i) => {
    const y = 206 + i * 56, estourou = gasto > lim, pct = Math.min(1, gasto / lim);
    s += catCirculo(40, y + 12, cat, 28) + txt(64, y + 16, nome, { t: 14, p: 600 }) +
      txt(328, y + 16, `R$ ${brl(gasto)} de R$ ${brl(lim)}`, { t: 12, cor: c.onSurfaceVariant, a: "end" }) +
      rr(64, y + 26, 264, 8, 4, c.surfaceContainerHighest) + rr(64, y + 26, Math.round(264 * pct), 8, 4, estourou ? c.error : c.g[cat]) +
      (estourou
        ? icone("alerta", 64, y + 38, c.error, 14, 2) + txt(82, y + 50, `Passou R$ ${brl(gasto - lim)}`, { t: 12, p: 600, cor: c.error })
        : txt(64, y + 50, `Restam R$ ${brl(lim - gasto)}`, { t: 12, cor: c.onSurfaceVariant }));
  });
  s += cartao(16, 446, 328, 222) + txt(32, 476, "Metas", { t: 16, p: 600 });
  [["Reserva de emergência", 4200, 6000, "até 30 jun 2027"], ["Viagem de fim de ano", 900, 1500, "até 15 dez 2026"]].forEach(([nome, atual, alvo, prazo], i) => {
    const m = 490 + i * 76;
    s += txt(32, m + 16, nome, { t: 14, p: 600 }) + txt(328, m + 16, `${Math.round((atual / alvo) * 100)}%`, { t: 13, p: 600, a: "end" }) +
      rr(32, m + 26, 296, 8, 4, c.surfaceContainerHighest) + rr(32, m + 26, Math.round(296 * (atual / alvo)), 8, 4, c.mata) +
      txt(32, m + 50, `R$ ${brl(atual)} de R$ ${brl(alvo)}`, { t: 12 }) +
      txt(32, m + 66, `Faltam R$ ${brl(alvo - atual)} · ${prazo}`, { t: 12, cor: c.onSurfaceVariant });
  });
  s += txt(32, 654, "Nova meta", { t: 13, p: 600, cor: c.primary });
  return s + nav(676, "Gastos");
}

function novoAlerta() {
  const linhasAl = [["Gastos em", "Alimentação › Delivery"], ["Passar de", "R$ 300,00"], ["Período", "Por mês (novembro)"], ["Avisar", "No sino e no celular"]];
  let s = topo("Novo alerta") + txt(18, 104, "Escreva do seu jeito", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    rr(16, 114, 328, 96, 12, c.surfaceContainerLowest, { borda: c.primary, lb: 2 }) +
    linhas(32, 146, ["Me avise quando o delivery", "passar de R$ 300 por mês"], { t: 16 }, 24) +
    `<path d="M226 156V176" stroke="${c.primary}" stroke-width="2"/>` +
    icone("escudo", 18, 220, c.onSurfaceVariant, 14, 2) + txt(38, 231, "Só o texto da frase vai para a IA.", { t: 11, cor: c.onSurfaceVariant }) +
    txt(18, 268, "Entendi assim", { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(16, 278, 328, 164);
  linhasAl.forEach(([k, v], i) => {
    const y = 290 + i * 38;
    s += txt(32, y + 22, k, { t: 12, cor: c.onSurfaceVariant }) + txt(124, y + 22, v, { t: 14, p: 600 }) + icone("editar", 304, y + 6, c.onSurfaceVariant, 20, 1.8) + (i < 3 ? risca(32, y + 36, 328) : "");
  });
  return s + txt(18, 474, "Ou comece por um destes", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    fila(16, 486, [["Fatura alta", false], ["Conexão vencendo", false]]) + fila(16, 538, [["Saldo abaixo de R$ 200", false]]) +
    botao(16, 604, 328, "Criar alerta") + txt(180, 678, "Cancelar", { t: 14, p: 600, cor: c.primary, a: "middle" });
}

function alertas() {
  const item = (y, ic, titulo, ls, acao, hora, novo) =>
    cartao(16, y, 328, 100) + `<circle cx="44" cy="${y + 30}" r="18" fill="${c.secondaryContainer}"/>` + icone(ic, 34, y + 20, c.onSecondaryContainer, 20, 1.8) +
    txt(72, y + 28, titulo, { t: 14, p: 600 }) + txt(328, y + 28, hora, { t: 11, cor: c.onSurfaceVariant, a: "end" }) +
    linhas(72, y + 48, ls, { t: 12, cor: c.onSurfaceVariant }, 16) + txt(72, y + 88, acao, { t: 13, p: 600, cor: c.primary }) +
    (novo ? rr(284, y + 74, 44, 20, 10, c.primaryContainer) + txt(306, y + 88, "Novo", { t: 11, p: 600, a: "middle", cor: c.onPrimaryContainer }) : "");
  return topo("Alertas", { acao: "Marcar como lidos" }) +
    cartao(16, 92, 328, 160) + pacoca("preocupada", 58, 242, 96) +
    marca(108, 124, "Conexão vencendo", { t: 15 }) + rr(268, 106, 60, 24, 12, c.milho) + txt(298, 122, "7 dias", { t: 12, p: 600, cor: c.sobreMilho, a: "middle" }) +
    linhas(108, 148, ["A conexão com o Banco Jatobá", "vence em 7 dias. Renove para", "não perder nada."], { t: 13, cor: c.onSurfaceVariant }, 18) +
    botao(108, 192, 220, "Renovar no Meu Pluggy", "tonal") +
    txt(18, 280, "Novos", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    item(290, "cartao", "Fatura acima da média", ["R$ 1.130,55 contra média de", "R$ 940,00. Bora ver o que pesou?"], "Ver compras", "há 2 h", true) +
    item(398, "alerta", "Delivery passou de R$ 300", ["Foram R$ 342,80 este mês.", "Quer ver os pedidos?"], "Ver pedidos", "ontem", true) +
    txt(18, 524, "Antes", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    cartao(16, 534, 328, 76) + `<circle cx="44" cy="568" r="18" fill="${c.secondaryContainer}"/>` + icone("alvo", 34, 558, c.onSecondaryContainer, 20, 1.8) +
    txt(72, 562, "Meta batida!", { t: 14, p: 600 }) + txt(328, 562, "há 3 dias", { t: 11, cor: c.onSurfaceVariant, a: "end" }) +
    txt(72, 584, "Você completou a meta de outubro.", { t: 12, cor: c.onSurfaceVariant }) +
    botao(16, 628, 328, "Criar alerta", "contorno");
}

// ---------- Configurações e modo demo ----------
function config1() {
  const faixa = (y, cor) => rr(28, y, 4, 36, 2, cor);
  let s = topo("Configurações") +
    cartao(16, 84, 328, 68) + `<circle cx="48" cy="118" r="20" fill="${c.primaryContainer}"/>` + txt(48, 124, "B", { t: 16, p: 700, f: MARCA, a: "middle", cor: c.onPrimaryContainer }) +
    txt(80, 113, "Bia · bia@exemplo.com", { t: 14, p: 600 }) + txt(80, 133, "Meu servidor · conectado", { t: 12, cor: c.onSurfaceVariant }) +
    `<circle cx="324" cy="118" r="5" fill="${c.mata}"/>` +
    txt(18, 176, "Bancos e consentimento", { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(16, 186, 328, 152) +
    faixa(196, c.tertiary) + txt(44, 213, "Banco Ipê", { t: 14, p: 600 }) + txt(44, 232, "Consentimento até 12 mar 2027", { t: 12, cor: c.onSurfaceVariant }) +
    icone("check", 268, 206, c.mata, 18, 2.6) + txt(292, 219, "Ativo", { t: 12, p: 600, cor: c.mata }) + risca(32, 242, 328) +
    faixa(252, c.rio) + txt(44, 269, "Banco Jatobá", { t: 14, p: 600 }) + txt(44, 288, "Vence em 7 dias", { t: 12, cor: c.onSurfaceVariant }) +
    rr(252, 258, 76, 28, 14, c.milho) + txt(290, 277, "Renovar", { t: 12, p: 600, cor: c.sobreMilho, a: "middle" }) + risca(32, 298, 328) +
    icone("fora", 32, 308, c.primary, 20, 2) + txt(60, 323, "Abrir o Meu Pluggy", { t: 14, p: 600, cor: c.primary }) +
    txt(18, 362, "Provedor de IA", { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(16, 372, 328, 104) +
    linhaCfg(28, 372, "brilho", "Minha própria chave", "Guardada só neste aparelho", fimDireita(388)) + risca(32, 428, 328) +
    icone("escudo", 32, 440, c.onSurfaceVariant, 20, 1.8) + txt(60, 457, "O que vai para a IA", { t: 14, p: 600 }) + fimDireita(440) +
    txt(18, 500, "Privacidade", { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(16, 510, 328, 168);
  [["cadeado", "Biometria do aparelho", "Pede digital ou rosto ao abrir", true], ["olho", "Esconder valores", "Mostra R$ ••• em todo o app", false], ["escudo", "Tela oculta no seletor", "Fica em branco ao trocar de app", true]]
    .forEach(([ic, t, sb, on], i) => { s += linhaCfg(28, 510 + i * 56, ic, t, sb, chave(280, 522 + i * 56, on)) + (i < 2 ? risca(32, 566 + i * 56, 328) : ""); });
  return s;
}

function demo() {
  return rr(0, 28, 360, 44, 0, c.milho) + icone("info", 16, 38, c.sobreMilho, 24, 2) +
    txt(48, 55, "Modo demo · dados fictícios", { t: 13, p: 600, cor: c.sobreMilho }) + txt(344, 55, "Sair da demo", { t: 12, p: 600, cor: c.sobreMilho, a: "end" }) +
    marca(20, 108, "Boa noite, Bia", { t: 26 }) + txt(20, 126, "Bia é uma pessoa fictícia", { t: 12, cor: c.onSurfaceVariant }) +
    icone("sino", 314, 84, c.onSurface) +
    cartao(16, 138, 328, 170) + txt(32, 168, "Sobrou este mês", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    txt(32, 214, "R$ 1.284<tspan font-size=\"21\">,90</tspan>", { t: 38, p: 700 }) +
    txt(32, 240, "Entrou R$ 6.200,00 · Saiu R$ 4.915,10", { t: 12, cor: c.onSurfaceVariant }) +
    rr(32, 256, 296, 9, 4.5, c.surfaceContainerHighest) + rr(32, 256, 134, 9, 4.5, c.essencial) + rr(168, 256, 60, 9, 0, c.importante) + rr(230, 256, 42, 9, 0, c.flexivel) +
    [["Essencial", 3, c.essencial, 28], ["Importante", 2, c.importante, 132], ["Flexível", 1, c.flexivel, 246]].map(([n, q, cor, x]) => pintas(x + 4, 290, q, cor) + txt(x + 40, 294, n, { t: 11 })).join("") +
    cartao(16, 320, 328, 90) + pacocaEditorial("retrato", 62, 410, 0.7) +
    linhas(108, 358, ["Aqui tudo é de mentirinha.", "Pode mexer à vontade!"], { t: 14, p: 500, f: MARCA }, 22) +
    cartao(16, 422, 328, 134) +
    lancamento(28, 428, 302, "Mercado da Vila", "Alimentação · Débito", "-R$ 187,43") + risca(28, 490, 332) +
    lancamento(28, 490, 302, "Posto Estrela", "Transporte · Crédito", "-R$ 210,00", { cat: "transporte", banco: c.rio, ic: "carro" }) +
    botao(16, 572, 328, "Criar minha conta", "contorno") +
    txt(180, 644, "Seus dados de verdade ficam só no seu servidor.", { t: 11, a: "middle", cor: c.onSurfaceVariant }) +
    nav(676, "Início");
}

function configDados() {
  return topo("Configurações") +
    txt(18, 100, "Dados", { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(16, 110, 328, 168) +
    linhaCfg(28, 110, "exportar", "Exportar tudo", "Uma cópia em CSV e OFX", fimDireita(126)) + risca(32, 166, 328) +
    linhaCfg(28, 166, "nota", "Importar extrato", "Arquivos OFX ou CSV", fimDireita(182)) + risca(32, 222, 328) +
    linhaCfg(28, 222, "sincronizar", "Refazer o guia inicial", "Ocupação, casa e transporte", fimDireita(238)) +
    txt(18, 304, "Aparelhos conectados", { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(16, 314, 328, 124) +
    linhaCfg(28, 314, "usuario", "Celular da Bia", "Este aparelho · agora", icone("check", 304, 332, c.mata, 20, 2.6)) + risca(32, 372, 328) +
    linhaCfg(28, 374, "banco", "Notebook · Windows", "Último acesso há 3 dias", txt(328 - 12, 405, "Desconectar", { t: 13, p: 600, cor: c.error, a: "end" })) +
    icone("alerta", 18, 462, c.error, 16, 2) + txt(40, 475, "Zona de perigo", { t: 13, p: 600, cor: c.error }) +
    rr(16, 486, 328, 72, 20, c.surfaceContainerLow, { borda: c.error, lb: 1.5 }) +
    txt(32, 515, "Apagar tudo", { t: 15, p: 600, cor: c.error }) + txt(32, 535, "Remove todos os dados deste servidor.", { t: 12, cor: c.onSurfaceVariant }) +
    icone("lixeira", 304, 508, c.error, 24, 1.8) +
    txt(180, 612, "GranaPaCá · licença AGPL-3.0", { t: 11, a: "middle", cor: c.onSurfaceVariant });
}

function apagarTudo() {
  const y = 190;
  return configDados() + escurecer() +
    rr(24, y, 312, 396, 28, c.surfaceContainerLow, { borda: c.outlineVariant }) +
    `<circle cx="64" cy="${y + 48}" r="24" fill="${c.errorContainer}"/>` + icone("lixeira", 52, y + 36, c.onErrorContainer, 24, 1.8) +
    marca(40, y + 106, "Apagar tudo?", { t: 22 }) +
    linhas(40, y + 136, ["Isso remove lançamentos, ajustes,", "comprovantes e configurações deste", "servidor. Não tem volta."], { t: 14 }, 20) +
    txt(40, y + 208, "Dica: exporte uma cópia antes.", { t: 12, cor: c.onSurfaceVariant }) +
    campo(40, y + 252, 280, "Digite apagar para confirmar", "apagar", { foco: true }) +
    botao(40, y + 332, 124, "Cancelar", "contorno") +
    rr(176, y + 332, 144, 48, 24, c.error) + txt(248, y + 361, "Apagar tudo", { p: 600, cor: c.onError, a: "middle" });
}

// ---------- Folhas ----------
const FOLHAS = [
  ["chat", "Chat com a Paçoca no celular", [[chat1, "Resposta com números"], [chat2, "Pensando"], [chat3, "Sem IA, perguntas prontas"], [chat4, "O que vai para a IA"]]],
  ["comprovantes", "Nota fiscal e gasto em dinheiro no celular", [[nota1, "Ler o QR Code"], [nota2, "Consentimento dos itens"], [nota3, "Itens e divisão"], [dinheiro, "Dinheiro físico"]]],
  ["planejamento", "Planejamento e alertas no celular", [[planejamento, "Orçamentos e metas"], [novoAlerta, "Novo alerta"], [alertas, "Alertas"]]],
  ["config", "Configurações e modo demo no celular", [[config1, "Configurações"], [demo, "Modo demo"], [configDados, "Dados e aparelhos"], [apagarTudo, "Apagar tudo"]]],
];

let total = 0;
for (const tema of ["claro", "escuro"]) {
  usar(tema);
  for (const [nome, titulo, telas] of FOLHAS) {
    const corpo = telas.map(([f, legenda], i) => `<g transform="translate(${G + i * (CEL.w + G)} ${G})">${celular(0, 0, f(), legenda)}</g>`).join("");
    grava(import.meta.url, `${nome}-${tema}`, telas.length * (CEL.w + G) + G, CEL.h + G + LEG + 12, corpo, `${titulo}, tema ${tema}`);
    total++;
  }
}
console.log(`${total} folhas gravadas em docs/design/telas`);
