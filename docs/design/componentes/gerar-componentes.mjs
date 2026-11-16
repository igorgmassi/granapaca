// Gera as folhas da biblioteca de componentes em SVG, nos temas claro e escuro, a partir do tokens.json.
// Uso: node docs/design/componentes/gerar-componentes.mjs
// As fontes do app (Baloo 2 e Figtree) só aparecem onde estiverem instaladas; no GitHub entra a fonte do sistema.
import { readFileSync, writeFileSync } from "node:fs";
const T = JSON.parse(readFileSync(new URL("../tokens/tokens.json", import.meta.url), "utf8"));
const INTERFACE = "Figtree, Inter, system-ui, sans-serif", MARCA = "'Baloo 2', ui-rounded, system-ui, sans-serif";
const W = 960;
let c; // cores do tema em uso

const txt = (x, y, s, { t = 14, p = 400, cor = c.onSurface, a = "start", f = INTERFACE } = {}) =>
  `<text x="${x}" y="${y}" font-family="${f}" font-size="${t}" font-weight="${p}" fill="${cor}" text-anchor="${a}">${s}</text>`;
const rr = (x, y, w, h, r, fill, { borda, lb = 1, op, opb } = {}) =>
  `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}"${borda ? ` stroke="${borda}" stroke-width="${lb}"` : ""}${opb ? ` stroke-opacity="${opb}"` : ""}${op ? ` opacity="${op}"` : ""}/>`;
const rot = (x, y, s) => txt(x, y, s, { t: 12, p: 600, cor: c.onSurfaceVariant });
const titulo = (y, s) => txt(24, y, s, { t: 18, p: 600, f: MARCA });
const I = {
  casa: "M4 10.5 12 4l8 6.5V20h-5v-6H9v6H4Z", lista: "M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01",
  pizza: "M12 4a8 8 0 1 0 8 8h-8ZM15 3.6A8 8 0 0 1 20.4 9H15Z", balao: "M4 5h16v11H9l-5 4Z", mais: "M12 5v14M5 12h14",
  sino: "M6 10a6 6 0 0 1 12 0c0 4 1.5 6 2 7H4c.5-1 2-3 2-7ZM9.5 20a2.5 2.5 0 0 0 5 0", lupa: "M11 4a7 7 0 1 0 0 14a7 7 0 0 0 0-14ZM16 16l4.5 4.5",
  garfo: "M7 3v8M5 3v5a2 2 0 0 0 4 0V3M7 11v10M17 3c-2 2-2.5 5-2 8h2v10", seta: "M12 4v14M6 12l6 6 6-6", sacola: "M5 8h14l-1 12H6ZM9 8V6a3 3 0 0 1 6 0v2", alerta: "M12 4 3 20h18ZM12 10v5M12 17.5h.01", x: "M6 6l12 12M18 6 6 18",
  olho: "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12ZM12 9a3 3 0 1 0 0 6a3 3 0 0 0 0-6Z", check: "M5 12.5 10 17l9-10",
};
const icone = (n, x, y, cor, t = 24, l = 1.8) =>
  `<path d="${I[n]}" transform="translate(${x} ${y}) scale(${t / 24})" fill="none" stroke="${cor}" stroke-width="${l}" stroke-linecap="round" stroke-linejoin="round"/>`;
const pintas = (x, y, n, cor, vazia = c.outline) => [0, 1, 2].map((k) =>
  `<circle cx="${x + k * 12}" cy="${y}" r="4" fill="${k < n ? cor : "none"}" stroke="${k < n ? cor : vazia}" stroke-width="1.5"/>`).join("");

