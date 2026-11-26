// Peças comuns aos geradores de telas (Identidade Toca Editorial): cores, texto, formas, ícones e Paçoca refinada.
import { readFileSync, writeFileSync } from "node:fs";
export const T = JSON.parse(readFileSync(new URL("../tokens/tokens.json", import.meta.url), "utf8"));
const MINI = JSON.parse(readFileSync(new URL("./pacoca-mini.json", import.meta.url), "utf8"));
export const INTERFACE = "Inter, system-ui, -apple-system, sans-serif";
export const MARCA = "'Plus Jakarta Sans', Inter, system-ui, -apple-system, sans-serif";
export let c; // cores do tema em uso
export function usar(tema) {
  c = {
    ...T.cor.esquema[tema], ...T.cor.marca[tema], tema, heat: T.cor.grafico.sequencial[tema],
    g: Object.fromEntries(T.cor.categorias.map((k) => [k.id, T.cor.grafico[tema][k.cor]])),
  };
  return c;
}
export const txt = (x, y, s, { t = 14, p = 400, cor = c.onSurface, a = "start", f = INTERFACE } = {}) =>
  `<text x="${x}" y="${y}" font-family="${f}" font-size="${t}" font-weight="${p}" fill="${cor}" text-anchor="${a}">${s}</text>`;
export const linhas = (x, y, ls, o = {}, dy = 20) => ls.map((l, i) => txt(x, y + i * dy, l, o)).join("");
export const marca = (x, y, s, o = {}) => txt(x, y, s, { p: 700, f: MARCA, ...o });
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
  cadeado: "M7 11V8a5 5 0 0 1 10 0v3M5 11h14v9H5Z",
  engrenagem: "M12 9a3 3 0 1 0 0 6a3 3 0 0 0 0-6ZM12 3v3M12 18v3M3 12h3M18 12h3M5.6 5.6l2.1 2.1M16.3 16.3l2.1 2.1M5.6 18.4l2.1-2.1M16.3 7.7l2.1-2.1",
};
export const icone = (n, x, y, cor, t = 24, l = 1.8) =>
  `<path d="${I[n]}" transform="translate(${x} ${y}) scale(${t / 24})" fill="none" stroke="${cor}" stroke-width="${l}" stroke-linecap="round" stroke-linejoin="round"/>`;
export const pintas = (x, y, n, cor, vazia = c.outline) => [0, 1, 2].map((k) =>
  `<circle cx="${x + k * 12}" cy="${y}" r="4" fill="${k < n ? cor : "none"}" stroke="${k < n ? cor : vazia}" stroke-width="1.5"/>`).join("");

// Paçoca ilustrada herdada (ex.: dormindo no estado vazio).
export function pacoca(nome, x, y, alt) {
  const m = MINI[nome], w = (alt * m.w) / m.h;
  return `<image href="${m.uri}" x="${(x - w / 2).toFixed(1)}" y="${(y - alt).toFixed(1)}" width="${w.toFixed(1)}" height="${alt}"/>`;
}

let nPacClip = 0;

