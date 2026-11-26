// Confere o contraste do ícone de cada categoria dentro do círculo de 14% da própria cor, nos dois temas.
// Uso: node docs/design/tokens/check-categorias.mjs   (só informa; sai com código 0, quem decide é a Parte 11)
// Lê só o tokens.json. O círculo é a cor do grupo a 14% sobre a Superfície (surfaceContainerLow), como nas telas.
import { readFileSync } from "node:fs";

const t = JSON.parse(readFileSync(new URL("./tokens.json", import.meta.url), "utf8"));
const rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const hex = (v) => `#${v.map((x) => Math.round(x).toString(16).padStart(2, "0")).join("").toUpperCase()}`;
const lin = (v) => v.map((x) => { const c = x / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
const lum = (h) => { const [r, g, b] = lin(rgb(h)); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
// Mistura "de" sobre "base" com opacidade op (0 a 1).
const mistura = (de, base, op) => hex(rgb(base).map((x, i) => x * (1 - op) + rgb(de)[i] * op));
const OPACIDADE = 0.14, MINIMO = 3;

let abaixo = 0;
for (const tema of ["claro", "escuro"]) {
  const e = t.cor.esquema[tema];
  console.log(`\n${tema} (círculo = cor a ${Math.round(OPACIDADE * 100)}% sobre ${e.surfaceContainerLow}, mínimo ${MINIMO}:1 para ícone)`);
  console.log("categoria".padEnd(24) + "cor".padEnd(9) + "círculo".padEnd(9) + "no círculo".padEnd(12) + "na superfície".padEnd(15) + "situação");
  for (const k of t.cor.categorias) {
    const cor = t.cor.grafico[tema][k.cor];
    const circulo = mistura(cor, e.surfaceContainerLow, OPACIDADE);
    const rc = ratio(cor, circulo), rs = ratio(cor, e.surfaceContainerLow);
    let nota = "ok";
    if (rc < MINIMO) {
      abaixo++;
      // Sugestão: aproxima a cor do texto (onSurface) em passos de 5% até chegar ao mínimo no círculo.
      let p = 0, tom = cor;
      while (p < 1 && ratio(tom, circulo) < MINIMO) { p += 0.05; tom = mistura(e.onSurface, cor, p); }
      nota = `abaixo; ícone sugerido ${tom} (${ratio(tom, circulo).toFixed(2)}:1)`;
    }
    console.log(k.nome.padEnd(24) + cor.padEnd(9) + circulo.padEnd(9) + `${rc.toFixed(2)}:1`.padEnd(12) + `${rs.toFixed(2)}:1`.padEnd(15) + nota);
  }
}
console.log(abaixo ? `\n${abaixo} ícone(s) abaixo de ${MINIMO}:1 dentro do círculo` : "\nTodos os ícones passam dentro do círculo.");
