// Gera logo, símbolo e ícones do GranaPaCá em SVG. Uso: node docs/design/logo/gerar-logo.mjs
// O letreiro é desenhado em traço redondo (geometria da Fredoka SemiBold), não com a fonte: assim o
// logo sai igual em qualquer lugar, sem depender da fonte instalada, e o acento do á vira a moedinha.
import { writeFileSync } from "node:fs";

const f = (n) => +n.toFixed(1);
const rad = (g) => (g * Math.PI) / 180;

// ---------- Letreiro ----------
const SW = 13; // espessura do traço
const BASE = 93.5, XT = 66.5, CT = 48.5, MEIO = 71, BOJO = 80; // linhas de centro do traço

const GLIFOS = {
  G: (x) => { const rx = 24, ry = 22.5, cx = x + rx, a = rad(40);
    return { d: `M${f(cx + rx * Math.cos(a))} ${f(MEIO - ry * Math.sin(a))} A${rx} ${ry} 0 1 0 ${cx + rx} ${MEIO} H${cx + 7}`, w: 2 * rx }; },
  r: (x) => ({ d: `M${x} ${BASE} V${XT} M${x} ${BOJO} C${x} 71 ${x + 5} ${XT} ${x + 16} ${XT}`, w: 16 }),
  a: (x) => ({ d: `M${x + 28} ${XT} V${BASE} M${x + 28} ${BOJO} A14 13.5 0 1 0 ${x} ${BOJO} A14 13.5 0 1 0 ${x + 28} ${BOJO}`, w: 28 }),
  n: (x) => ({ d: `M${x} ${BASE} V${XT} M${x} 82 C${x} 71 ${x + 6} ${XT} ${x + 13} ${XT} C${x + 21} ${XT} ${x + 26} 72 ${x + 26} ${BOJO} V${BASE}`, w: 26 }),
  P: (x) => ({ d: `M${x} ${BASE} V${CT} H${x + 12} A13 13 0 0 1 ${x + 12} ${CT + 26} H${x}`, w: 25 }),
  C: (x) => { const rx = 23, ry = 22.5, cx = x + rx, a = rad(48), dx = f(cx + rx * Math.cos(a));
    return { d: `M${dx} ${f(MEIO - ry * Math.sin(a))} A${rx} ${ry} 0 1 0 ${dx} ${f(MEIO + ry * Math.sin(a))}`, w: f(rx + rx * Math.cos(a)) }; },
};
const KERN = { Gr: 1, ra: -3, an: 0, na: 0, aP: 1, Pa: -2, aC: 0, Ca: -1 };
const ESPACO = 6;

function letreiro() {
  const texto = "GranaPaCa";
  let x = SW / 2 + 1, d = "", acento = null;
  for (let i = 0; i < texto.length; i++) {
    const g = GLIFOS[texto[i]](x);
    d += g.d + " ";
    if (i === texto.length - 1) acento = { cx: x + 13, cy: 47 }; // o último "a" é o á
    x += g.w + SW + ESPACO + (KERN[texto[i] + (texto[i + 1] ?? "")] ?? 0);
  }
  return { d: d.trim(), largura: Math.ceil(x - ESPACO - SW / 2 + 1), acento };
}
const L = letreiro();
const TOPO = 22; // acima da moeda e dos rastros
const ALTURA = 100 + 2 - TOPO;

// Moeda do acento: cai na direção do acento agudo, com dois rastros para cima e à direita.
function moeda({ cx, cy }, cores) {
  const rastros = [[6, -7, 11, -14], [10, -1, 16, -8]].map(([x0, y0, x1, y1]) =>
    `<path d="M${cx + x0} ${cy + y0} L${cx + x1} ${cy + y1}" stroke="${cores.rastro}" stroke-width="3.2" stroke-linecap="round"/>`).join("");
  if (cores.mono) {
    // Uma cor só: anel e miolo, com o vão vazado (funciona sobre qualquer fundo).
    return rastros + `<path fill-rule="evenodd" fill="${cores.rastro}" d="M${cx - 8.5} ${cy} a8.5 8.5 0 1 0 17 0 a8.5 8.5 0 1 0 -17 0 Z M${cx - 6} ${cy} a6 6 0 1 1 12 0 a6 6 0 1 1 -12 0 Z M${cx - 4.2} ${cy} a4.2 4.2 0 1 0 8.4 0 a4.2 4.2 0 1 0 -8.4 0 Z"/>`;
  }
  return rastros + `<circle cx="${cx}" cy="${cy}" r="8.5" fill="${cores.moeda}"/>` +
    `<circle cx="${cx}" cy="${cy}" r="5.3" fill="none" stroke="${cores.anel}" stroke-width="1.8"/>` +
    `<circle cx="${cx - 2.6}" cy="${cy - 2.8}" r="1.7" fill="${cores.brilho}"/>`;
}

