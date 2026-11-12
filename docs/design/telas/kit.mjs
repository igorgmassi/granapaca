// Peças comuns aos geradores de telas: cores do tema, texto, formas, ícones, Paçoca e a moldura do celular.
import { readFileSync, writeFileSync } from "node:fs";
export const T = JSON.parse(readFileSync(new URL("../tokens/tokens.json", import.meta.url), "utf8"));
const MINI = JSON.parse(readFileSync(new URL("./pacoca-mini.json", import.meta.url), "utf8"));
export const INTERFACE = "Figtree, Inter, system-ui, sans-serif", MARCA = "'Baloo 2', ui-rounded, system-ui, sans-serif";
export let c; // cores do tema em uso
export function usar(tema) {
  c = { ...T.cor.esquema[tema], ...T.cor.marca[tema], tema, heat: T.cor.grafico.sequencial[tema],
    g: Object.fromEntries(T.cor.categorias.map((k) => [k.id, T.cor.grafico[tema][k.cor]])) };
  return c;
}
export const txt = (x, y, s, { t = 14, p = 400, cor = c.onSurface, a = "start", f = INTERFACE } = {}) =>
  `<text x="${x}" y="${y}" font-family="${f}" font-size="${t}" font-weight="${p}" fill="${cor}" text-anchor="${a}">${s}</text>`;
export const linhas = (x, y, ls, o = {}, dy = 20) => ls.map((l, i) => txt(x, y + i * dy, l, o)).join("");
export const marca = (x, y, s, o = {}) => txt(x, y, s, { p: 600, f: MARCA, ...o });
export const rr = (x, y, w, h, r, fill, { borda, lb = 1, op } = {}) =>
  `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${fill}"${borda ? ` stroke="${borda}" stroke-width="${lb}"` : ""}${op ? ` opacity="${op}"` : ""}/>`;
const I = {
  casa: "M4 10.5 12 4l8 6.5V20h-5v-6H9v6H4Z", lista: "M9 6h11M9 12h11M9 18h11M4.5 6h.01M4.5 12h.01M4.5 18h.01",
  pizza: "M12 4a8 8 0 1 0 8 8h-8ZM15 3.6A8 8 0 0 1 20.4 9H15Z", balao: "M4 5h16v11H9l-5 4Z", mais: "M12 5v14M5 12h14",
  sino: "M6 10a6 6 0 0 1 12 0c0 4 1.5 6 2 7H4c.5-1 2-3 2-7ZM9.5 20a2.5 2.5 0 0 0 5 0", lupa: "M11 4a7 7 0 1 0 0 14a7 7 0 0 0 0-14ZM16 16l4.5 4.5",
  garfo: "M7 3v8M5 3v5a2 2 0 0 0 4 0V3M7 11v10M17 3c-2 2-2.5 5-2 8h2v10", seta: "M12 4v14M6 12l6 6 6-6", sacola: "M5 8h14l-1 12H6ZM9 8V6a3 3 0 0 1 6 0v2",
  carro: "M4 16v-4l2-5h12l2 5v4ZM4 16v2.5h3V16M17 16v2.5h3V16M4 12h16", alerta: "M12 4 3 20h18ZM12 10v5M12 17.5h.01",
  olho: "M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12ZM12 9a3 3 0 1 0 0 6a3 3 0 0 0 0-6Z", check: "M5 12.5 10 17l9-10",
  qr: "M4 4h6v6H4ZM14 4h6v6h-6ZM4 14h6v6H4ZM14 14h2v2h-2ZM18 14h2v2h-2ZM14 18h2v2h-2ZM18 18h2v2h-2Z", fora: "M14 5h5v5M19 5l-8 8M11 6H6v12h12v-5",
  engrenagem: "M12 9a3 3 0 1 0 0 6a3 3 0 0 0 0-6ZM12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1",
};
export const icone = (n, x, y, cor, t = 24, l = 1.8) =>
  `<path d="${I[n]}" transform="translate(${x} ${y}) scale(${t / 24})" fill="none" stroke="${cor}" stroke-width="${l}" stroke-linecap="round" stroke-linejoin="round"/>`;
export const pintas = (x, y, n, cor, vazia = c.outline) => [0, 1, 2].map((k) =>
  `<circle cx="${x + k * 12}" cy="${y}" r="4" fill="${k < n ? cor : "none"}" stroke="${k < n ? cor : vazia}" stroke-width="1.5"/>`).join("");
