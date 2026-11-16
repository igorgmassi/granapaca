// Pose neutra separada em partes, com uma animação de exemplo (respirar, inclinar a cabeça, piscar).
// Lê ./pacoca-01-frente.png e grava ./pacoca-01-frente-partes.svg. Sem dependências.
// Uso: node docs/design/mascote/ilustrada/partes.mjs
import { readFileSync, writeFileSync } from "node:fs";

const aqui = new URL(".", import.meta.url);
const png = readFileSync(new URL("pacoca-01-frente.png", aqui)).toString("base64");
const L = 215, A = 308;                // tamanho do recorte
const PIVO = [108, 130];               // pescoço: onde a cabeça gira
const CARAMELO = "#D98042", MARROM = "#402009";
// Linha do queixo, da esquerda para a direita. Acima dela é cabeça; abaixo, corpo.
const QUEIXO = [[0, 118], [58, 122], [68, 130], [90, 135], [108, 136], [125, 135], [150, 130], [160, 122], [L, 118]];
const pts = (p) => p.map(([x, y]) => `${x},${y}`).join(" ");
const cabeca = pts([[0, 0], ...QUEIXO, [L, 0]]);
// O corpo sobe 6 px por baixo da cabeça, para a junta não abrir quando ela gira.
const corpo = pts([[0, A], ...QUEIXO.map(([x, y]) => [x, y - 6]), [L, A]]);
const olhos = [[71, 62], [144, 62]];   // centro de cada olho

const svg = `<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" viewBox="-12 -12 ${L + 24} ${A + 24}" role="img" aria-labelledby="t">
<title id="t">Paçoca de frente, em partes: respira, inclina a cabeça e pisca</title>
<style>
.corpo { transform-origin: 108px 300px; animation: respira 3.6s ease-in-out infinite; }
.cabeca { transform-origin: ${PIVO[0]}px ${PIVO[1]}px; animation: inclina 7.2s ease-in-out infinite; }
.palpebra { transform-box: fill-box; transform-origin: 50% 0; transform: scaleY(0); animation: pisca 4.8s linear infinite; }
.risco { opacity: 0; animation: risco 4.8s linear infinite; }
@keyframes respira { 50% { transform: scaleY(1.012); } }
@keyframes inclina { 0%, 100% { transform: translateY(0) rotate(0deg); } 25% { transform: translateY(-1.2px) rotate(-2.2deg); } 75% { transform: translateY(-1.2px) rotate(2.2deg); } }
@keyframes pisca { 0%, 93%, 100% { transform: scaleY(0); } 96% { transform: scaleY(1); } }
@keyframes risco { 0%, 94.5%, 97.5%, 100% { opacity: 0; } 96% { opacity: 1; } }
@media (prefers-reduced-motion: reduce) { .corpo, .cabeca, .palpebra, .risco { animation: none; } }
</style>
<defs>
<image id="arte" width="${L}" height="${A}" xlink:href="data:image/png;base64,${png}"/>
<clipPath id="so-cabeca"><polygon points="${cabeca}"/></clipPath>
<clipPath id="so-corpo"><polygon points="${corpo}"/></clipPath>
</defs>
<g class="corpo" id="corpo">
<ellipse cx="${PIVO[0]}" cy="${PIVO[1] - 4}" rx="46" ry="14" fill="${CARAMELO}"/>
<use xlink:href="#arte" clip-path="url(#so-corpo)"/>
</g>
<g class="cabeca" id="cabeca">
<use xlink:href="#arte" clip-path="url(#so-cabeca)"/>
${olhos.map(([x, y], k) => `<g id="olho-${k ? "direito" : "esquerdo"}"><ellipse class="palpebra" cx="${x}" cy="${y}" rx="15.5" ry="19.5" fill="${CARAMELO}"/><path class="risco" d="M${x - 12} ${y + 5} Q${x} ${y + 13} ${x + 12} ${y + 5}" fill="none" stroke="${MARROM}" stroke-width="2.4" stroke-linecap="round"/></g>`).join("\n")}
</g>
</svg>
`;
writeFileSync(new URL("pacoca-01-frente-partes.svg", aqui), svg);
console.log(`pacoca-01-frente-partes.svg gravado (${(svg.length / 1024).toFixed(0)} KB)`);
