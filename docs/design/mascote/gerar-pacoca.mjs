// Gera os SVGs da Paçoca a partir das mesmas peças, para frente, perfil, costas e expressões
// ficarem consistentes. Uso: node docs/design/mascote/gerar-pacoca.mjs (grava os SVGs nesta pasta).
import { writeFileSync } from "node:fs";

// Paleta da Paçoca: no máximo 3 tons por cor, sem contorno preto.
const C = {
  car: "#C47A3A", carL: "#DFA36B", carD: "#9A5524",
  cre: "#F7E6CC", creD: "#E6C9A0",
  olho: "#2A1C12", nariz: "#5A2A0C", narizL: "#8A4A22", boch: "#EE9C92",
  mata: "#2A7550", mataD: "#1E5A3C",
  milho: "#E5A62B", milhoD: "#B98318", milhoL: "#F7D27A",
  agua: "#7DB9EA", aguaD: "#22649C", metal: "#6B5546",
};

const ell = (cx, cy, rx, ry, fill, extra = "") => `<ellipse cx="${cx}" cy="${cy}" rx="${rx}" ry="${ry}" fill="${fill}"${extra}/>`;
const circ = (cx, cy, r, fill, extra = "") => `<circle cx="${cx}" cy="${cy}" r="${r}" fill="${fill}"${extra}/>`;
const traco = (d, cor, largura, extra = "") => `<path d="${d}" fill="none" stroke="${cor}" stroke-width="${largura}" stroke-linecap="round" stroke-linejoin="round"${extra}/>`;
const gira = (a, x, y) => ` transform="rotate(${a} ${x} ${y})"`;
const moeda = (x, y, r, base = C.milho, anel = C.milhoD, brilho = C.milhoL) =>
  circ(x, y, r, base) + `<circle cx="${x}" cy="${y}" r="${(r * 0.62).toFixed(1)}" fill="none" stroke="${anel}" stroke-width="${(r * 0.2).toFixed(1)}"/>` +
  (brilho ? circ((x - r * 0.3).toFixed(1), (y - r * 0.32).toFixed(1), (r * 0.2).toFixed(1), brilho) : "");
const pinta = (x, y, r) => moeda(x, y, r, C.cre, C.creD, null); // as pintas são moedinhas creme
const braco = ([x, y, a]) => ell(x, y, 12, 18, C.carD, gira(a, x, y));
const pegada = (x, y) => ell(x, y, 5, 6, C.carL) + circ(x - 5, y - 8, 2.2, C.carL) + circ(x, y - 10, 2.2, C.carL) + circ(x + 5, y - 8, 2.2, C.carL);

const OLHOS = {
  abertos: (r = 9.5) => [100, 140].map((x) => circ(x, 86, r, C.olho) + circ(x - 3, 82.5, r * 0.34, "#FFFFFF") + circ(x + 3, 89.5, 1.4, "#FFFFFF")).join(""),
  felizes: () => [100, 140].map((x) => traco(`M${x - 9} 89 Q${x} 79 ${x + 9} 89`, C.olho, 3.6)).join(""),
  fechados: () => [100, 140].map((x) => traco(`M${x - 9} 86 Q${x} 93 ${x + 9} 86`, C.olho, 3.6)).join(""),
  cima: () => [102, 142].map((x) => circ(x, 83, 9.5, C.olho) + circ(x - 3, 79.5, 3.2, "#FFFFFF")).join(""),
  lupa: () => circ(100, 86, 9.5, C.olho) + circ(97, 82.5, 3.2, "#FFFFFF") + circ(142, 86, 13, C.olho) + circ(138, 81, 4.4, "#FFFFFF") + circ(146, 90, 1.8, "#FFFFFF"),
};
const BOCAS = {
  sorriso: traco("M120 107 V112", C.nariz, 3) + traco("M109 112 Q120 121 131 112", C.nariz, 3),
  aberta: traco("M120 107 V112", C.nariz, 3) + `<path d="M108 112 Q120 129 132 112 Z" fill="${C.nariz}"/>` + ell(120, 120, 6, 3.5, C.boch),
  reta: traco("M120 107 V112", C.nariz, 3) + traco("M113 115 L127 114", C.nariz, 3),
  ondulada: traco("M110 116 Q115 112 120 116 Q125 120 130 116", C.nariz, 3),
  pequena: traco("M116 114 Q120 117 124 114", C.nariz, 3),
};

const DENTES = `<rect x="115.5" y="111" width="9" height="8" rx="2" fill="#FFFFFF"/>` + traco("M120 111.5 V118.5", C.creD, 1.2);
const BIGODE = [[101, 106], [98, 112], [104, 114], [139, 106], [142, 112], [136, 114]].map(([x, y]) => circ(x, y, 1.6, C.creD)).join("");
const BRACOS_PADRAO = [[84, 160, -28], [156, 160, 28]];