const LOGO = {
  cor: { letra: "#A0521A", rastro: "#A0521A", moeda: "#E5A62B", anel: "#A0521A", brilho: "#F7D27A" },
  escuro: { letra: "#E8A066", rastro: "#E8A066", moeda: "#F3C35A", anel: "#8E4A20", brilho: "#FBE3A6", fundo: "#17110D" },
  mono: { letra: "currentColor", rastro: "currentColor", mono: true },
};
function logo(nome, { respiro = false } = {}) {
  const c = LOGO[nome], m = respiro ? 40 : 0; // respiro = altura do "a" (40 unidades)
  const vb = `${-m} ${TOPO - m} ${L.largura + 2 * m} ${ALTURA + 2 * m}`;
  const guia = respiro
    ? `<rect x="${-m}" y="${TOPO - m}" width="${L.largura + 2 * m}" height="${ALTURA + 2 * m}" fill="#FBF5EC"/>` +
      `<rect x="0" y="${TOPO}" width="${L.largura}" height="${ALTURA}" fill="none" stroke="#94816E" stroke-width="1" stroke-dasharray="4 3"/>` +
      `<rect x="${-m + 1}" y="${TOPO - m + 1}" width="${L.largura + 2 * m - 2}" height="${ALTURA + 2 * m - 2}" fill="none" stroke="#B83A22" stroke-width="1.5" stroke-dasharray="6 4"/>` +
      `<g fill="none" stroke="#22649C" stroke-width="1.5"><path d="M${-m + 4} ${TOPO + 20} H-4"/><path d="M${L.largura + 4} ${TOPO + 20} H${L.largura + m - 4}"/></g>` +
      `<text x="${-m / 2}" y="${TOPO + 14}" font-family="Inter, sans-serif" font-size="11" fill="#22649C" text-anchor="middle">x</text>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb}" role="img" aria-labelledby="t"><title id="t">GranaPaCá</title>` +
    guia + (c.fundo && !respiro ? `<rect x="${-m}" y="${TOPO - m}" width="${L.largura + 2 * m}" height="${ALTURA + 2 * m}" fill="${c.fundo}"/>` : "") +
    tracoLogo(c) + `</svg>\n`;
}
// O letreiro é feito de traços (stroke); para gravação ou recorte, expandir os traços num editor vetorial.
function tracoLogo(c) {
  return `<path d="${L.d}" fill="none" stroke="${c.letra}" stroke-width="${SW}" stroke-linecap="round" stroke-linejoin="round"/>` + moeda(L.acento, c);
}

// ---------- Símbolo e ícone: cabeça da Paçoca de perfil com três pintas em linha ----------
// Coordenadas da cabeça iguais às do perfil da mascote (docs/design/mascote/gerar-pacoca.mjs).
const CABECA = "M156 104 C166 88 196 88 208 104 C216 112 226 116 227 126 C228 136 218 141 208 141 C192 145 168 142 156 128 Z";
// Pescoço do ícone: sai pela borda de baixo. O do símbolo termina arredondado dentro do quadro.
const PESCOCO = "M160 106 C138 112 118 138 114 178 L114 240 L192 240 L192 178 C188 158 182 146 170 138 Q164 122 160 106 Z";
const PESCOCO_SIMBOLO = "M160 106 C138 112 118 138 114 178 L114 192 C114 204 122 210 134 210 L172 210 C184 210 192 204 192 192 L192 178 C188 158 182 146 170 138 Q164 122 160 106 Z";
// Pintas alongadas, como as fileiras do flanco: [x, y, inclinação]. Redondas com anel pareciam botões.
const PINTAS = [[134, 163, -8], [154, 161, -6], [173, 160, -4]];
const pinta = ([x, y, a], cor) => `<ellipse cx="${x}" cy="${y}" rx="8.5" ry="5.2" fill="${cor}" transform="rotate(${a} ${x} ${y})"/>`;

// Sete cores no máximo, contando o fundo: o creme faz pintas, bochecha, orelha e brilho do olho.
const PALETA = {
  claro: { fundo: "#A0521A", cabeca: "#E3A775", pescoco: "#D2925C", escuro: "#2A1C12", marrom: "#8E4A20", creme: "#F7E6CC", nariz: "#D9877A" },
  escuro: { fundo: "#17110D" },
  simbolo: { fundo: null, cabeca: "#B96A35", pescoco: "#A55E2E" },
  tingido: { fundo: null, cabeca: "#D9D9D9", pescoco: "#BFBFBF", escuro: "#262626", marrom: "#595959", creme: "#F2F2F2", nariz: "#A6A6A6" },
};
const paleta = (nome) => ({ ...PALETA.claro, ...PALETA[nome] });