// Paçoca refinada da Toca Editorial (sem contorno preto, sem pochete, focinho suavemente alongado de paca).
// Estados: "modo", "email", "senha", "seguranca", "pronto", "pensando", "retrato".
export function pacocaEditorial(estado, cx, baseY, escala = 1, { camada = "todas" } = {}) {
  if (camada === "frente" && estado !== "seguranca") return "";
  const pele = "#C97C44", peleEsc = "#AE632F", peleClara = "#D9945C", creme = "#F6E5CC", nariz = "#E0876F", olho = "#23160E";
  const pintasFlanco =
    `<ellipse cx="-44" cy="-34" rx="5" ry="9" transform="rotate(-14 -44 -34)" fill="${creme}" opacity="0.9"/>` +
    `<ellipse cx="-35" cy="-14" rx="4.5" ry="8" transform="rotate(-8 -35 -14)" fill="${creme}" opacity="0.88"/>` +
    `<ellipse cx="44" cy="-34" rx="5" ry="9" transform="rotate(14 44 -34)" fill="${creme}" opacity="0.9"/>` +
    `<ellipse cx="35" cy="-14" rx="4.5" ry="8" transform="rotate(8 35 -14)" fill="${creme}" opacity="0.88"/>`;

  const orelhas =
    `<ellipse cx="-34" cy="-98" rx="12" ry="11" transform="rotate(-22 -34 -98)" fill="${peleEsc}"/>` +
    `<ellipse cx="-34" cy="-97" rx="7" ry="6.5" transform="rotate(-22 -34 -97)" fill="#E9A48B"/>` +
    `<ellipse cx="34" cy="-98" rx="12" ry="11" transform="rotate(22 34 -98)" fill="${peleEsc}"/>` +
    `<ellipse cx="34" cy="-97" rx="7" ry="6.5" transform="rotate(22 34 -97)" fill="#E9A48B"/>`;

  // Cabeça com bochechas arredondadas e focinho alongado suave característico de paca.
  const cabecaBase = (dx = 0, dy = 0, rot = 0) =>
    `<g transform="translate(${dx} ${dy}) rotate(${rot} 0 -70)">` +
    orelhas +
    `<path d="M-44 -68 C-46 -98 -24 -110 0 -110 C24 -110 46 -98 44 -68 C43 -46 28 -36 0 -36 C-28 -36 -43 -46 -44 -68 Z" fill="${pele}"/>` +
    `<ellipse cx="0" cy="-54" rx="25" ry="17" fill="${creme}"/>` +
    `<ellipse cx="0" cy="-61" rx="9.5" ry="6.5" fill="${nariz}"/>` +
    `<path d="M0 -54 V-50 M-8 -49 Q0 -44 8 -49" fill="none" stroke="${olho}" stroke-width="2.2" stroke-linecap="round"/>` +
    `<path d="M-32 -56 Q-46 -58 -56 -53 M-32 -50 Q-46 -49 -54 -43 M32 -56 Q46 -58 56 -53 M32 -50 Q46 -49 54 -43" fill="none" stroke="${peleEsc}" stroke-width="1.3" stroke-linecap="round" opacity="0.7"/>`;

  const olhosNormais = (px = 0, py = 0) =>
    `<ellipse cx="-18" cy="-76" rx="7.5" ry="9" fill="${olho}"/>` +
    `<circle cx="${-16 + px}" cy="${-79 + py}" r="2.6" fill="#FFFFFF"/>` +
    `<ellipse cx="18" cy="-76" rx="7.5" ry="9" fill="${olho}"/>` +
    `<circle cx="${20 + px}" cy="${-79 + py}" r="2.6" fill="#FFFFFF"/>`;

  const olhosFelizes =
    `<path d="M-25 -76 Q-18 -84 -11 -76" fill="none" stroke="${olho}" stroke-width="3" stroke-linecap="round"/>` +
    `<path d="M11 -76 Q18 -84 25 -76" fill="none" stroke="${olho}" stroke-width="3" stroke-linecap="round"/>`;

  const corpo =
    `<path d="M-46 0 C-50 -36 -38 -56 0 -56 C38 -56 50 -36 46 0 Z" fill="${pele}"/>` +
    `<ellipse cx="0" cy="-18" rx="26" ry="26" fill="${creme}"/>` +
    pintasFlanco;

  const patasBorda =
    `<ellipse cx="-28" cy="2" rx="13" ry="8" fill="${peleClara}"/>` +
    `<ellipse cx="28" cy="2" rx="13" ry="8" fill="${peleClara}"/>`;

  let s = "";
  if (estado === "retrato") {
    const clipId = `pacClip${nPacClip++}`;
    s = `<clipPath id="${clipId}"><circle cx="0" cy="-64" r="46"/></clipPath>` +
      `<circle cx="0" cy="-64" r="46" fill="${c.secondaryContainer}"/>` +
      `<g clip-path="url(#${clipId})">` + corpo + cabecaBase(0, 6, 0) + olhosNormais(0, 0) + `</g></g>`;
  } else if (estado === "modo") {
    s = corpo + cabecaBase(-4, 0, -6) + olhosNormais(-3, 2) + `</g>` + patasBorda;
  } else if (estado === "email") {
    s = corpo + cabecaBase(5, 4, 8) + olhosNormais(4, 4) + `</g>` + patasBorda;
  } else if (estado === "senha") {
    // Patas levantadas tampando os olhos + bolha discreta da espiadinha no canto superior direito.
    const patasNosOlhos =
      `<path d="M-40 -14 C-46 -46 -36 -74 -16 -84 C-6 -88 0 -80 -4 -66 C-8 -52 -16 -38 -20 -14 Z" fill="${peleClara}"/>` +
      `<path d="M40 -14 C46 -46 36 -74 16 -84 C6 -88 0 -80 4 -66 C8 -52 16 -38 20 -14 Z" fill="${peleClara}"/>`;
    const bolhaEspia =
      `<g transform="translate(70 -92)">` +
      `<circle cx="0" cy="0" r="21" fill="${c.surfaceContainerLow}" stroke="${c.outlineVariant}" stroke-width="1.2"/>` +
      `<g transform="translate(0 25) scale(0.34)">` +
      cabecaBase(0, 0, 0) + olhosNormais(2, 0) + `</g>` +
      `<path d="M-38 -24 C-42 -52 -32 -78 -14 -84 C-4 -86 0 -76 -6 -62 Z" fill="${peleClara}"/>` +
      `</g></g>`;
    s = corpo + cabecaBase(0, 0, 0) + `</g>` + patasNosOlhos + bolhaEspia;
  } else if (estado === "seguranca") {
    const escudo =
      `<g transform="translate(0 -18)">` +
      `<path d="M0 -24 L22 -16 V2 C22 16 11 25 0 30 C-11 25 -22 16 -22 2 V-16 Z" fill="${c.mata}" stroke="${c.milho}" stroke-width="2.5"/>` +
      `<rect x="-8" y="-3" width="16" height="14" rx="3" fill="${c.milho}"/>` +
      `<path d="M-4 -3 V-8 A4 4 0 0 1 4 -8 V-3" fill="none" stroke="${c.milho}" stroke-width="2.6" stroke-linecap="round"/>` +
      `<circle cx="0" cy="4" r="2.2" fill="${olho}"/></g>`;
    const tras = corpo + cabecaBase(0, -2, 0) + olhosNormais(0, 0) + `</g>`;
    const frente =
      `<ellipse cx="-24" cy="-16" rx="11" ry="8" fill="${peleClara}"/>` +
      `<ellipse cx="24" cy="-16" rx="11" ry="8" fill="${peleClara}"/>` + escudo;
    s = camada === "tras" ? tras : camada === "frente" ? frente : tras + frente;
  } else if (estado === "pronto") {
    const moedas =
      `<circle cx="-58" cy="-86" r="8" fill="${c.milho}" opacity="0.85"/>` +
      `<circle cx="56" cy="-98" r="9.5" fill="${c.milho}" opacity="0.9"/>` +
      `<circle cx="62" cy="-54" r="6" fill="${creme}" stroke="${c.milho}" stroke-width="2"/>`;
    const bracosCima =
      `<ellipse cx="-46" cy="-54" rx="10" ry="18" transform="rotate(-42 -46 -54)" fill="${peleClara}"/>` +
      `<ellipse cx="46" cy="-54" rx="10" ry="18" transform="rotate(42 46 -54)" fill="${peleClara}"/>`;
    s = moedas + `<g transform="translate(0 -10)">` + bracosCima + corpo + cabecaBase(0, -2, 4) + olhosFelizes + `</g></g>`;
  } else {
    s = corpo + cabecaBase(0, 0, -4) + olhosNormais(3, -3) + `</g>` + patasBorda;
  }
  return `<g transform="translate(${cx} ${baseY}) scale(${escala})">${s}</g>`;
}

