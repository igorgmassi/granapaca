// Gera logo, símbolo e ícones do GranaPaCá em SVG. Uso: node docs/design/logo/gerar-logo.mjs
// O logo vem de contornos prontos (letreiro.json); o símbolo e os ícones são desenhados aqui.
import { readFileSync, writeFileSync } from "node:fs";

const f = (n) => +n.toFixed(1);

// ---------- Logo ----------
// Letreiro serifado "Grana PaCá" com a paca deitada sobre "aC" e o acento em forma de pinta.
// Os contornos ficam em letreiro.json (traçados da arte aprovada); aqui só entram as cores.
// A pochete é o ícone do app e NUNCA entra no logo.
const LT = JSON.parse(readFileSync(new URL("./letreiro.json", import.meta.url), "utf8"));
const LOGO = {
  cor: { grana: "#2A7550", paca: "#A0521A", bicho: "#B96A35", acento: "#2A7550" },
  escuro: { grana: "#6CC596", paca: "#E8A066", bicho: "#D99A66", acento: "#6CC596", fundo: "#17110D" },
  mono: { grana: "currentColor", paca: "currentColor", bicho: "currentColor", acento: "currentColor" },
};
function logo(nome, { respiro = false } = {}) {
  const c = LOGO[nome], [x0, y0, x1, y1] = LT.caixa;
  const m = respiro ? LT.alturaDoA : 50; // área de respiro = altura do "a" minúsculo
  const vb = [x0 - m, y0 - m, x1 - x0 + 2 * m, y1 - y0 + 2 * m];
  const fundo = respiro ? "#FBF5EC" : c.fundo;
  const guia = respiro
    ? `<rect x="${x0}" y="${y0}" width="${x1 - x0}" height="${y1 - y0}" fill="none" stroke="#94816E" stroke-width="8" stroke-dasharray="40 30"/>` +
      `<rect x="${vb[0] + 10}" y="${vb[1] + 10}" width="${vb[2] - 20}" height="${vb[3] - 20}" fill="none" stroke="#B83A22" stroke-width="12" stroke-dasharray="60 40"/>`
    : "";
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb.join(" ")}" role="img" aria-labelledby="t"><title id="t">Grana PaCá</title>` +
    (fundo ? `<rect x="${vb[0]}" y="${vb[1]}" width="${vb[2]}" height="${vb[3]}" fill="${fundo}"/>` : "") + guia +
    ["grana", "paca", "bicho", "acento"].map((n) => `<path d="${LT[n]}" fill="${c[n]}" fill-rule="evenodd"/>`).join("") + `</svg>
`;
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