// ---------- 1. Botões ----------
function botoes() {
  const estados = ["Normal", "Foco", "Pressionado", "Desabilitado", "Carregando"], X0 = 150, DX = 160, BW = 136, BH = 48;
  const tipos = [
    ["Principal", c.primary, c.onPrimary, null, "Conectar banco"],
    ["Tonal", c.secondaryContainer, c.onSecondaryContainer, null, "Ver extrato"],
    ["Contorno", "none", c.primary, c.outline, "Agora não"],
    ["Texto", "none", c.primary, null, "Pular por agora"],
  ];
  let s = titulo(36, "Botões") + estados.map((e, i) => rot(X0 + i * DX, 66, e)).join(""), y = 82;
  for (const [nome, fundo, texto, borda, label] of tipos) {
    s += rot(24, y + 29, nome);
    estados.forEach((e, i) => {
      const x = X0 + i * DX, off = e === "Desabilitado";
      const f = off ? (fundo === "none" ? "none" : c.onSurface) : fundo, tx = off ? c.onSurface : texto;
      s += rr(x, y, BW, BH, 24, f, { borda: borda ? (off ? c.onSurface : borda) : null, op: off && fundo !== "none" ? 0.12 : null, opb: off ? 0.12 : null });
      if (e === "Pressionado") s += rr(x, y, BW, BH, 24, texto, { op: 0.1 });
      if (e === "Foco") s += rr(x - 4, y - 4, BW + 8, BH + 8, 28, "none", { borda: c.primary, lb: 2 });
      s += e === "Carregando" ? pintas(x + BW / 2 - 12, y + BH / 2, 2, tx, tx)
        : `<g${off ? ' opacity="0.38"' : ""}>${txt(x + BW / 2, y + 29, label, { p: 600, cor: tx, a: "middle" })}</g>`;
    });
    y += 68;
  }
  s += rot(24, y + 34, "Ação (+)");
  [["Normal", 0], ["Foco", 1], ["Pressionado", 2]].forEach(([e, i]) => {
    const x = X0 + i * DX + 40;
    s += `<circle cx="${x + 28}" cy="${y + 28}" r="28" fill="${c.primary}"/>` + (e === "Pressionado" ? `<circle cx="${x + 28}" cy="${y + 28}" r="28" fill="${c.onPrimary}" opacity="0.1"/>` : "") +
      (e === "Foco" ? `<circle cx="${x + 28}" cy="${y + 28}" r="32" fill="none" stroke="${c.primary}" stroke-width="2"/>` : "") + icone("mais", x + 16, y + 16, c.onPrimary, 24, 2.2);
  });
  return { h: y + 80, s };
}

// ---------- 2. Campos ----------
function campos() {
  const CW = 280, CH = 56;
  const campo = (x, y, { rotulo, valor, dica, borda = c.outline, lb = 1, corRot = c.onSurfaceVariant, off, erro, prefixo, lupa }) => {
    let s = `<g${off ? ' opacity="0.38"' : ""}>` + txt(x, y - 8, rotulo, { t: 12, p: 600, cor: corRot }) +
      rr(x, y, CW, CH, 12, c.surfaceContainerLowest, { borda, lb });
    if (lupa) s += icone("lupa", x + 14, y + 16, c.onSurfaceVariant);
    const tx = x + (lupa ? 48 : 16);
    if (prefixo) s += txt(tx, y + 35, prefixo, { t: 16, cor: c.onSurfaceVariant });
    s += valor ? txt(tx + (prefixo ? 30 : 0), y + 35, valor, { t: 16 }) : txt(tx, y + 35, dica ?? "", { t: 16, cor: c.onSurfaceVariant });
    if (erro) s += txt(x, y + CH + 18, erro, { t: 12, cor: c.error });
    return s + "</g>";
  };
  let s = titulo(36, "Campos");
  s += campo(24, 84, { rotulo: "Vazio", dica: "Nome do estabelecimento" });
  s += campo(336, 84, { rotulo: "Preenchido", valor: "Mercado da Vila" });
  s += campo(648, 84, { rotulo: "Foco", valor: "Mercado da V", borda: c.primary, lb: 2, corRot: c.primary }) + rr(648 + 16 + 98, 84 + 18, 2, 22, 1, c.primary);
  s += campo(24, 196, { rotulo: "Erro", valor: "0,00", prefixo: "R$", borda: c.error, lb: 2, corRot: c.error, erro: "Informe um valor maior que zero." });
  s += campo(336, 196, { rotulo: "Desabilitado", valor: "Banco Ipê", off: true });
  s += campo(648, 196, { rotulo: "Busca", dica: "Buscar no extrato", lupa: true });
  s += campo(24, 316, { rotulo: "Valor", valor: "187,43", prefixo: "R$" });
  s += txt(336, 340, "O campo de valor abre o teclado numérico e formata", { t: 13, cor: c.onSurfaceVariant }) + txt(336, 360, "os centavos enquanto a pessoa digita.", { t: 13, cor: c.onSurfaceVariant });
  return { h: 400, s };
}