export function botao(x, y, w, label, tipo = "principal") {
  const [fundo, texto, borda] = {
    principal: [c.primary, c.onPrimary],
    tonal: [c.secondaryContainer, c.onSecondaryContainer],
    contorno: ["none", c.primary, c.outline],
    texto: ["none", c.primary],
  }[tipo];
  return rr(x, y, w, 48, 24, fundo, { borda }) + txt(x + w / 2, y + 29, label, { p: 600, cor: texto, a: "middle" });
}
export function campo(x, y, w, rotulo, valor, { dica, foco } = {}) {
  return txt(x, y - 8, rotulo, { t: 12, p: 600, cor: foco ? c.primary : c.onSurfaceVariant }) +
    rr(x, y, w, 56, 12, c.surfaceContainerLowest, { borda: foco ? c.primary : c.outline, lb: foco ? 2 : 1 }) +
    txt(x + 16, y + 35, valor ?? dica, { t: 15, cor: valor ? c.onSurface : c.onSurfaceVariant });
}
export function chipGrande(x, y, label, sel) {
  const w = Math.round(label.length * 8.2 + 34);
  return [rr(x, y, w, 44, 22, sel ? c.secondaryContainer : "none", { borda: sel ? c.primary : c.outline, lb: sel ? 2 : 1 }) +
    txt(x + w / 2, y + 28, label, { t: 14, p: 600, a: "middle", cor: sel ? c.onSecondaryContainer : c.onSurface }), w];
}
export const cartao = (x, y, w, h, o = {}) => rr(x, y, w, h, 20, c.surfaceContainerLow, { borda: c.outlineVariant, ...o });
export const valor = (x, y, int, cent, t = 38, o = {}) => txt(x, y, `R$ ${int}<tspan font-size="${Math.round(t * 0.56)}">,${cent}</tspan>`, { t, p: 700, ...o });
export function lancamento(x, y, w, nome, info, v, { cat = "alimentacao", banco = c.tertiary, entrada, ic = "garfo" } = {}) {
  const cor = entrada ? c.mata : c.g[cat];
  return rr(x, y + 10, 4, 38, 2, banco) + `<circle cx="${x + 34}" cy="${y + 29}" r="18" fill="${cor}" opacity="0.14"/>` + icone(ic, x + 24, y + 19, cor, 20) +
    txt(x + 62, y + 25, nome, { t: 15, p: 600 }) + txt(x + 62, y + 44, info, { t: 12, cor: c.onSurfaceVariant }) +
    txt(x + w, y + 34, v, { t: 15, p: 600, a: "end", cor: entrada ? c.mata : c.onSurface });
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
export function celular(x, y, conteudo, legenda, fundo = c.surface) {
  const id = `cel${nClip++}`;
  return `<clipPath id="${id}"><rect width="${CEL.w}" height="${CEL.h}" rx="36"/></clipPath>` +
    `<g transform="translate(${x} ${y})"><g clip-path="url(#${id})"><rect width="${CEL.w}" height="${CEL.h}" fill="${fundo}"/>${conteudo}</g>` +
    `<rect width="${CEL.w}" height="${CEL.h}" rx="36" fill="none" stroke="${c.outlineVariant}" stroke-width="2"/>` +
    txt(CEL.w / 2, CEL.h + 26, legenda, { t: 14, p: 600, a: "middle", cor: c.onSurfaceVariant }) + `</g>`;
}
export function grava(url, nome, w, h, corpo, titulo) {
  if (/undefined|NaN/.test(corpo)) throw new Error(`${nome}: undefined ou NaN`);
  writeFileSync(new URL(`./${nome}.svg`, url),
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${w} ${h}" role="img" aria-labelledby="t"><title id="t">${titulo}</title><rect width="${w}" height="${h}" fill="${c.surfaceDim}"/>${corpo}</svg>\n`);
}