function marca(p, { bigodes = true, pescoco = PESCOCO } = {}) {
  const fio = (d) => `<path d="${d}" fill="none" stroke="${p.marrom}" stroke-width="1.6" stroke-linecap="round"/>`;
  return [
    `<path d="${pescoco}" fill="${p.pescoco}"/>`,
    PINTAS.map((q) => pinta(q, p.creme)).join(""),
    `<circle cx="168" cy="93" r="9" fill="${p.marrom}"/><circle cx="168" cy="94" r="4.5" fill="${p.creme}"/>`,
    `<path d="${CABECA}" fill="${p.cabeca}"/>`,
    `<ellipse cx="186" cy="128" rx="15" ry="10" fill="${p.creme}"/>`,
    `<circle cx="190" cy="108" r="7" fill="${p.escuro}"/><circle cx="187.8" cy="105.8" r="2.4" fill="${p.creme}"/>`,
    `<ellipse cx="224" cy="124" rx="5.5" ry="5" fill="${p.nariz}"/>`,
    `<path d="M213 135 Q217 138 222 134" fill="none" stroke="${p.marrom}" stroke-width="2.4" stroke-linecap="round"/>`,
    bigodes ? fio("M218 129 Q228 122 238 114") + fio("M218 131 Q229 130 240 131") + fio("M217 133 Q227 140 235 149") : "",
  ].join("");
}
const simbolo = () => encaixa(1.45, marca(paleta("simbolo"), { pescoco: PESCOCO_SIMBOLO }), 104);
// Encaixa a marca (centro ~ 172,128 nas coordenadas da cabeça) no quadro 240×240.
const encaixa = (escala, conteudo, cy = 124) => `<g transform="translate(120 ${cy}) scale(${escala}) translate(-174 -128)">${conteudo}</g>`;
const svg240 = (titulo, corpo, extra = "") => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" role="img" aria-labelledby="t"${extra}><title id="t">${titulo}</title>${corpo}</svg>\n`;
const fundo = (cor) => (cor ? `<rect width="240" height="240" fill="${cor}"/>` : "");

// Monocromático (Android, ícone temático): só a forma importa; olho e pintas ficam vazados.
function mono() {
  const m = `<mask id="m"><path d="${PESCOCO}" fill="#fff"/><circle cx="168" cy="93" r="9" fill="#fff"/><path d="${CABECA}" fill="#fff"/>` +
    PINTAS.map((q) => pinta(q, "#000")).join("") +
    `<circle cx="168" cy="94" r="4.5" fill="#000"/><circle cx="190" cy="108" r="7" fill="#000"/><circle cx="187.8" cy="105.8" r="2.4" fill="#fff"/>` +
    `<path d="M213 135 Q217 138 222 134" fill="none" stroke="#000" stroke-width="2.4" stroke-linecap="round"/></mask>`;
  return encaixa(1.3, `<defs>${m}</defs><rect x="0" y="0" width="300" height="300" fill="#000000" mask="url(#m)"/>`);
}

const ARQUIVOS = {
  "logo-cor.svg": logo("cor"),
  "logo-escuro.svg": logo("escuro"),
  "logo-mono.svg": logo("mono"),
  "logo-respiro.svg": logo("cor", { respiro: true }),
  "simbolo.svg": svg240("Símbolo do GranaPaCá", simbolo()),
  // Logo empilhado: símbolo em cima, letreiro embaixo, para espaços estreitos (o horizontal é muito largo).
  "logo-empilhado.svg": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 28 ${L.largura} 274" role="img" aria-labelledby="t"><title id="t">GranaPaCá</title>` +
    `<g transform="translate(${L.largura / 2 - 100} 0) scale(${f(200 / 240)})">${simbolo()}</g>` +
    `<g transform="translate(0 ${220 - TOPO})">${tracoLogo(LOGO.cor)}</g></svg>\n`,
  // iOS: quadro inteiro de 1024 px; o sistema aplica o recorte [Conferir: Apple HIG, App icons].
  "icone-ios-claro.svg": svg240("Ícone do GranaPaCá", fundo(PALETA.claro.fundo) + encaixa(1.55, marca(paleta("claro")))),
  "icone-ios-escuro.svg": svg240("Ícone do GranaPaCá, aparência escura", fundo(PALETA.escuro.fundo) + encaixa(1.55, marca(paleta("escuro")))),
  "icone-ios-tingido.svg": svg240("Ícone do GranaPaCá, aparência tingida", encaixa(1.55, marca(paleta("tingido")))),
  // Android adaptativo: camadas de 108 dp; o essencial fica no círculo seguro de 66 dp (raio ~73 em 240).
  "icone-android-fundo.svg": svg240("Fundo do ícone adaptativo", fundo(PALETA.claro.fundo)),
  "icone-android-frente.svg": svg240("Frente do ícone adaptativo", encaixa(1.3, marca(paleta("claro")))),
  "icone-android-mono.svg": svg240("Ícone monocromático", mono()),
  // Favicon da demo web: sem bigodes e maior, para ler em 16 a 32 px.
  "favicon.svg": svg240("GranaPaCá", `<rect width="240" height="240" rx="56" fill="${PALETA.claro.fundo}"/>` + encaixa(1.75, marca(paleta("claro"), { bigodes: false }), 116)),
};
const pasta = new URL("./", import.meta.url);
for (const [nome, conteudo] of Object.entries(ARQUIVOS)) writeFileSync(new URL(nome, pasta), conteudo);
console.log(`${Object.keys(ARQUIVOS).length} SVGs gravados em docs/design/logo`);
