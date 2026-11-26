// Troca o <text> do letreiro "Grana PaCá" por contornos <path>, para o logo não depender da fonte instalada.
// Uso: node docs/design/logo/vetorizar-letreiro.mjs --fonte <arquivo.ttf|otf|woff> [--entrada docs/design/logo/logo-cor.svg] [--saida arquivo.svg]
// Sem --saida, escreve o SVG na saída padrão. Nunca sobrescreve a --entrada.
// Dependência fora do Git: npm install --no-save --prefix docs/design opentype.js
// Fonte: a Plus Jakarta Sans Bold (OFL) que será empacotada no app. Não há .ttf no repositório ainda (Parte 12).
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { createRequire } from "node:module";

const arg = (nome, padrao) => { const i = process.argv.indexOf(`--${nome}`); return i > 0 ? process.argv[i + 1] : padrao; };
const fontePath = arg("fonte"), entrada = arg("entrada", new URL("./logo-cor.svg", import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, "$1")), saida = arg("saida");
if (!fontePath) { console.error("Faltou --fonte <arquivo.ttf|otf|woff>."); process.exit(2); }
if (saida && resolve(saida) === resolve(entrada)) { console.error("A --saida não pode ser a --entrada."); process.exit(2); }

let opentype;
try { opentype = createRequire(import.meta.url)("opentype.js"); } catch {
  try { opentype = (await import(new URL("../node_modules/opentype.js/dist/opentype.mjs", import.meta.url))).default; } catch {
    console.error("Instale a dependência: npm install --no-save --prefix docs/design opentype.js"); process.exit(2);
  }
}
const lib = opentype.parse ? opentype : opentype.default;
const dados = readFileSync(fontePath);
const fonte = lib.parse(dados.buffer.slice(dados.byteOffset, dados.byteOffset + dados.byteLength));

const svg = readFileSync(entrada, "utf8");
const m = svg.match(/<text x="([\d.]+)" y="([\d.]+)" textLength="([\d.]+)"[^>]*font-size="([\d.]+)"[^>]*letter-spacing="(-?[\d.]+)"[^>]*>(.*?)<\/text>/);
if (!m) { console.error("O SVG de entrada não tem o <text> do letreiro (talvez já esteja vetorizado)."); process.exit(1); }
const [, x0, y0, largura, tamanho, espaco, miolo] = m.map((v, i) => (i >= 1 && i <= 5 ? Number(v) : v));
const trechos = [...miolo.matchAll(/<tspan fill="([^"]+)">(.*?)<\/tspan>/g)].map(([, cor, texto]) => ({ cor, texto }));

// O layout é feito glifo a glifo (avanço + kerning + espaçamento), sem o processamento de ligaduras do opentype.js,
// que não suporta todos os lookups GSUB da fonte (substFormat 2). Para este letreiro (Latin básico) o resultado é o mesmo.
const escala = tamanho / fonte.unitsPerEm;
const kern = (a, b) => { try { return fonte.getKerningValue(a, b) || 0; } catch { return 0; } };
function gliphos(texto, ls) {
  const lista = [...texto].map((ch) => fonte.charToGlyph(ch));
  let x = 0;
  return lista.map((g, i) => { const pos = x; x += g.advanceWidth * escala + (i < lista.length - 1 ? kern(g, lista[i + 1]) * escala : 0) + ls; return { g, x: pos }; });
}
// textLength com lengthAdjust="spacing" reparte a diferença entre os caracteres; faz o mesmo aqui.
const completo = trechos.map((t) => t.texto).join("");
const ult = gliphos(completo, espaco).at(-1);
const natural = ult.x + ult.g.advanceWidth * escala;
const ls = espaco + (largura - natural) / completo.length;
const todos = gliphos(completo, ls);

let indice = 0, paths = "";
for (const { cor, texto } of trechos) {
  const fatia = todos.slice(indice, indice + [...texto].length);
  indice += fatia.length;
  const d = fatia.map(({ g, x }) => g.getPath(x0 + x, y0, tamanho).toPathData(2)).join("");
  paths += `<path d="${d}" fill="${cor}"/>`;
}const novo = svg.replace(m[0], `<g aria-hidden="true">${paths}</g>`);
if (saida) { writeFileSync(saida, novo); console.error(`Gravado em ${saida} (${paths.length} caracteres de contorno).`); } else process.stdout.write(novo);
