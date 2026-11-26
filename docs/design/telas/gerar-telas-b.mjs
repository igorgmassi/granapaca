// Telas B (Identidade Toca Editorial): Extrato, Detalhe do lançamento com correção e histórico, e Gastos (claro, escuro e desktop).
// Uso: node docs/design/telas/gerar-telas-b.mjs
import { T, c, usar, txt, linhas, marca, rr, icone, pintas, botao, cartao, lancamento, nav, celular, grava, CEL, ICONE_CATEGORIA, brl } from "./kit.mjs";

// ---------- Dados fictícios (os mesmos do Início da Parte 6) ----------
const BANCO = () => ({ ipe: c.tertiary, jatoba: c.rio, dinheiro: c.milho });
const nivelCor = () => [null, c.flexivel, c.importante, c.essencial];
const NIVEL_NOME = [null, "Flexível", "Importante", "Essencial"];
const CATEGORIA_NOME = Object.fromEntries(T.cor.categorias.map((k) => [k.id, k.nome]));
const CATEGORIA_CURTA = { ...CATEGORIA_NOME, assinaturas: "Assinaturas" };
const L = {
  mercado: { nome: "Mercado da Vila", cat: "alimentacao", banco: "ipe", bancoNome: "Banco Ipê", forma: "Débito", v: 187.43, nivel: 3 },
  posto: { nome: "Posto Estrela", cat: "transporte", banco: "jatoba", bancoNome: "Banco Jatobá", forma: "Crédito", v: 210, nivel: 2 },
  cafe: { nome: "Café do Largo", cat: "alimentacao", banco: "ipe", bancoNome: "Banco Ipê", forma: "Pix", v: 18.5, nivel: 1 },
  loja: { nome: "Loja 0387", cat: "compras", banco: "jatoba", bancoNome: "Banco Jatobá", forma: "Crédito", v: 64.9, nivel: 1, revisar: true },
  streaming: { nome: "Streaming Mais", cat: "assinaturas", banco: "jatoba", bancoNome: "Banco Jatobá", forma: "Crédito", v: 39.9, nivel: 1 },
  farmacia: { nome: "Farmácia Pétala", cat: "saude", banco: "ipe", bancoNome: "Banco Ipê", forma: "Débito", v: 82.3, nivel: 3 },
  mercado19: { nome: "Mercado da Vila", cat: "alimentacao", banco: "ipe", bancoNome: "Banco Ipê", forma: "Débito", v: 98.6, nivel: 3 },
  mercado12: { nome: "Mercado Bela Safra", cat: "alimentacao", banco: "jatoba", bancoNome: "Banco Jatobá", forma: "Crédito", v: 126.15, nivel: 3 },
  salario: { nome: "Salário", cat: "outros", banco: "ipe", bancoNome: "Banco Ipê", forma: "Pix", v: 6200, entrada: true },
  aluguel: { nome: "Aluguel", cat: "moradia", banco: "ipe", bancoNome: "Banco Ipê", forma: "Pix", v: 1800, nivel: 3 },
};
const GASTOS = [["moradia", 1800], ["alimentacao", 960], ["transporte", 520], ["compras", 420], ["saude", 310], ["outros", 905.1]];
const ORDEM_ROSCA = T.cor.grafico.ordemDaRosca.filter((id) => GASTOS.some(([g]) => g === id));
const TOTAL = GASTOS.reduce((a, [, v]) => a + v, 0);
const ENTROU = 6200, SOBROU = ENTROU - TOTAL;
const SEP = T.tamanho.separacaoGrafico;

// Percentuais inteiros que fecham em 100 (maior resto).
function percentuais(valores) {
  const soma = valores.reduce((a, v) => a + v, 0), bruto = valores.map((v) => (v / soma) * 100), base = bruto.map(Math.floor);
  let falta = 100 - base.reduce((a, v) => a + v, 0);
  bruto.map((b, i) => [b - base[i], i]).sort((a, b) => b[0] - a[0]).forEach(([, i]) => { if (falta-- > 0) base[i]++; });
  return base;
}
const PCT = Object.fromEntries(percentuais(GASTOS.map(([, v]) => v)).map((p, i) => [GASTOS[i][0], p]));
const sinal = (d) => `${d.entrada ? "+" : "-"}R$ ${brl(d.v)}`;
const valorSinal = (x, y, sg, int, cent, t = 38, o = {}) =>
  txt(x, y, `${sg}R$ ${int}<tspan font-size="${Math.round(t * 0.58)}">,${cent}</tspan>`, { t, p: 700, ...o });
const oculto = (entrada) => `${entrada ? "+" : ""}R$ •••`;

// ---------- Peças locais ----------
// Chip de filtro (Parte 5): selecionado vira secondaryContainer com o ✓; fora disso, borda de campo.
function chip(x, y, rotulo, { sel, ponto, n } = {}) {
  const extra = (sel ? 20 : 0) + (ponto ? 16 : 0) + (n ? 40 : 0);
  const w = Math.round(rotulo.length * 7.3 + extra + 26);
  let s = rr(x, y, w, 34, T.raio.chip, sel ? c.secondaryContainer : "none", { borda: sel ? undefined : c.outline });
  let cx = x + 12;
  if (sel) { s += icone("check", cx - 2, y + 8, c.onSecondaryContainer, 18, 2.2); cx += 20; }
  if (ponto) { s += `<circle cx="${cx + 4}" cy="${y + 17}" r="5" fill="${ponto}"/>`; cx += 16; }
  if (n) { s += pintas(cx + 4, y + 17, n, nivelCor()[n]); cx += 40; }
  return [s + txt(cx, y + 22, rotulo, { t: 13, p: 600, cor: sel ? c.onSecondaryContainer : c.onSurface }), w];
}
function chipsLinha(x, y, lista) {
  let cx = x, s = "";
  for (const [r, o] of lista) { const [g, w] = chip(cx, y, r, o); s += g; cx += w + 8; }
  return s;
}
function chipsQuebra(x, y, lista, maxX) {
  let cx = x, cy = y, s = "";
  for (const [r, o] of lista) {
    const w = Math.round(r.length * 7.3 + ((o?.sel ? 20 : 0) + (o?.ponto ? 16 : 0) + (o?.n ? 40 : 0)) + 26);
    if (cx + w > maxX) { cx = x; cy += 42; }
    s += chip(cx, cy, r, o)[0]; cx += w + 8;
  }
  return [s, cy + 34];
}
const busca = (x, y, w, texto, { foco } = {}) =>
  rr(x, y, w, 48, 24, c.surfaceContainerHigh, { borda: foco ? c.primary : c.outlineVariant, lb: foco ? 2 : 1 }) +
  icone("lupa", x + 16, y + 12, c.onSurfaceVariant, 24) +
  txt(x + 52, y + 30, texto ?? "Buscar lançamentos", { t: 15, cor: texto ? c.onSurface : c.onSurfaceVariant }) +
  (texto ? icone("fechar", x + w - 40, y + 12, c.onSurfaceVariant, 24) : "");