// ---------- 3. Chips e seleção ----------
function selecao() {
  const chip = (x, y, label, { sel, off, cor } = {}) => {
    const w = label.length * 7.6 + (cor ? 50 : 26);
    return [`<g${off ? ' opacity="0.38"' : ""}>` + rr(x, y, w, 32, 12, sel ? c.secondaryContainer : "none", { borda: sel ? null : c.outline }) +
      (cor ? `<circle cx="${x + 18}" cy="${y + 16}" r="7" fill="${cor}"/>` : "") +
      txt(x + (cor ? 32 : 13), y + 21, label, { p: 600, cor: sel ? c.onSecondaryContainer : c.onSurfaceVariant }) + "</g>", w];
  };
  let s = titulo(36, "Chips e seleção"), x = 150;
  s += rot(24, 85, "Filtro");
  for (const [l, o] of [["Tudo", { sel: true }], ["Entradas", {}], ["Saídas", {}], ["Pix", { off: true }]]) { const [g, w] = chip(x, 64, l, o); s += g; x += w + 8; }
  s += rot(24, 135, "Categoria"); x = 150;
  for (const [l, k] of [["Alimentação", "alimentacao"], ["Transporte", "transporte"], ["Lazer", "lazer"]]) { const [g, w] = chip(x, 114, l, { cor: c.g[k], sel: l === "Alimentação" }); s += g; x += w + 8; }
  s += rot(24, 189, "Período");
  s += rr(150, 164, 300, 40, 20, "none", { borda: c.outline }) + rr(150, 164, 100, 40, 20, c.secondaryContainer) +
    ["Este mês", "3 meses", "12 meses"].map((l, i) => txt(200 + i * 100, 189, l, { p: 600, a: "middle", cor: i ? c.onSurface : c.onSecondaryContainer })).join("");
  s += rot(24, 245, "Chave");
  s += rr(150, 226, 52, 32, 16, c.primary) + `<circle cx="186" cy="242" r="12" fill="${c.onPrimary}"/>` + txt(212, 247, "Ligada", { t: 13 }) +
    rr(300, 226, 52, 32, 16, c.surfaceContainerHighest, { borda: c.outline, lb: 2 }) + `<circle cx="316" cy="242" r="8" fill="${c.outline}"/>` + txt(362, 247, "Desligada", { t: 13 });
  s += rot(24, 299, "Marcar");
  s += rr(150, 284, 22, 22, 4, c.primary) + icone("check", 151, 285, c.onPrimary, 20, 2.4) + txt(182, 300, "Lembrar a escolha", { t: 13 }) +
    rr(340, 284, 22, 22, 4, "none", { borda: c.onSurfaceVariant, lb: 2 }) + txt(372, 300, "Desmarcada", { t: 13 }) +
    `<circle cx="511" cy="295" r="10" fill="none" stroke="${c.primary}" stroke-width="2"/><circle cx="511" cy="295" r="5" fill="${c.primary}"/>` + txt(530, 300, "Opção escolhida", { t: 13 }) +
    `<circle cx="681" cy="295" r="10" fill="none" stroke="${c.onSurfaceVariant}" stroke-width="2"/>` + txt(700, 300, "Outra opção", { t: 13 });
  s += rot(24, 353, "Essencialidade");
  [["Essencial", 3, c.essencial], ["Importante", 2, c.importante], ["Flexível", 1, c.flexivel]].forEach(([n, q, cor], i) => {
    s += pintas(154 + i * 190, 348, q, cor) + txt(196 + i * 190, 353, n, { t: 13 });
  });
  return { h: 384, s };
}