function frente({ olhos = "abertos", boca = "sorriso", bracos = BRACOS_PADRAO, sobrancelhas = "", atras = "", meio = "", frenteExtra = "", olhoR } = {}) {
  return [
    atras,
    ell(97, 213, 21, 10, C.carD), ell(143, 213, 21, 10, C.carD),
    circ(78, 56, 10, C.carD), circ(78, 57, 5, C.creD), circ(162, 56, 10, C.carD), circ(162, 57, 5, C.creD),
    ell(120, 156, 68, 63, C.car),
    pinta(64, 138, 7), pinta(62, 158, 7.5), pinta(66, 178, 7), pinta(176, 138, 7), pinta(178, 158, 7.5), pinta(174, 178, 7),
    ell(120, 170, 38, 33, C.cre),
    traco("M54 172 Q120 196 186 172", C.mataD, 6),
    `<rect x="93" y="174" width="54" height="27" rx="11" fill="${C.mata}"/>`, traco("M96 183 Q120 190 144 183", C.mataD, 3), moeda(120, 187, 6),
    ell(120, 92, 60, 50, C.car),
    ell(120, 111, 31, 22, C.cre),
    ell(84, 106, 9, 5.5, C.boch, ' opacity="0.75"'), ell(156, 106, 9, 5.5, C.boch, ' opacity="0.75"'),
    OLHOS[olhos](olhoR), sobrancelhas,
    ell(120, 101, 9, 6.5, C.nariz), ell(117, 99.5, 2.6, 1.6, C.narizL),
    BOCAS[boca],
    boca === "pequena" ? "" : DENTES,
    BIGODE,
    meio,
    bracos.map(braco).join(""),
    frenteExtra,
  ].join("");
}

function perfil({ andando = false } = {}) {
  const pes = andando
    ? ell(86, 211, 22, 10, C.carD, gira(-14, 86, 211)) + ell(156, 208, 22, 10, C.carD, gira(16, 156, 208))
    : ell(96, 213, 22, 10, C.carD) + ell(142, 213, 22, 10, C.carD);
  return [
    andando ? pegada(28, 224) + pegada(50, 206) : "",
    ell(56, 172, 8, 6, C.carD), pes,
    circ(108, 58, 10, C.carD), circ(109, 59, 5, C.creD),
    ell(112, 155, 60, 62, C.car),
    [[70, 136, 6.5], [88, 134, 6.5], [106, 134, 6.5], [64, 158, 7], [82, 157, 7], [100, 157, 7], [72, 180, 6], [90, 180, 6], [108, 181, 6]].map(([x, y, r]) => pinta(x, y, r)).join(""),
    ell(146, 170, 24, 34, C.cre),
    traco("M66 166 Q110 192 160 168", C.mataD, 6), `<rect x="132" y="170" width="36" height="26" rx="10" fill="${C.mata}"/>`, moeda(150, 183, 5.5),
    ell(140, 94, 54, 46, C.car),
    ell(180, 106, 24, 19, C.cre),
    ell(162, 110, 9, 5.5, C.boch, ' opacity="0.75"'),
    circ(156, 84, 9, C.olho), circ(153, 80.5, 3, "#FFFFFF"), circ(158.5, 87.5, 1.3, "#FFFFFF"),
    ell(201, 99, 7, 5.5, C.nariz), ell(199, 97.5, 2.2, 1.4, C.narizL),
    traco("M182 115 Q190 120 197 113", C.nariz, 3), `<rect x="192" y="106" width="6" height="8" rx="2" fill="#FFFFFF"/>`,
    braco(andando ? [160, 144, -30] : [150, 150, 20]),
  ].join("");
}

function costas() {
  return [
    braco([60, 160, -18]), braco([180, 160, 18]),
    ell(97, 213, 21, 10, C.carD), ell(143, 213, 21, 10, C.carD),
    circ(78, 56, 10, C.carD), circ(162, 56, 10, C.carD),
    ell(120, 156, 68, 63, C.car),
    [[62, 140, 7], [60, 160, 7], [66, 180, 6.5], [84, 128, 6], [80, 150, 6], [84, 172, 6]].flatMap(([x, y, r]) => [pinta(x, y, r), pinta(240 - x, y, r)]).join(""),
    traco("M54 172 Q120 196 186 172", C.mataD, 6),
    ell(120, 200, 7, 6, C.carD),
    ell(120, 92, 60, 50, C.car),
  ].join("");
}

