// Gera os SVGs da Paçoca a partir das mesmas peças, para frente, perfil, costas e expressões
// ficarem consistentes. Uso: node docs/design/mascote/gerar-pacoca.mjs (grava os SVGs nesta pasta).
// Anatomia a partir de fotos de paca: corpo esguio, focinho alongado com nariz rosado, orelhas
// pequenas, bigodes longos e fileiras horizontais de pintas que viram traços no flanco.
import { writeFileSync } from "node:fs";

// Paleta: no máximo 3 tons por cor, sem contorno preto.
const C = {
  car: "#B96A35", carL: "#D99A66", carD: "#8E4A20",
  cre: "#F7E6CC", creD: "#E6C9A0",
  olho: "#2A1C12", nariz: "#5A2A0C", rosa: "#D9877A", rosaL: "#F0B0A6",
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
// Pinta em traço: cápsula creme; as fileiras alternam traços longos e curtos, como na paca.
const listra = ([x, y, w, a = 0]) => `<rect x="${x}" y="${y - 2.5}" width="${w}" height="5" rx="2.5" fill="${C.cre}"${a ? gira(a, x + w / 2, y) : ""}/>`;
const espelha = ([x, y, w, a = 0]) => [240 - x - w, y, w, -a];
const braco = ([x, y, a]) => ell(x, y, 8, 16, C.carD, gira(a, x, y));
const pegada = (x, y) => ell(x, y, 4.5, 5.5, C.carL) + circ(x - 4.5, y - 7, 2, C.carL) + circ(x, y - 9, 2, C.carL) + circ(x + 4.5, y - 7, 2, C.carL);
const fio = (d) => traco(d, C.nariz, 1.4, ' opacity="0.75"');
const bigodes = (x, y, lado) => [[-56, -12], [-60, 3], [-52, 18]].map(([dx, dy]) => fio(`M${x} ${y} Q${x + lado * dx * 0.5} ${y + dy * 0.4} ${x + lado * dx} ${y + dy}`)).join("");

// Frente: em pé, para os gestos. Cabeça com focinho alongado; os dentes saem da junção do lábio.
const OLHOS = {
  abertos: (r = 8) => [101, 139].map((x) => circ(x, 88, r, C.olho) + circ(x - 2.5, 85, r * 0.34, "#FFFFFF") + circ(x + 2.5, 91, 1.2, "#FFFFFF")).join(""),
  felizes: () => [101, 139].map((x) => traco(`M${x - 8} 91 Q${x} 82 ${x + 8} 91`, C.olho, 3.4)).join(""),
  fechados: () => [101, 139].map((x) => traco(`M${x - 8} 88 Q${x} 94 ${x + 8} 88`, C.olho, 3.4)).join(""),
  cima: () => [103, 141].map((x) => circ(x, 85, 8, C.olho) + circ(x - 2.5, 82, 2.7, "#FFFFFF")).join(""),
  lupa: () => circ(101, 88, 8, C.olho) + circ(98.5, 85, 2.7, "#FFFFFF") + circ(139, 88, 11, C.olho) + circ(135.5, 84, 3.7, "#FFFFFF") + circ(142.5, 91.5, 1.6, "#FFFFFF"),
};
const DENTES = `<rect x="116.5" y="120" width="7" height="7" rx="1.8" fill="#FFFFFF"/>` + traco("M120 120.5 V126.5", C.creD, 1);
const LABIO = {
  sorriso: "M108 117 Q113 125 120 120 Q127 125 132 117",
  reta: "M112 121 Q116 123 120 120 Q124 123 128 121",
  ondulada: "M110 123 Q115 119 120 120 Q125 119 130 123",
  pequena: "M114 120 Q117 122.5 120 120 Q123 122.5 126 120",
};
function boca(tipo) {
  const filtro = traco("M120 118.5 V120.5", C.nariz, 2.4);
  if (tipo === "aberta") return filtro + `<path d="M110 120 Q120 137 130 120 Z" fill="${C.nariz}"/>` + ell(120, 130, 5, 3, C.rosa) + DENTES;
  return filtro + traco(LABIO[tipo], C.nariz, 2.6) + (tipo === "pequena" ? "" : DENTES);
}
const LISTRAS_FRENTE = [[78, 134, 12], [74, 148, 14], [74, 162, 12], [88, 162, 4], [76, 176, 12], [81, 190, 8]];
const BRACOS_PADRAO = [[80, 160, -12], [160, 160, 12]];

function frente({ olhos = "abertos", bocaTipo = "sorriso", bracos = BRACOS_PADRAO, sobrancelhas = "", atras = "", meio = "", frenteExtra = "", olhoR } = {}) {
  return [
    atras,
    ell(106, 216, 14, 7, C.carD), ell(134, 216, 14, 7, C.carD),
    circ(90, 58, 9, C.carD), circ(90, 59, 4.5, C.creD), circ(150, 58, 9, C.carD), circ(150, 59, 4.5, C.creD),
    ell(120, 158, 50, 58, C.car),
    [...LISTRAS_FRENTE, ...LISTRAS_FRENTE.map(espelha)].map(listra).join(""),
    ell(120, 172, 26, 34, C.cre),
    traco("M72 172 Q120 192 168 172", C.mataD, 5),
    `<rect x="98" y="174" width="44" height="24" rx="10" fill="${C.mata}"/>`, traco("M101 182 Q120 188 139 182", C.mataD, 2.5), moeda(120, 186, 5.5),
    ell(120, 92, 48, 42, C.car), ell(120, 114, 24, 20, C.car),
    ell(120, 119, 18, 12, C.carL),
    ell(98, 108, 7, 4.5, C.rosa, ' opacity="0.45"'), ell(142, 108, 7, 4.5, C.rosa, ' opacity="0.45"'),
    OLHOS[olhos](olhoR), sobrancelhas,
    bigodes(106, 118, 1), bigodes(134, 118, -1),
    ell(120, 113, 8, 6, C.rosa), ell(118, 111.5, 2.4, 1.4, C.rosaL),
    boca(bocaTipo),
    meio,
    bracos.map(braco).join(""),
    frenteExtra,
  ].join("");
}

// Perfil: em quatro patas, como nas fotos. Corpo alongado, garupa alta e quatro fileiras de traços.
const LISTRAS_PERFIL = [
  [62, 124, 12], [78, 122, 9], [92, 122, 15], [111, 124, 10], [125, 127, 7],
  [50, 138, 9], [63, 137, 17], [84, 137, 11], [99, 138, 16], [119, 140, 10], [133, 142, 8],
  [54, 152, 12], [70, 152, 15], [89, 153, 9], [102, 153, 17], [123, 155, 11],
  [64, 166, 10], [78, 167, 14], [96, 168, 11], [111, 168, 9],
];
function perfil({ andando = false } = {}) {
  const [pt, pd] = andando ? [-16, 14] : [6, 0];
  return [
    andando ? pegada(16, 226) + pegada(32, 214) : "",
    ell(70, 190, 11, 18, C.carD, gira(pt, 70, 176)), ell(98, 194, 8, 15, C.carD, gira(-pt, 98, 182)),
    ell(80, 136, 46, 44, C.car), ell(114, 150, 74, 40, C.car),
    ell(118, 176, 50, 11, C.cre),
    LISTRAS_PERFIL.map(listra).join(""),
    traco("M124 112 Q134 146 126 186", C.mataD, 5), `<rect x="112" y="168" width="30" height="20" rx="8" fill="${C.mata}"/>`, moeda(127, 178, 4.5),
    ell(152, 194, 8, 16, C.carD, gira(pd, 152, 180)), ell(172, 194, 8, 15, C.carD, gira(-pd, 172, 181)),
    ell(andando ? 66 : 72, 211, 12, 5, C.carD), ell(100, 211, 10, 5, C.carD), ell(andando ? 162 : 156, 211, 11, 5, C.carD), ell(176, 211, 10, 5, C.carD),
    circ(164, 104, 8, C.carD), circ(164, 105, 4, C.creD),
    ell(178, 126, 32, 26, C.car, gira(12, 178, 126)), ell(204, 138, 18, 13, C.car), ell(211, 140, 12, 9, C.carL),
    circ(186, 120, 6, C.olho), circ(184, 118, 2, "#FFFFFF"),
    traco("M208 146 Q213 148 218 145", C.nariz, 2.2), `<rect x="211.5" y="146" width="4.5" height="5" rx="1.2" fill="#FFFFFF"/>`,
    ell(221, 138, 6, 5, C.rosa), ell(220, 136.5, 2, 1.3, C.rosaL),
    fio("M214 142 Q226 135 238 128"), fio("M214 144 Q227 144 240 146"), fio("M213 146 Q224 153 234 162"),
  ].join("");
}

function costas() {
  const LISTRAS = [[76, 132, 12], [72, 146, 16], [72, 160, 14], [74, 174, 12], [80, 188, 8], [92, 140, 6], [92, 168, 5]];
  return [
    braco([74, 160, -12]), braco([166, 160, 12]),
    ell(106, 216, 14, 7, C.carD), ell(134, 216, 14, 7, C.carD),
    circ(90, 58, 9, C.carD), circ(150, 58, 9, C.carD),
    ell(120, 158, 50, 58, C.car),
    [...LISTRAS, ...LISTRAS.map(espelha)].map(listra).join(""),
    traco("M72 172 Q120 192 168 172", C.mataD, 5),
    ell(120, 92, 48, 42, C.car),
  ].join("");
}

const zz = traco("M174 40 h14 l-14 16 h14", C.metal, 3.5) + traco("M198 20 h10 l-10 12 h10", C.metal, 3);
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
    frente({ bracos: [[80, 160, -12], [170, 106, 30]], frenteExtra: traco("M186 78 Q194 87 190 98", C.carL, 3) + traco("M195 70 Q206 83 200 98", C.carL, 3) })],
  ["comemorando", "Comemorando", "Meta batida, mês com sobra", 2,
    frente({ olhos: "felizes", bocaTipo: "aberta", bracos: [[74, 104, -28], [166, 104, 28]], atras: moeda(56, 44, 9) + moeda(120, 20, 10) + moeda(186, 46, 9) + moeda(28, 84, 6) + moeda(214, 86, 6) })],
  ["pensando", "Pensando", "IA processando, chat digitando", 3,
    frente({ olhos: "cima", bocaTipo: "reta", bracos: [[80, 160, -12], [140, 142, -40]], atras: moeda(172, 48, 5, C.carL, C.car, null) + moeda(188, 33, 7, C.carL, C.car, null) + moeda(207, 17, 9, C.carL, C.car, null) })],
  ["lupa", "Com lupa", "Lendo nota fiscal ou comprovante", 4,
    frente({ olhos: "lupa", bracos: [[80, 160, -12]], meio: circ(139, 88, 19, C.agua, ' opacity="0.35"') + `<circle cx="139" cy="88" r="19" fill="none" stroke="${C.metal}" stroke-width="5.5"/>` + traco("M127 78 Q132 72 139 71", "#FFFFFF", 3, ' opacity="0.8"') + traco("M152 102 L172 126", C.metal, 7), frenteExtra: braco([174, 132, 25]) })],
  ["dormindo", "Dormindo", "Sem internet, sincronização pendente", 5,
    frente({ olhos: "fechados", bocaTipo: "pequena", bracos: [[84, 166, -10], [156, 166, 10]], frenteExtra: zz })],
  ["mergulhando", "Mergulhando", "Atualizando os dados ao puxar a tela", 6,
    frente({ olhos: "felizes", bracos: [[62, 146, 62], [178, 146, -62]], frenteExtra: agua })],
  ["preocupada", "Preocupada", "Alertas e conexão vencendo", 7,
    frente({ olhoR: 7, bocaTipo: "ondulada", sobrancelhas: traco("M90 76 L106 70", C.carD, 3.5) + traco("M134 70 L150 76", C.carD, 3.5), bracos: [[88, 118, 22], [160, 160, 12]] })],
  ["cadeado", "Segurando um cadeado", "Telas de privacidade e segurança", 8,
    frente({ bracos: [[100, 168, 38], [140, 168, -38]], meio: traco("M108 150 v-11 a12 12 0 0 1 24 0 v11", C.metal, 5.5) + `<rect x="100" y="146" width="40" height="34" rx="8" fill="${C.milho}"/>` + circ(120, 159, 4.5, C.metal) + `<rect x="117.75" y="160" width="4.5" height="9" rx="2" fill="${C.metal}"/>` })],
  ["andando", "Andando", "Trilha do primeiro acesso", 9, perfil({ andando: true })],
];

const svg = (titulo, corpo) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 240 240" role="img" aria-labelledby="t"><title id="t">Paçoca: ${titulo}</title>${corpo}</svg>\n`;
const pasta = new URL("./", import.meta.url);
for (const [arquivo, nome, , , corpo] of [...VISTAS, ...EXPRESSOES]) writeFileSync(new URL(`${arquivo}.svg`, pasta), svg(nome.toLowerCase(), corpo));
console.log(`${VISTAS.length + EXPRESSOES.length} SVGs gravados em docs/design/mascote`);
export { C };