// ---------- 4. Cartões e listas ----------
function cartoes() {
  const cartao = (x, y, w, h) => rr(x, y, w, h, 20, c.surfaceContainerLow, { borda: c.outlineVariant });
  const valor = (x, y, int, cent, t = 40) => txt(x, y, `R$ ${int}<tspan font-size="${t * 0.55}">,${cent}</tspan>`, { t, p: 600 });
  let s = titulo(36, "Cartões e listas");
  s += rot(24, 66, "Valor em destaque") + cartao(24, 76, 300, 132) + txt(40, 104, "Sobrou este mês", { p: 600, cor: c.onSurfaceVariant }) + valor(40, 152, "1.284", "90") +
    txt(40, 186, "Entrou R$ 6.200,00 · Saiu R$ 4.915,10", { t: 12, cor: c.onSurfaceVariant });
  s += rot(344, 66, "Valores ocultos") + cartao(344, 76, 300, 132) + txt(360, 104, "Sobrou este mês", { p: 600, cor: c.onSurfaceVariant }) +
    txt(360, 152, "R$", { t: 40, p: 600 }) + [0, 1, 2].map((k) => `<circle cx="${436 + k * 22}" cy="139" r="7" fill="${c.onSurface}"/>`).join("") + icone("olho", 604, 92, c.onSurfaceVariant);
  s += rot(664, 66, "Fala da Paçoca") + `<path d="M734 96h178a20 20 0 0 1 20 20v52a20 20 0 0 1-20 20H720a6 6 0 0 1-6-6v-66a20 20 0 0 1 20-20Z" fill="${c.primaryContainer}"/>` +
    `<circle cx="686" cy="168" r="20" fill="${c.inversePrimary}"/>` +
    txt(730, 128, "Mercado ficou 12% abaixo", { t: 15, p: 500, f: MARCA, cor: c.onPrimaryContainer }) + txt(730, 150, "do mês passado.", { t: 15, p: 500, f: MARCA, cor: c.onPrimaryContainer }) +
    txt(730, 172, "Bom ritmo!", { t: 15, p: 500, f: MARCA, cor: c.onPrimaryContainer });
  const linha = (y, nome, info, v, { cat = "alimentacao", banco = c.tertiary, entrada, marca, ic = "garfo" } = {}) => {
    const cor = entrada ? c.mata : c.g[cat];
    return rr(40, y + 8, 4, 40, 2, banco) + `<circle cx="76" cy="${y + 28}" r="20" fill="${cor}" opacity="0.16"/>` + icone(ic, 65, y + 17, cor, 22) +
      txt(108, y + 24, nome, { t: 16, p: 600 }) + txt(108, y + 44, info, { t: 12, cor: c.onSurfaceVariant }) +
      (marca ? rr(430, y + 14, 74, 22, 11, c.tertiaryContainer) + txt(467, y + 29, "Revisar", { t: 11, p: 600, cor: c.onTertiaryContainer, a: "middle" }) : "") +
      txt(608, y + 33, v, { t: 16, p: 600, a: "end", cor: entrada ? c.mata : c.onSurface });
  };
  s += rot(24, 240, "Lançamentos") + cartao(24, 250, 600, 188) + linha(256, "Mercado da Vila", "Alimentação · Débito · Banco Ipê", "R$ 187,43") +
    `<path d="M40 316H608" stroke="${c.outlineVariant}"/>` + linha(316, "Loja 0387", "Compras · Crédito · Banco Jatobá", "R$ 64,90", { cat: "compras", banco: c.rio, marca: true, ic: "sacola" }) +
    `<path d="M40 376H608" stroke="${c.outlineVariant}"/>` + linha(376, "Salário", "Entrada · Pix · Banco Ipê", "+R$ 6.200,00", { entrada: true, ic: "seta" });
  s += rot(664, 240, "Conta conectada") + cartao(664, 250, 272, 188) + rr(680, 266, 4, 40, 2, c.tertiary) + txt(696, 284, "Banco Ipê", { t: 16, p: 600 }) +
    txt(696, 304, "Conta corrente", { t: 12, cor: c.onSurfaceVariant }) + valor(680, 356, "3.412", "08", 24) +
    `<circle cx="686" cy="402" r="5" fill="${c.mata}"/>` + txt(698, 406, "Sincronizado hoje às 18:40", { t: 12, cor: c.onSurfaceVariant });
  return { h: 462, s };
}