const zz = traco("M182 34 h14 l-14 16 h14", C.metal, 3.5) + traco("M206 14 h10 l-10 12 h10", C.metal, 3);
const agua = `<path d="M0 152 Q30 142 60 152 T120 152 T180 152 T240 152 V240 H0 Z" fill="${C.agua}" opacity="0.6"/>` +
  traco("M0 152 Q30 142 60 152 T120 152 T180 152 T240 152", C.aguaD, 3) +
  [[40, 124, 5], [28, 104, 3.5], [206, 116, 4.5], [214, 98, 3]].map(([x, y, r]) => `<circle cx="${x}" cy="${y}" r="${r}" fill="none" stroke="${C.aguaD}" stroke-width="2"/>`).join("");

// [arquivo, nome, quando aparece, estado no Rive, desenho]
export const VISTAS = [
  ["frente", "Frente", "Folha de modelo", "—", frente()],
  ["perfil", "Perfil", "Folha de modelo e ícone do app", "—", perfil()],
  ["costas", "Costas", "Folha de modelo", "—", costas()],
];
export const EXPRESSOES = [
  ["acenando", "Acenando", "Boas-vindas e guia inicial", 1,
    frente({ bracos: [[84, 160, -28], [176, 104, 32]], frenteExtra: traco("M193 76 Q201 85 197 96", C.carL, 3) + traco("M202 68 Q213 81 207 96", C.carL, 3) })],
  ["comemorando", "Comemorando", "Meta batida, mês com sobra", 2,
    frente({ olhos: "felizes", boca: "aberta", bracos: [[66, 100, -30], [174, 100, 30]], atras: moeda(56, 44, 9) + moeda(120, 20, 10) + moeda(186, 46, 9) + moeda(28, 84, 6) + moeda(214, 86, 6) })],
  ["pensando", "Pensando", "IA processando, chat digitando", 3,
    frente({ olhos: "cima", boca: "reta", bracos: [[84, 160, -28], [142, 136, -40]], atras: moeda(176, 46, 5, C.carL, C.car, null) + moeda(193, 31, 7, C.carL, C.car, null) + moeda(213, 15, 9, C.carL, C.car, null) })],
  ["lupa", "Com lupa", "Lendo nota fiscal ou comprovante", 4,
    frente({ olhos: "lupa", bracos: [[84, 160, -28]], meio: circ(142, 86, 21, C.agua, ' opacity="0.35"') + `<circle cx="142" cy="86" r="21" fill="none" stroke="${C.metal}" stroke-width="6"/>` + traco("M129 75 Q134 69 142 68", "#FFFFFF", 3, ' opacity="0.8"') + traco("M157 101 L180 126", C.metal, 8), frenteExtra: braco([182, 132, 25]) })],
  ["dormindo", "Dormindo", "Sem internet, sincronização pendente", 5,
    frente({ olhos: "fechados", boca: "pequena", bracos: [[86, 166, -20], [154, 166, 20]], frenteExtra: zz })],
  ["mergulhando", "Mergulhando", "Atualizando os dados ao puxar a tela", 6,
    frente({ olhos: "felizes", bracos: [[50, 146, 62], [190, 146, -62]], frenteExtra: agua })],
  ["preocupada", "Preocupada", "Alertas e conexão vencendo", 7,
    frente({ olhoR: 8.5, boca: "ondulada", sobrancelhas: traco("M88 74 L107 66", C.carD, 4) + traco("M133 66 L152 74", C.carD, 4), bracos: [[78, 122, 25], [156, 160, 28]] })],
  ["cadeado", "Segurando um cadeado", "Telas de privacidade e segurança", 8,
    frente({ bracos: [[96, 170, 40], [144, 170, -40]], meio: traco("M107 152 v-12 a13 13 0 0 1 26 0 v12", C.metal, 6) + `<rect x="98" y="148" width="44" height="36" rx="9" fill="${C.milho}"/>` + circ(120, 162, 5, C.metal) + `<rect x="117.5" y="163" width="5" height="10" rx="2" fill="${C.metal}"/>` })],
  ["andando", "Andando", "Trilha do primeiro acesso", 9, perfil({ andando: true })],
];

const svg = (titulo, corpo) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" role="img" aria-labelledby="t"><title id="t">Paçoca: ${titulo}</title>${corpo}</svg>\n`;
const pasta = new URL("./", import.meta.url);
for (const [arquivo, nome, , , corpo] of [...VISTAS, ...EXPRESSOES]) writeFileSync(new URL(`${arquivo}.svg`, pasta), svg(nome.toLowerCase(), corpo));
console.log(`${VISTAS.length + EXPRESSOES.length} SVGs gravados em docs/design/mascote`);
export { C };