const chave = (x, y, ligada) =>
  rr(x, y, 52, 32, 16, ligada ? c.primary : c.surfaceContainerHighest, { borda: ligada ? undefined : c.outline, lb: 2 }) +
  `<circle cx="${ligada ? x + 36 : x + 16}" cy="${y + 16}" r="${ligada ? 12 : 8}" fill="${ligada ? c.onPrimary : c.outline}"/>`;
const topo = (titulo, dir) => icone("voltar", 14, 30, c.onSurface, 28) + marca(180, 52, titulo, { t: 18, a: "middle" }) + (dir ? icone(dir, 318, 30, c.onSurface, 28) : "");
const separador = (x, y, w) => `<path d="M${x} ${y}H${x + w}" stroke="${c.outlineVariant}"/>`;
const scrim = () => rr(0, 0, CEL.w, CEL.h, 0, c.scrim, { op: 0.45 });
const origemTxt = (s) => s.replace(/&/g, "e");

// Linha do extrato: faixa do banco, círculo da categoria, nome, "Revisar", categoria e banco, valor e pintas.
function linha(x, y, w, d, { oculta, sel, marcar } = {}) {
  const cor = d.entrada ? c.mata : c.g[d.cat];
  const ic = d.entrada ? "seta" : ICONE_CATEGORIA[d.cat];
  const nomePlano = d.nome.replace(/<[^>]+>/g, "");
  const nome = marcar ? d.nome.replace(new RegExp(marcar, "i"), (m) => `<tspan font-weight="700" fill="${c.primary}" text-decoration="underline">${m}</tspan>`) : d.nome;
  let s = (sel ? rr(x - 8, y + 3, w + 16, 56, 12, c.secondaryContainer) : "") +
    rr(x, y + 10, 4, 38, 2, BANCO()[d.banco]) + `<circle cx="${x + 34}" cy="${y + 29}" r="18" fill="${cor}" opacity="0.14"/>` + icone(ic, x + 24, y + 19, cor, 20) +
    txt(x + 62, y + 25, nome, { t: 15, p: 600 });
  if (d.revisar) {
    const cx = x + 62 + Math.round(nomePlano.length * 8.8) + 10;
    s += rr(cx, y + 11, 56, 18, 9, c.milho) + txt(cx + 28, y + 24, "Revisar", { t: 11, p: 700, a: "middle", cor: c.sobreMilho });
  }
  s += txt(x + 62, y + 44, `${CATEGORIA_CURTA[d.cat]} · ${d.bancoNome}`, { t: 12, cor: c.onSurfaceVariant });
  s += txt(x + w, y + 26, oculta ? oculto(d.entrada) : sinal(d), { t: 15, p: 600, a: "end", cor: d.entrada ? c.mata : c.onSurface });
  if (d.nivel) s += pintas(x + w - 24, y + 43, d.nivel, nivelCor()[d.nivel]);
  return s;
}
const grupo = (x, y, w, rotulo, itens, o = {}) => {
  let s = txt(x + 2, y + 14, rotulo, { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(x, y + 26, w, itens.length * 62 + 8);
  itens.forEach((d, i) => { s += linha(x + 12, y + 30 + i * 62, w - 24, d, o); if (i < itens.length - 1) s += separador(x + 12, y + 30 + (i + 1) * 62 - 1, w - 24); });
  return s;
};

// ---------- Extrato ----------
function extratoConsolidado() {
  return marca(20, 62, "Extrato", { t: 26 }) + icone("filtro", 314, 38, c.onSurface) +
    busca(16, 80, 328, null) +
    chipsLinha(16, 140, [["Todos os bancos", { sel: true }], ["Novembro", { sel: true }], ["Forma de pagamento"], ["Só a revisar"]]) +
    txt(18, 202, "42 lançamentos · Saiu R$ 4.915,10", { t: 12, cor: c.onSurfaceVariant }) +
    grupo(16, 214, 328, "Hoje · quinta, 26 de nov.", [L.mercado, L.posto, L.cafe]) +
    grupo(16, 440, 328, "Ontem · quarta, 25 de nov.", [L.loja, L.streaming, L.farmacia]) +
    nav(676, "Extrato");
}
function extratoBanco() {
  const b = L.posto;
  return marca(20, 62, "Extrato", { t: 26 }) + icone("filtro", 314, 38, c.onSurface) +
    busca(16, 80, 328, null) +
    chipsLinha(16, 140, [["Todos", {}], ["Banco Ipê", { ponto: BANCO().ipe }], ["Banco Jatobá", { sel: true, ponto: BANCO().jatoba }], ["Dinheiro físico", { ponto: BANCO().dinheiro }]]) +
    cartao(16, 190, 328, 124) + rr(28, 204, 4, 96, 2, BANCO().jatoba) +
    txt(44, 220, "Banco Jatobá", { t: 16, p: 600 }) + txt(44, 238, "Cartão de crédito", { t: 12, cor: c.onSurfaceVariant }) +
    txt(44, 262, "Fatura aberta", { t: 12, cor: c.onSurfaceVariant }) +
    txt(44, 290, `R$ 1.130<tspan font-size="16">,55</tspan>`, { t: 24, p: 600 }) +
    `<circle cx="48" cy="304" r="4" fill="${c.mata}"/>` + txt(60, 308, "Sincronizado hoje, 18:40", { t: 12, cor: c.onSurfaceVariant }) +
    grupo(16, 326, 328, "Hoje · quinta, 26 de nov.", [b]) +
    grupo(16, 424, 328, "Ontem · quarta, 25 de nov.", [L.loja, L.streaming]) +
    nav(676, "Extrato");
}
function extratoBusca() {
  const r = [L.mercado, L.mercado19, L.mercado12];
  return marca(20, 62, "Extrato", { t: 26 }) + icone("filtro", 314, 38, c.primary) +
    busca(16, 80, 328, "mercado", { foco: true }) +
    chipsLinha(16, 140, [["Alimentação", { sel: true, ponto: c.g.alimentacao }], ["Débito e crédito", { sel: true }], ["Novembro", { sel: true }]]) +
    txt(18, 202, "3 resultados · -R$ 412,18", { t: 12, cor: c.onSurfaceVariant }) +
    grupo(16, 214, 328, "Hoje · quinta, 26 de nov.", [r[0]], { marcar: "mercado" }) +
    grupo(16, 312, 328, "Quinta, 19 de nov.", [r[1]], { marcar: "mercado" }) +
    grupo(16, 410, 328, "Quinta, 12 de nov.", [r[2]], { marcar: "mercado" }) +
    txt(180, 560, "Deslize um lançamento para corrigir a categoria", { t: 12, cor: c.onSurfaceVariant, a: "middle" }) +
    txt(180, 578, "ou anexar um comprovante.", { t: 12, cor: c.onSurfaceVariant, a: "middle" }) +
    nav(676, "Extrato");
}

// Folha de filtros (serve ao Extrato e ao Gastos): seções de chips, uma escolha de período e o botão de aplicar.
function folhaFiltros(titulo, secoes, botaoRotulo, fundo) {
  let corpo = "", y = 24;
  const seg = (rotulos, ativo) => rr(16, y, 328, 44, 22, c.surfaceContainer, { borda: c.outlineVariant }) + rotulos.map((l, i) => {
    const w = 320 / rotulos.length, sel = i === ativo;
    return (sel ? rr(20 + i * w, y + 4, w, 36, 18, c.secondaryContainer) : "") + txt(20 + i * w + w / 2, y + 28, l, { t: 13, p: 600, a: "middle", cor: sel ? c.onSecondaryContainer : c.onSurfaceVariant });
  }).join("");
  for (const sec of secoes) {
    corpo += txt(16, y + 14, sec.titulo, { t: 13, p: 600, cor: c.onSurfaceVariant });
    y += 28;
    if (sec.seg) { corpo += seg(sec.seg, sec.ativo); y += 44 + 20; }
    else if (sec.chave) { corpo += txt(16, y + 18, sec.chave, { t: 15, p: 600 }) + chave(292, y, sec.ligada); y += 32 + 20; }
    else { const [g, fim] = chipsQuebra(16, y, sec.chips, 344); corpo += g; y = fim + 20; }
  }
  const altura = 44 + y + 12 + 48 + 28, topoFolha = CEL.h - altura;
  return fundo + scrim() +
    `<g transform="translate(0 ${topoFolha})">` + rr(0, 0, 360, altura + 40, 28, c.surfaceContainerLow, { borda: c.outlineVariant }) +
    rr(160, 10, 40, 4, 2, c.outline) + marca(16, 52, titulo, { t: 18 }) + txt(344, 52, "Limpar", { t: 14, p: 600, a: "end", cor: c.primary }) +
    `<g transform="translate(0 44)">${corpo}</g>` +
    botao(16, 44 + y + 12, 328, botaoRotulo) + `</g>`;
}
const SECOES_EXTRATO = () => [
  { titulo: "Período", seg: ["Este mês", "Mês passado", "Datas"], ativo: 0 },
  { titulo: "Banco", chips: [["Banco Ipê", { sel: true, ponto: BANCO().ipe }], ["Banco Jatobá", { sel: true, ponto: BANCO().jatoba }], ["Dinheiro físico", { ponto: BANCO().dinheiro }]] },
  { titulo: "Forma de pagamento", chips: [["Débito", { sel: true }], ["Crédito", { sel: true }], ["Pix"], ["Boleto"], ["Dinheiro"]] },
  { titulo: "Essencialidade", chips: [["Essencial", { n: 3 }], ["Importante", { n: 2 }], ["Flexível", { n: 1 }]] },
  { titulo: "Revisão", chave: "Só lançamentos a revisar", ligada: false },
];
const SECOES_GASTOS = () => [
  { titulo: "Período", seg: ["Mês", "3 meses", "Ano"], ativo: 0 },
  { titulo: "Banco", chips: [["Banco Ipê", { sel: true, ponto: BANCO().ipe }], ["Banco Jatobá", { ponto: BANCO().jatoba }], ["Dinheiro físico", { ponto: BANCO().dinheiro }]] },
  { titulo: "Forma de pagamento", chips: [["Débito", { sel: true }], ["Crédito"], ["Pix"], ["Boleto"], ["Dinheiro"]] },
  { titulo: "Essencialidade", chips: [["Essencial", { n: 3 }], ["Importante", { n: 2 }], ["Flexível", { n: 1 }]] },
];

// ---------- Detalhe do lançamento ----------
// Conteúdo reutilizado no celular (w = 328) e no painel do desktop.
function detalhe(x, y, w, { ajustado = true } = {}) {
  const d = L.mercado, cor = c.g.alimentacao;
  let s = valorSinal(x, y + 38, "-", "187", "43", 38) +
    marca(x, y + 68, d.nome, { t: 20 }) +
    txt(x, y + 90, "Quinta, 26 de nov. de 2026 · 18:12", { t: 13, cor: c.onSurfaceVariant }) +
    `<circle cx="${x + 5}" cy="${y + 109}" r="5" fill="${BANCO().ipe}"/>` + txt(x + 16, y + 114, "Banco Ipê · Débito", { t: 13, cor: c.onSurfaceVariant });

  // Dado do banco: nunca muda (ADR-012).
  const y1 = y + 124;
  s += cartao(x, y1, w, 120) + icone("cadeado", x + 14, y1 + 12, c.mata, 20) + txt(x + 42, y1 + 28, "Dado do banco", { t: 14, p: 600 }) +
    rr(x + w - 154, y1 + 12, 140, 24, 12, c.mata, { op: 0.16 }) + txt(x + w - 84, y1 + 28, "Original preservado", { t: 11, p: 600, a: "middle", cor: c.mata }) +
    txt(x + 16, y1 + 56, "Descrição original", { t: 12, cor: c.onSurfaceVariant }) + txt(x + 16, y1 + 74, "MERCADO DA VILA 0412 SP", { t: 14, p: 600 }) +
    txt(x + w - 16, y1 + 56, "Valor original", { t: 12, cor: c.onSurfaceVariant, a: "end" }) + txt(x + w - 16, y1 + 74, "-R$ 187,43", { t: 14, p: 600, a: "end" }) +
    linhas(x + 16, y1 + 94, ["O banco é a fonte e não muda.", "Seus ajustes ficam por cima, com histórico."], { t: 12, cor: c.onSurfaceVariant }, 16);

  // Classificação editável.
  const y2 = y1 + 130, h2 = 160;
  s += cartao(x, y2, w, h2) + txt(x + 16, y2 + 28, "Sua classificação", { t: 14, p: 600 }) +
    (ajustado ? rr(x + w - 142, y2 + 12, 128, 24, 12, c.primaryContainer) + txt(x + w - 78, y2 + 28, "Ajustado por você", { t: 11, p: 600, a: "middle", cor: c.onPrimaryContainer }) : "");
  [["Categoria", "Alimentação"], ["Essencialidade", "Essencial"], ["Tipo", "Gasto"]].forEach(([rot, val], i) => {
    const yy = y2 + 42 + i * 38;
    s += separador(x + 16, yy, w - 32) + txt(x + 16, yy + 25, rot, { t: 13, cor: c.onSurfaceVariant });
    if (i === 0) s += `<circle cx="${x + w - 172}" cy="${yy + 19}" r="14" fill="${cor}" opacity="0.14"/>` + icone("garfo", x + w - 182, yy + 9, cor, 20);
    if (i === 1) s += pintas(x + w - 168, yy + 19, 3, c.essencial);
    s += txt(x + w - 44, yy + 25, val, { t: 14, p: 600, a: "end" }) + icone("direita", x + w - 36, yy + 8, c.onSurfaceVariant, 24);
  });

  // Comprovantes e divisão.
  const y3 = y2 + h2 + 10;
  s += cartao(x, y3, w, 84) + icone("clipe", x + 14, y3 + 12, c.onSurfaceVariant, 20) + txt(x + 42, y3 + 28, "Comprovantes e divisão", { t: 14, p: 600 });
  [0, 1].forEach((k) => { s += rr(x + 16 + k * 44, y3 + 40, 36, 36, 8, c.surfaceContainerHigh, { borda: c.outlineVariant }) + icone("nota", x + 22 + k * 44, y3 + 46, c.onSurfaceVariant, 24, 1.6); });
  s += rr(x + 108, y3 + 40, 36, 36, 18, "none", { borda: c.outline }) + icone("mais", x + 116, y3 + 48, c.primary, 20, 2) +
    icone("divisao", x + w - 124, y3 + 48, c.primary, 20) + txt(x + w - 98, y3 + 63, "Dividir valor", { t: 13, p: 600, cor: c.primary });

  // Histórico.
  const y4 = y3 + 94;
  s += cartao(x, y4, w, 48) + icone("desfazer", x + 14, y4 + 12, c.onSurfaceVariant, 24) + txt(x + 48, y4 + 29, "Histórico", { t: 14, p: 600 }) +
    txt(x + w - 40, y4 + 29, "2 ajustes", { t: 13, a: "end", cor: c.onSurfaceVariant }) + icone("direita", x + w - 36, y4 + 12, c.onSurfaceVariant, 24);
  return s;
}
const telaDetalhe = () => topo("Lançamento", "pontos") + detalhe(16, 80, 328) + botao(16, 676, 328, "Corrigir lançamento");

// Folha de correção: grade de categorias, escala de essencialidade, justificativa e "vale para as semelhantes".
function folhaCorrecao() {
  const topoFolha = 112, cw = 109;
  let s = telaDetalhe() + scrim() + `<g transform="translate(0 ${topoFolha})">` + rr(0, 0, 360, CEL.h, 28, c.surfaceContainerLow, { borda: c.outlineVariant }) + rr(160, 10, 40, 4, 2, c.outline) +
    marca(16, 52, "Corrigir lançamento", { t: 18 }) + icone("fechar", 316, 30, c.onSurface, 28) +
    txt(16, 84, "Categoria", { t: 13, p: 600, cor: c.onSurfaceVariant });
  T.cor.categorias.forEach((k, i) => {
    const col = i % 3, lin = Math.floor(i / 3), cx = 16 + col * cw + cw / 2 - 8, cy = 120 + lin * 68, sel = k.id === "alimentacao";
    s += (sel ? rr(16 + col * cw, cy - 24, cw - 8, 62, 14, c.secondaryContainer) : "") + `<circle cx="${cx}" cy="${cy}" r="18" fill="${c.g[k.id]}" opacity="0.14"/>` +
      icone(ICONE_CATEGORIA[k.id], cx - 10, cy - 10, c.g[k.id], 20) +
      (sel ? `<circle cx="${cx + 15}" cy="${cy - 14}" r="8" fill="${c.primary}"/>` + icone("check", cx + 9, cy - 20, c.onPrimary, 12, 2.6) : "") +
      txt(cx, cy + 32, CATEGORIA_CURTA[k.id], { t: 11, p: sel ? 700 : 500, a: "middle" });
  });
  const yE = 120 + 3 * 68 - 6;
  s += txt(16, yE, "Essencialidade", { t: 13, p: 600, cor: c.onSurfaceVariant });
  [3, 2, 1].forEach((n, i) => {
    const x0 = 16 + i * 110, sel = n === 3;
    s += rr(x0, yE + 12, 104, 52, 14, sel ? c.secondaryContainer : "none", { borda: sel ? c.primary : c.outline, lb: sel ? 2 : 1 }) +
      pintas(x0 + 52 - 12, yE + 30, n, nivelCor()[n]) + txt(x0 + 52, yE + 53, NIVEL_NOME[n], { t: 12, p: 600, a: "middle", cor: sel ? c.onSecondaryContainer : c.onSurface });
  });
  const yJ = yE + 92;
  s += txt(16, yJ, "Por que mudou? (opcional)", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    rr(16, yJ + 10, 328, 48, 12, c.surfaceContainerLowest, { borda: c.outline }) + txt(32, yJ + 40, "É mercado, não loja", { t: 15 });
  const yV = yJ + 74;
  s += txt(16, yV + 14, "Vale para todas as semelhantes?", { t: 15, p: 600 }) + txt(16, yV + 33, "Mercado da Vila · 6 lançamentos", { t: 12, cor: c.onSurfaceVariant }) + chave(292, yV + 2, true);
  s += botao(16, yV + 54, 328, "Salvar correção") + txt(180, yV + 130, "Cancelar", { t: 14, p: 600, a: "middle", cor: c.primary }) + `</g>`;
  return s;
}

// Histórico em linha do tempo, com Desfazer (que cria um registro novo; nada é apagado).
function telaHistorico() {
  const itens = [
    ["Categoria: Compras → Alimentação", "Você · hoje, 18:31", "Motivo: é mercado, não loja", { desfazer: true, cor: c.primary }],
    ["Essencial em vez de Importante", "Você · hoje, 18:31", "Vale para as 6 semelhantes", { desfazer: true, cor: c.primary }],
    ["Classificado pela regra do app", "Regra do app · hoje, 18:12", "Categoria Compras, confiança baixa", { cor: c.outline }],
    ["Lançamento recebido do banco", "Banco Ipê · hoje, 18:12", "MERCADO DA VILA 0412 SP · -R$ 187,43", { lacre: true, cor: c.mata }],
  ];
  let s = topo("Histórico") + txt(180, 76, "Mercado da Vila · -R$ 187,43", { t: 13, cor: c.onSurfaceVariant, a: "middle" }) +
    `<path d="M34 134V${134 + 3 * 88}" stroke="${c.outlineVariant}" stroke-width="2"/>`;
  itens.forEach(([titulo, quem, extra, o], i) => {
    const y = 120 + i * 88;
    s += `<circle cx="34" cy="${y + 14}" r="7" fill="${o.cor}"/>` + (o.lacre ? icone("cadeado", 28, y + 8, c.surfaceContainerLow, 12, 2.4) : "") +
      txt(56, y + 18, titulo, { t: 14, p: 600 }) + txt(56, y + 38, quem, { t: 12, cor: c.onSurfaceVariant }) + txt(56, y + 56, extra, { t: 12, cor: c.onSurfaceVariant });
    if (o.desfazer) s += txt(344, y + 38, "Desfazer", { t: 13, p: 600, a: "end", cor: c.primary });
    if (o.lacre) s += rr(56, y + 64, 160, 20, 10, c.mata, { op: 0.16 }) + txt(136, y + 78, "Dado original, não muda", { t: 11, p: 600, a: "middle", cor: c.mata });
  });
  s += cartao(16, 484, 328, 84) + icone("info", 30, 498, c.rio, 22) +
    linhas(62, 512, ["Desfazer cria um novo registro.", "Nada é apagado: o original e todo o", "histórico continuam aqui."], { t: 12, cor: c.onSurfaceVariant }, 17);
  s += rr(16, 648, 328, 48, 12, c.inverseSurface) + txt(32, 677, "Correção salva", { t: 14, cor: c.onInverseSurface }) + txt(328, 677, "Desfazer", { t: 14, p: 600, a: "end", cor: c.inversePrimary });
  return s;
}

// ---------- Gastos ----------
function rosca(cx, cy, R, sw, centro, sub) {
  const C = 2 * Math.PI * R;
  let ini = 0, s = "";
  for (const id of ORDEM_ROSCA) {
    const v = GASTOS.find(([g]) => g === id)[1], L2 = (v / TOTAL) * C;
    s += `<circle cx="${cx}" cy="${cy}" r="${R}" fill="none" stroke="${c.g[id]}" stroke-width="${sw}" stroke-dasharray="${(L2 - SEP).toFixed(1)} ${C.toFixed(1)}" stroke-dashoffset="${(-ini).toFixed(1)}" transform="rotate(-90 ${cx} ${cy})"/>`;
    ini += L2;
  }
  return s + txt(cx, cy - 2, centro, { t: R > 60 ? 16 : 12, p: 700, a: "middle" }) + txt(cx, cy + (R > 60 ? 16 : 14), sub, { t: 11, a: "middle", cor: c.onSurfaceVariant });
}
const rankingOrdenado = () => [...GASTOS.filter(([g]) => g !== "outros").sort((a, b) => b[1] - a[1]), GASTOS.find(([g]) => g === "outros")];
function cartaoRosca(x, y, w, { oculta, grande } = {}) {
  const R = grande ? 70 : 54, sw = grande ? 28 : 20, h = grande ? 250 : 190, cx = x + (grande ? 110 : 84), cy = y + (grande ? 138 : 104);
  let s = cartao(x, y, w, h) + txt(x + 16, y + 28, "Para onde foi", { t: 16, p: 600 }) + txt(x + w - 16, y + 28, "novembro", { t: 12, a: "end", cor: c.onSurfaceVariant }) +
    rosca(cx, cy, R, sw, oculta ? "R$ •••" : `R$ ${brl(TOTAL)}`, "saiu no mês");
  ORDEM_ROSCA.forEach((id, i) => {
    const ly = y + (grande ? 76 : 66) + i * (grande ? 26 : 22), lx = x + (grande ? 230 : 168);
    s += `<circle cx="${lx}" cy="${ly - 4}" r="6" fill="${c.g[id]}"/>` + txt(lx + 14, ly, CATEGORIA_NOME[id], { t: 13 }) + txt(x + w - 16, ly, `${PCT[id]}%`, { t: 13, p: 600, a: "end" });
  });
  return s;
}
function cartaoRanking(x, y, w, { oculta, linhaH = 38 } = {}) {
  const itens = rankingOrdenado(), max = itens[0][1], barraW = w - 40 - 64;
  let s = cartao(x, y, w, itens.length * linhaH + 16);
  itens.forEach(([id, v], i) => {
    const yy = y + 8 + i * linhaH;
    s += `<circle cx="${x + 28}" cy="${yy + 19}" r="14" fill="${c.g[id]}" opacity="0.14"/>` + icone(ICONE_CATEGORIA[id], x + 20, yy + 11, c.g[id], 16, 2) +
      txt(x + 52, yy + 15, CATEGORIA_NOME[id], { t: 13, p: 600 }) + txt(x + w - 16, yy + 15, oculta ? "R$ •••" : `R$ ${brl(v)}`, { t: 13, p: 600, a: "end" }) +
      rr(x + 52, yy + 23, barraW, 6, 3, c.surfaceContainerHighest) + rr(x + 52, yy + 23, Math.max(8, (barraW * v) / max), 6, 3, c.g[id]) +
      txt(x + w - 16, yy + 30, `${PCT[id]}%`, { t: 11, a: "end", cor: c.onSurfaceVariant });
  });
  return s;
}
const abasGastos = (y, ativo = 0) => rr(16, y, 328, 44, 22, c.surfaceContainer, { borda: c.outlineVariant }) + ["Análise", "Planejamento"].map((l, i) =>
  (i === ativo ? rr(20 + i * 160, y + 4, 160, 36, 18, c.secondaryContainer) : "") + txt(100 + i * 160, y + 28, l, { t: 14, p: 600, a: "middle", cor: i === ativo ? c.onSecondaryContainer : c.onSurfaceVariant })).join("");
const seletorMes = (y, cx = 180) => icone("voltar", cx - 160, y, c.onSurface, 28) + marca(cx, y + 22, "Novembro de 2026", { t: 16, a: "middle" }) + icone("direita", cx + 130, y, c.outlineVariant, 28);
function gastosAnalise({ oculta } = {}) {
  return marca(20, 62, "Gastos", { t: 26 }) + icone("olho", 314, 38, oculta ? c.primary : c.onSurface) + abasGastos(76) + seletorMes(132) +
    chipsLinha(16, 174, [["Todos os bancos", { sel: true }], ["Todas as formas", { sel: true }], ["Essencialidade"]]) +
    cartaoRosca(16, 218, 328, { oculta }) + cartaoRanking(16, 416, 328, { oculta }) + nav(676, "Gastos");
}

const META = { necessidades: 50, desejos: 30, poupanca: 20 };
const ESSENCIAL = 2790, IMPORTANTE = 1240.1, FLEXIVEL = 885;
function carta5030(x, y, w) {
  const partes = [["Necessidades", ESSENCIAL, c.essencial, "Essencial", META.necessidades], ["Desejos", IMPORTANTE + FLEXIVEL, c.importante, "Importante + Flexível", META.desejos], ["Poupança", SOBROU, c.mata, "O que sobrou", META.poupanca]];
  const pc = percentuais(partes.map((p) => p[1])), bw = w - 32;
  let s = cartao(x, y, w, 204) + txt(x + 16, y + 28, "Regra 50/30/20", { t: 16, p: 600 }) + txt(x + w - 16, y + 28, `Entrou R$ ${brl(ENTROU)}`, { t: 12, a: "end", cor: c.onSurfaceVariant }) +
    rr(x + 16, y + 48, bw, 14, 7, c.surfaceContainerHighest);
  let ini = 0;
  partes.forEach(([, v, cor], i) => { const pw = (bw * v) / ENTROU; s += rr(x + 16 + ini, y + 48, Math.max(4, pw - SEP), 14, i === 0 ? 7 : 3, cor); ini += pw; });
  [50, 80].forEach((m) => { s += `<path d="M${x + 16 + (bw * m) / 100} ${y + 44}v22" stroke="${c.onSurface}" stroke-width="1.5" stroke-dasharray="2 2"/>`; });
  partes.forEach(([n, v, cor, sub, meta], i) => {
    const yy = y + 82 + i * 38;
    s += rr(x + 16, yy - 2, 12, 12, 3, cor) + txt(x + 36, yy + 9, n, { t: 14, p: 600 }) + txt(x + 36, yy + 26, `${sub} · R$ ${brl(v)}`, { t: 11, cor: c.onSurfaceVariant }) +
      txt(x + w - 16, yy + 9, `${pc[i]}%`, { t: 15, p: 700, a: "end" }) + txt(x + w - 16, yy + 26, `meta ${meta}%`, { t: 11, a: "end", cor: c.onSurfaceVariant });
  });
  return s;
}
const MESES = [["jun", 4380], ["jul", 4620], ["ago", 4510], ["set", 4790], ["out", 4690], ["nov", TOTAL]];
const MEDIA = MESES.slice(0, 5).reduce((a, [, v]) => a + v, 0) / 5;
const mil = (v) => `${(v / 1000).toFixed(1).replace(".", ",")} mil`;
function cartaoEvolucao(x, y, w, h = 176) {
  const base = y + h - 46, topo = y + 56, escala = (base - topo) / 5200, passo = (w - 32) / MESES.length;
  let s = cartao(x, y, w, h) + txt(x + 16, y + 28, "Evolução", { t: 16, p: 600 }) + txt(x + w - 16, y + 28, "Saiu por mês · tracejado é a média", { t: 11, a: "end", cor: c.onSurfaceVariant });
  const ym = base - MEDIA * escala;
  MESES.forEach(([m, v], i) => {
    const bx = x + 16 + i * passo + (passo - 30) / 2, bh = v * escala, ultimo = i === MESES.length - 1;
    s += rr(bx, base - bh, 30, bh, 6, ultimo ? c.primary : c.outline) + txt(bx + 15, base + 32, mil(v), { t: 11, p: ultimo ? 700 : 400, a: "middle", cor: ultimo ? c.onSurface : c.onSurfaceVariant }) +
      txt(bx + 15, base + 18, m, { t: 12, p: ultimo ? 700 : 400, a: "middle", cor: c.onSurfaceVariant });
  });
  return s + `<path d="M${x + 16} ${ym.toFixed(1)}H${x + w - 16}" stroke="${c.onSurfaceVariant}" stroke-width="1.5" stroke-dasharray="4 4"/>`;
}
function cartaoMedia(x, y, w) {
  const bw = w - 32 - 84 - 80, maxV = Math.max(TOTAL, MEDIA), pct = ((TOTAL / MEDIA - 1) * 100).toFixed(1).replace(".", ",");
  let s = cartao(x, y, w, 100) + txt(x + 16, y + 26, "Novembro x média", { t: 16, p: 600 });
  [["Novembro", TOTAL, c.primary], ["Média", MEDIA, c.outline]].forEach(([n, v, cor], i) => {
    const yy = y + 38 + i * 22;
    s += txt(x + 16, yy + 12, n, { t: 12, cor: c.onSurfaceVariant }) + rr(x + 84, yy, (bw * v) / maxV, 14, 7, cor) + txt(x + w - 16, yy + 12, `R$ ${brl(v)}`, { t: 12, p: 600, a: "end" });
  });
  return s + txt(x + 16, y + 90, `${pct}% acima da média dos 5 meses anteriores`, { t: 12, cor: c.onSurfaceVariant });
}
function gastosPlanos() {
  return marca(20, 62, "Gastos", { t: 26 }) + icone("olho", 314, 38, c.onSurface) + abasGastos(76) + seletorMes(132) +
    carta5030(16, 176, 328) + cartaoEvolucao(16, 388, 328, 168) + cartaoMedia(16, 566, 328) + nav(676, "Gastos");
}
// Nível de gasto por dia (0 = sem gasto), do dia 1 ao 30; os dias depois do 26 ainda não aconteceram.
const NIVEIS_DIA = [3, 1, 0, 2, 5, 1, 0, 0, 2, 1, 4, 1, 3, 0, 2, 1, 0, 3, 2, 5, 1, 1, 0, 2, 3, 4, 0, 0, 0, 0];
// Mapa de calor: um matiz só (Caramelo); dia sem gasto é célula vazia com borda; dias futuros ficam apagados.
function cartaoCalor(x, y, w) {
  const cel = 30, gap = 6, x0 = x + (w - (7 * cel + 6 * gap)) / 2;
  let s = cartao(x, y, w, 276) + txt(x + 16, y + 28, "Dia a dia", { t: 16, p: 600 }) + txt(x + w - 16, y + 28, "novembro", { t: 12, a: "end", cor: c.onSurfaceVariant });
  ["D", "S", "T", "Q", "Q", "S", "S"].forEach((d, i) => { s += txt(x0 + i * (cel + gap) + cel / 2, y + 52, d, { t: 11, a: "middle", cor: c.onSurfaceVariant }); });
  for (let dia = 1; dia <= 30; dia++) {
    const col = (dia - 1) % 7, lin = Math.floor((dia - 1) / 7), cx = x0 + col * (cel + gap), cy = y + 62 + lin * (cel + gap);
    if (dia > 26) { s += rr(cx, cy, cel, cel, 6, "none", { borda: c.outlineVariant, op: 0.5 }); continue; }
    const nivel = NIVEIS_DIA[dia - 1];
    s += nivel === 0 ? rr(cx, cy, cel, cel, 6, "none", { borda: c.outlineVariant }) : rr(cx, cy, cel, cel, 6, c.heat[Math.min(4, nivel - 1)]);
  }
  s += txt(x + 16, y + 262, "menos", { t: 11, cor: c.onSurfaceVariant });
  c.heat.forEach((h, i) => { s += rr(x + 60 + i * 18, y + 252, 14, 14, 3, h); });
  return s + txt(x + 60 + 5 * 18 + 6, y + 262, "mais", { t: 11, cor: c.onSurfaceVariant });
}

// ---------- Folhas ----------
const G = 32, LEG = 44;
function folhaCelulares(nome, telas, titulo) {
  const W = telas.length * (CEL.w + G) + G;
  grava(import.meta.url, nome, W, CEL.h + G + LEG + 12,
    telas.map(([t, l], i) => `<g transform="translate(${G + i * (CEL.w + G)} ${G})">${celular(0, 0, t, l)}</g>`).join(""), titulo);
}
function trilho(ativo, H = 800) {
  let s = rr(0, 0, 88, H, 0, c.surfaceContainer) + `<path d="M88 0V${H}" stroke="${c.outlineVariant}"/>` + rr(16, 24, 56, 56, 16, c.primary) + icone("mais", 32, 40, c.onPrimary, 24, 2.2);
  [["casa", "Início"], ["lista", "Extrato"], ["pizza", "Gastos"], ["balao", "Paçoca"]].forEach(([ic, l], i) => {
    const yy = 112 + i * 64, sel = l === ativo;
    s += (sel ? rr(16, yy, 56, 30, 15, c.secondaryContainer) : "") + icone(ic, 32, yy + 3, sel ? c.onSecondaryContainer : c.onSurfaceVariant) + txt(44, yy + 48, l, { t: 12, p: 600, a: "middle", cor: sel ? c.onSurface : c.onSurfaceVariant });
  });
  return s + icone("engrenagem", 32, H - 56, c.onSurfaceVariant);
}
function extratoDesktop() {
  const W = 1280, H = 800;
  let s = rr(0, 0, W, H, 0, c.surface) + trilho("Extrato") + marca(120, 66, "Extrato", { t: 30 }) +
    busca(120, 88, 520, null) + icone("filtro", 656, 100, c.onSurface) +
    chipsLinha(120, 148, [["Todos os bancos", { sel: true }], ["Novembro", { sel: true }], ["Forma de pagamento"], ["Só a revisar"]]) +
    txt(122, 208, "42 lançamentos · Saiu R$ 4.915,10", { t: 12, cor: c.onSurfaceVariant });
  const lista = [["Hoje · quinta, 26 de nov.", [L.mercado, L.posto, L.cafe]], ["Ontem · quarta, 25 de nov.", [L.loja, L.streaming, L.farmacia]]];
  let yy = 214;
  for (const [rot, itens] of lista) {
    s += txt(122, yy + 14, rot, { t: 13, p: 600, cor: c.onSurfaceVariant }) + cartao(120, yy + 26, 560, itens.length * 62 + 8);
    itens.forEach((d, i) => { s += linha(132, yy + 30 + i * 62, 536, d, { sel: d === L.mercado }); if (i < itens.length - 1) s += separador(132, yy + 30 + (i + 1) * 62 - 1, 536); });
    yy += 26 + itens.length * 62 + 8 + 20;
  }
  s += cartao(712, 96, 536, 640) + icone("fechar", 1204, 112, c.onSurfaceVariant, 24) + txt(736, 124, "Lançamento", { t: 13, p: 600, cor: c.onSurfaceVariant }) +
    detalhe(736, 140, 488) + botao(1000, 156, 224, "Corrigir lançamento", "tonal");
  return { W, H, s };
}
function gastosDesktop() {
  const W = 1280, H = 864;
  let s = rr(0, 0, W, H, 0, c.surface) + trilho("Gastos", 864) + marca(120, 66, "Gastos", { t: 30 });
  s += rr(432, 40, 400, 44, 22, c.surfaceContainer, { borda: c.outlineVariant }) + ["Análise", "Planejamento"].map((l, i) =>
    (i === 0 ? rr(436 + i * 196, 44, 196, 36, 18, c.secondaryContainer) : "") + txt(534 + i * 196, 68, l, { t: 14, p: 600, a: "middle", cor: i === 0 ? c.onSecondaryContainer : c.onSurfaceVariant })).join("");
  s += icone("voltar", 1000, 42, c.onSurface, 28) + marca(1124, 62, "Novembro de 2026", { t: 16, a: "middle" }) + icone("direita", 1218, 42, c.outlineVariant, 28);
  s += chipsLinha(120, 100, [["Todos os bancos", { sel: true }], ["Todas as formas", { sel: true }], ["Essencialidade"]]) + icone("olho", 1216, 104, c.onSurface);
  s += cartaoRosca(120, 152, 520, { grande: true }) + cartaoRanking(120, 414, 520, { linhaH: 44 }) +
    cartaoMedia(120, 706, 520) + carta5030(672, 152, 576) + cartaoEvolucao(672, 368, 576, 176) + cartaoCalor(672, 556, 576);
  return { W, H, s };
}

for (const tema of ["claro", "escuro"]) {
  usar(tema);
  folhaCelulares(`extrato-${tema}`, [
    [extratoConsolidado(), "Extrato de todos os bancos"],
    [extratoBanco(), "Extrato por banco"],
    [extratoBusca(), "Busca com filtros ligados"],
    [folhaFiltros("Filtros", SECOES_EXTRATO(), "Mostrar 42 lançamentos", extratoConsolidado()), "Folha de filtros"],
  ], `Extrato no celular, tema ${tema}`);
  const ed = extratoDesktop();
  grava(import.meta.url, `extrato-desktop-${tema}`, ed.W, ed.H, ed.s, `Extrato no desktop com o detalhe ao lado, tema ${tema}`);
  folhaCelulares(`detalhe-${tema}`, [
    [telaDetalhe(), "Detalhe do lançamento"],
    [folhaCorrecao(), "Folha de correção"],
    [telaHistorico(), "Histórico com Desfazer"],
  ], `Detalhe, correção e histórico do lançamento, tema ${tema}`);
  folhaCelulares(`gastos-${tema}`, [
    [gastosAnalise(), "Gastos: para onde foi"],
    [gastosPlanos(), "Gastos: 50/30/20 e evolução"],
    [folhaFiltros("Filtrar gastos", SECOES_GASTOS(), "Mostrar gastos", gastosAnalise()), "Folha de filtros"],
    [gastosAnalise({ oculta: true }), "Valores ocultos: só percentuais"],
  ], `Gastos no celular, tema ${tema}`);
  const gd = gastosDesktop();
  grava(import.meta.url, `gastos-desktop-${tema}`, gd.W, gd.H, gd.s, `Gastos no desktop, tema ${tema}`);
}
console.log("10 folhas gravadas em docs/design/telas");