// A Paçoca ilustrada, pela altura; (x, y) é o centro da base, onde ela pisa.
export function pacoca(nome, x, y, alt) {
  const m = MINI[nome], w = (alt * m.w) / m.h;
  return `<image href="${m.uri}" x="${(x - w / 2).toFixed(1)}" y="${(y - alt).toFixed(1)}" width="${w.toFixed(1)}" height="${alt}"/>`;
}
export function botao(x, y, w, label, tipo = "principal") {
  const [fundo, texto, borda] = { principal: [c.primary, c.onPrimary], tonal: [c.secondaryContainer, c.onSecondaryContainer], contorno: ["none", c.primary, c.outline], texto: ["none", c.primary] }[tipo];
  return rr(x, y, w, 48, 24, fundo, { borda }) + txt(x + w / 2, y + 29, label, { p: 600, cor: texto, a: "middle" });
}
export function campo(x, y, w, rotulo, valor, { dica, foco } = {}) {
  return txt(x, y - 8, rotulo, { t: 12, p: 600, cor: foco ? c.primary : c.onSurfaceVariant }) + rr(x, y, w, 56, 12, c.surfaceContainerLowest, { borda: foco ? c.primary : c.outline, lb: foco ? 2 : 1 }) +
    txt(x + 16, y + 35, valor ?? dica, { t: 16, cor: valor ? c.onSurface : c.onSurfaceVariant });
}
// Chip grande do guia: devolve [svg, largura].
export function chipGrande(x, y, label, sel) {
  const w = Math.round(label.length * 8.4 + 36);
  return [rr(x, y, w, 44, 22, sel ? c.secondaryContainer : "none", { borda: sel ? c.primary : c.outline, lb: sel ? 2 : 1 }) +
    txt(x + w / 2, y + 28, label, { t: 15, p: 600, a: "middle", cor: sel ? c.onSecondaryContainer : c.onSurface }), w];
}
export const cartao = (x, y, w, h, o = {}) => rr(x, y, w, h, 20, c.surfaceContainerLow, { borda: c.outlineVariant, ...o });
export const valor = (x, y, int, cent, t = 40, o = {}) => txt(x, y, `R$ ${int}<tspan font-size="${t * 0.55}">,${cent}</tspan>`, { t, p: 600, ...o });
export function lancamento(x, y, w, nome, info, v, { cat = "alimentacao", banco = c.tertiary, entrada, ic = "garfo" } = {}) {
  const cor = entrada ? c.mata : c.g[cat];
  return rr(x, y + 8, 4, 40, 2, banco) + `<circle cx="${x + 36}" cy="${y + 28}" r="20" fill="${cor}" opacity="0.16"/>` + icone(ic, x + 25, y + 17, cor, 22) +
    txt(x + 68, y + 24, nome, { t: 16, p: 600 }) + txt(x + 68, y + 44, info, { t: 12, cor: c.onSurfaceVariant }) +
    txt(x + w, y + 33, v, { t: 16, p: 600, a: "end", cor: entrada ? c.mata : c.onSurface });
}
export function nav(y, ativo) {
  let s = rr(0, y, 360, 84, 0, c.surfaceContainer) + `<path d="M0 ${y}H360" stroke="${c.outlineVariant}"/>`;
  [["casa", "Início"], ["lista", "Extrato"], null, ["pizza", "Gastos"], ["balao", "Paçoca"]].forEach((it, i) => {
    const x = 36 + i * 72;
    if (!it) { s += `<circle cx="${x}" cy="${y + 36}" r="26" fill="${c.primary}"/>` + icone("mais", x - 12, y + 24, c.onPrimary, 24, 2.2); return; }
    const sel = it[1] === ativo;
    s += (sel ? rr(x - 28, y + 12, 56, 30, 15, c.secondaryContainer) : "") + icone(it[0], x - 12, y + 15, sel ? c.onSecondaryContainer : c.onSurfaceVariant) +
      txt(x, y + 62, it[1], { t: 12, p: 600, a: "middle", cor: sel ? c.onSurface : c.onSurfaceVariant });
  });
  return s;
}
let nClip = 0;
export const CEL = { w: 360, h: 760 };
// Moldura do celular com o conteúdo recortado e uma legenda embaixo.
export function celular(x, y, conteudo, legenda, fundo = c.surface) {
  const id = `cel${nClip++}`;
  return `<clipPath id="${id}"><rect width="${CEL.w}" height="${CEL.h}" rx="36"/></clipPath>` +
    `<g transform="translate(${x} ${y})"><g clip-path="url(#${id})"><rect width="${CEL.w}" height="${CEL.h}" fill="${fundo}"/>${conteudo}</g>` +
    `<rect width="${CEL.w}" height="${CEL.h}" rx="36" fill="none" stroke="${c.outline}" stroke-width="2"/>` +
    txt(CEL.w / 2, CEL.h + 26, legenda, { t: 14, p: 600, a: "middle", cor: c.onSurfaceVariant }) + `</g>`;
}
export function grava(url, nome, w, h, corpo, titulo) {
  if (/undefined|NaN/.test(corpo)) throw new Error(`${nome}: undefined ou NaN`);
  writeFileSync(new URL(`./${nome}.svg`, url),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" role="img" aria-labelledby="t"><title id="t">${titulo}</title><rect width="${w}" height="${h}" fill="${c.surfaceDim}"/>${corpo}</svg>\n`);
}