// ---------- 5. Navegação ----------
function navegacao() {
  let s = titulo(36, "Navegação") + rot(24, 66, "Barra de baixo (celular)");
  s += rr(24, 76, 380, 76, 0, c.surfaceContainer, { borda: c.outlineVariant });
  [["casa", "Início", true], ["lista", "Extrato"], null, ["pizza", "Gastos"], ["balao", "Paçoca"]].forEach((it, i) => {
    const x = 24 + 38 + i * 76;
    if (!it) { s += `<circle cx="${x}" cy="112" r="26" fill="${c.primary}"/>` + icone("mais", x - 12, 100, c.onPrimary, 24, 2.2); return; }
    const [ic, l, sel] = it;
    s += (sel ? rr(x - 28, 88, 56, 30, 15, c.secondaryContainer) : "") + icone(ic, x - 12, 91, sel ? c.onSecondaryContainer : c.onSurfaceVariant) +
      txt(x, 138, l, { t: 12, p: 600, a: "middle", cor: sel ? c.onSurface : c.onSurfaceVariant });
  });
  s += rot(444, 66, "Topo do Início") + rr(444, 76, 380, 64, 0, c.surface, { borda: c.outlineVariant }) + txt(460, 118, "Boa noite, Bia", { t: 24, p: 600, f: MARCA }) +
    icone("sino", 776, 96, c.onSurface) + `<circle cx="796" cy="98" r="9" fill="${c.error}"/>` + txt(796, 102, "2", { t: 11, p: 600, cor: c.onError, a: "middle" });
  s += rot(24, 192, "Trilho") + rr(24, 202, 88, 330, 0, c.surfaceContainer, { borda: c.outlineVariant }) +
    rr(40, 218, 56, 56, 16, c.primary) + icone("mais", 56, 234, c.onPrimary, 24, 2.2);
  [["casa", "Início"], ["lista", "Extrato", true], ["pizza", "Gastos"], ["balao", "Paçoca"]].forEach(([ic, l, sel], i) => {
    const y = 296 + i * 58;
    s += (sel ? rr(40, y, 56, 30, 15, c.secondaryContainer) : "") + icone(ic, 56, y + 3, sel ? c.onSecondaryContainer : c.onSurfaceVariant) +
      txt(68, y + 46, l, { t: 12, p: 600, a: "middle", cor: sel ? c.onSurface : c.onSurfaceVariant });
  });
  s += rot(160, 192, "Folha de ações do + (o trilho é para tablet e desktop)") + rr(160, 202, 380, 330, 28, c.surfaceContainerLow, { borda: c.outlineVariant }) + rr(334, 214, 32, 4, 2, c.outline) +
    txt(184, 256, "O que você quer registrar?", { t: 20, p: 600 });
  [["Gasto em dinheiro", "Para o que não passa pelo banco"], ["Ler nota fiscal", "Pela câmera ou por uma foto"], ["Conectar banco", "Pelo Open Finance"]].forEach(([a, b], i) => {
    const y = 280 + i * 76;
    s += `<circle cx="208" cy="${y + 28}" r="20" fill="${c.primaryContainer}"/>` + icone(["mais", "lupa", "lista"][i], 197, y + 17, c.onPrimaryContainer, 22) +
      txt(244, y + 25, a, { t: 16, p: 600 }) + txt(244, y + 45, b, { t: 13, cor: c.onSurfaceVariant });
  });
  return { h: 556, s };
}

