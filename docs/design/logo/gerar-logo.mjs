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

// ---------- Símbolo e ícone: a pochete da Paçoca ----------
// A bolsa verde onde a Paçoca guarda a grana, com a fivela de moeda e três pintas costuradas.
// Quadro 256. O essencial fica no círculo seguro do Android (raio ~78 a partir do centro).
// Escolhida em 2026-11-11 depois de cinco tentativas de ícone com a Paçoca ilustrada (ver 04-logo-e-icone.md).
const P = {
  claro: { fundo: "#A0521A", bolsa: "#2A7550", tampa: "#1E5A3C", alca: "#1E5A3C", ouro: "#E5A62B", ouroE: "#B98318", ouroC: "#F7D27A", pinta: "#F7E6CC" },
  escuro: { fundo: "#17110D" },
  tingido: { fundo: null, bolsa: "#BFBFBF", tampa: "#8C8C8C", alca: "#8C8C8C", ouro: "#F2F2F2", ouroE: "#A6A6A6", ouroC: "#FFFFFF", pinta: "#FFFFFF" },
};
const cores = (nome) => ({ ...P.claro, ...P[nome] });
const ALCA_ICONE = "M-12 92 C40 122 216 122 268 92"; // sai pelas bordas do ícone
const ALCA_SIMBOLO = "M32 106 C70 117 186 117 224 106"; // trecho do mesmo arco, com ponta redonda (subir mais vira chifre)
const TAMPA = "M62 110 C62 94 74 82 90 82 H166 C182 82 194 94 194 110 C176 136 80 136 62 110 Z";
const PINTAS_X = [100, 128, 156];

const moedaIcone = (x, y, r, c) =>
  `<circle cx="${x}" cy="${y}" r="${r}" fill="${c.ouro}"/>` +
  `<circle cx="${x}" cy="${y}" r="${f(r * 0.64)}" fill="none" stroke="${c.ouroE}" stroke-width="${f(r * 0.16)}"/>` +
  `<circle cx="${f(x - r * 0.3)}" cy="${f(y - r * 0.32)}" r="${f(r * 0.16)}" fill="${c.ouroC}"/>`;

function pochete(c, { alca = ALCA_ICONE, pintas = true } = {}) {
  return [
    `<path d="${alca}" fill="none" stroke="${c.alca}" stroke-width="16" stroke-linecap="round"/>`,
    `<rect x="62" y="82" width="132" height="90" rx="26" fill="${c.bolsa}"/>`,
    `<path d="${TAMPA}" fill="${c.tampa}"/>`,
    moedaIcone(128, 125, 17, c),
    pintas ? PINTAS_X.map((x) => `<rect x="${x - 10}" y="151" width="20" height="9" rx="4.5" fill="${c.pinta}"/>`).join("") : "",
  ].join("");
}

const svg256 = (titulo, corpo) =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" role="img" aria-labelledby="t"><title id="t">${titulo}</title>${corpo}</svg>\n`;
const fundo = (cor, rx = 0) => (cor ? `<rect width="256" height="256"${rx ? ` rx="${rx}"` : ""} fill="${cor}"/>` : "");
const simbolo = () => pochete(cores("claro"), { alca: ALCA_SIMBOLO });
// O centro da bolsa fica em y 127, um pouco acima do centro do quadro (centro óptico).
const ampliada = (k, corpo) => `<g transform="translate(128 127) scale(${k}) translate(-128 -127)">${corpo}</g>`;
// Disco creme atrás da pochete. A bolsa verde e o Caramelo têm a mesma luminância (1,01:1): sem o disco,
// ela some em cinza e em 32 px. Só vale sobre o Caramelo; no fundo escuro a bolsa já passa de 3:1.
const disco = (r) => `<circle cx="128" cy="127" r="${r}" fill="${P.claro.pinta}"/>`;

// Monocromático (Android, ícone temático): só a forma; a tampa, a moeda e as pintas ficam vazadas.
function mono() {
  const m = `<mask id="m"><path d="${ALCA_ICONE}" fill="none" stroke="#fff" stroke-width="16"/>` +
    `<rect x="62" y="82" width="132" height="90" rx="26" fill="#fff"/>` +
    `<path d="M62 110 C80 136 176 136 194 110" fill="none" stroke="#000" stroke-width="5"/>` +
    `<circle cx="128" cy="125" r="20" fill="#000"/><circle cx="128" cy="125" r="15" fill="#fff"/><circle cx="128" cy="125" r="9" fill="#000"/>` +
    PINTAS_X.map((x) => `<rect x="${x - 10}" y="151" width="20" height="9" rx="4.5" fill="#000"/>`).join("") + `</mask>`;
  return `<defs>${m}</defs><rect width="256" height="256" fill="#000000" mask="url(#m)"/>`;
}

const ARQUIVOS = {
  "logo-cor.svg": logo("cor"),
  "logo-escuro.svg": logo("escuro"),
  "logo-mono.svg": logo("mono"),
  "logo-respiro.svg": logo("cor", { respiro: true }),
  "simbolo.svg": svg256("Símbolo do GranaPaCá", simbolo()),
  // Logo empilhado: símbolo em cima, letreiro embaixo, para espaços estreitos (o horizontal é muito largo).
  "logo-empilhado.svg": `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 70 ${L.largura} 232" role="img" aria-labelledby="t"><title id="t">GranaPaCá</title>` +
    `<g transform="translate(${f(L.largura / 2 - 112)} 14) scale(${f(224 / 256)})">${simbolo()}</g>` +
    `<g transform="translate(0 ${220 - TOPO})">${tracoLogo(LOGO.cor)}</g></svg>\n`,
  // iOS: quadro inteiro de 1024 px; o sistema aplica o recorte [Conferir: Apple HIG, App icons].
  // No iOS o quadro aparece inteiro e no Android só 2/3 dele: o Android usa a mesma composição em 2/3.
  "icone-ios-claro.svg": svg256("Ícone do GranaPaCá", fundo(P.claro.fundo) + disco(104) + ampliada(1.2, pochete(cores("claro")))),
  "icone-ios-escuro.svg": svg256("Ícone do GranaPaCá, aparência escura", fundo(P.escuro.fundo) + ampliada(1.2, pochete(cores("escuro")))),
  "icone-ios-tingido.svg": svg256("Ícone do GranaPaCá, aparência tingida", ampliada(1.2, pochete(cores("tingido")))),
  // Android adaptativo: camadas de 108 dp; o essencial fica no círculo seguro de 66 dp.
  "icone-android-fundo.svg": svg256("Fundo do ícone adaptativo", fundo(P.claro.fundo)),
  "icone-android-frente.svg": svg256("Frente do ícone adaptativo", disco(69) + ampliada(0.8, pochete(cores("claro")))),
  "icone-android-mono.svg": svg256("Ícone monocromático", mono()),
  // Favicon da demo web: sem as pintas, com disco e pochete maiores, para ler em 16 a 32 px.
  "favicon.svg": svg256("GranaPaCá", fundo(P.claro.fundo, 56) + disco(112) + ampliada(1.3, pochete(cores("claro"), { pintas: false }))),
};
const pasta = new URL("./", import.meta.url);
for (const [nome, conteudo] of Object.entries(ARQUIVOS)) writeFileSync(new URL(nome, pasta), conteudo);
console.log(`${Object.keys(ARQUIVOS).length} SVGs gravados em docs/design/logo`);