// ---------- 6. Avisos e estados ----------
function avisos() {
  let s = titulo(36, "Avisos e estados") + rot(24, 66, "Aviso rápido (some sozinho)");
  s += rr(24, 76, 400, 48, 12, c.inverseSurface) + txt(40, 105, "Categoria alterada para Lazer.", { cor: c.onInverseSurface }) + txt(408, 105, "Desfazer", { p: 600, cor: c.inversePrimary, a: "end" });
  s += rot(464, 66, "Faixa de alerta") + rr(464, 76, 472, 88, 20, c.errorContainer) + icone("alerta", 480, 92, c.onErrorContainer) +
    txt(516, 104, "A conexão com o Banco Jatobá vence em 5 dias", { p: 600, cor: c.onErrorContainer }) +
    txt(516, 126, "Renove para o extrato continuar chegando.", { t: 13, cor: c.onErrorContainer }) + txt(516, 150, "Renovar agora", { p: 600, cor: c.onErrorContainer });
  s += rot(24, 196, "Diálogo") + rr(24, 206, 400, 196, 28, c.surfaceContainerHigh, { borda: c.outlineVariant }) + txt(48, 246, "Desconectar o Banco Ipê?", { t: 20, p: 600 }) +
    txt(48, 276, "Os lançamentos já baixados continuam no app.", { cor: c.onSurfaceVariant }) + txt(48, 296, "Novos lançamentos deixam de chegar.", { cor: c.onSurfaceVariant }) +
    txt(272, 366, "Cancelar", { p: 600, cor: c.primary, a: "end" }) + rr(288, 340, 112, 40, 20, c.error) + txt(344, 365, "Desconectar", { p: 600, cor: c.onError, a: "middle" });
  s += rot(464, 196, "Estado vazio") + rr(464, 206, 472, 196, 20, c.surfaceContainerLow, { borda: c.outlineVariant }) + `<circle cx="524" cy="304" r="36" fill="${c.inversePrimary}" opacity="0.5"/>` +
    txt(580, 286, "Nada por aqui ainda", { t: 20, p: 600, f: MARCA }) + txt(580, 310, "Conecte um banco para ver seus", { cor: c.onSurfaceVariant }) +
    txt(580, 330, "lançamentos neste extrato.", { cor: c.onSurfaceVariant }) + rr(580, 346, 136, 40, 20, c.primary) + txt(648, 371, "Conectar banco", { p: 600, cor: c.onPrimary, a: "middle" });
  s += rot(24, 438, "Carregando (esqueleto)") + rr(24, 448, 400, 132, 20, c.surfaceContainerLow, { borda: c.outlineVariant });
  [0, 1].forEach((k) => { const y = 464 + k * 56;
    s += `<circle cx="60" cy="${y + 20}" r="20" fill="${c.surfaceContainerHighest}"/>` + rr(92, y + 4, 150, 14, 7, c.surfaceContainerHighest) + rr(92, y + 26, 100, 10, 5, c.surfaceContainerHighest) + rr(336, y + 10, 72, 16, 8, c.surfaceContainerHighest); });
  s += rot(464, 438, "Passos e carregamento com pintas") + pintas(468, 470, 2, c.primary) + txt(512, 475, "Passo 2 de 3", { t: 13 }) +
    pintas(468, 512, 1, c.primary, c.primary) + txt(512, 517, "Buscando seus lançamentos…", { t: 13 }) +
    rr(464, 544, 300, 8, 4, c.surfaceContainerHighest) + rr(464, 544, 186, 8, 4, c.primary) + txt(776, 553, "62% da meta", { t: 13 });
  return { h: 604, s };
}

const FOLHAS = { botoes, campos, selecao, cartoes, navegacao, avisos };
for (const tema of ["claro", "escuro"]) {
  c = { ...T.cor.esquema[tema], ...T.cor.marca[tema], g: Object.fromEntries(T.cor.categorias.map((k) => [k.id, T.cor.grafico[tema][k.cor]])) };
  for (const [nome, fn] of Object.entries(FOLHAS)) {
    const { h, s } = fn();
    if (/undefined|NaN/.test(s)) throw new Error(`${nome}-${tema}: undefined ou NaN`);
    writeFileSync(new URL(`./${nome}-${tema}.svg`, import.meta.url),
      `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${h}" role="img" aria-labelledby="t"><title id="t">Componentes: ${nome}, tema ${tema}</title>` +
      `<rect width="${W}" height="${h}" fill="${c.surface}"/>${s}</svg>\n`);
  }
}
console.log("12 folhas gravadas em docs/design/componentes");
