// Confere o contraste WCAG 2.x dos pares de cor de tokens.json, nos dois temas.
// Uso: node docs/design/tokens/check-contrast.mjs   (sai com código 1 se algum par falhar)
import { readFileSync } from "node:fs";

const t = JSON.parse(readFileSync(new URL("./tokens.json", import.meta.url), "utf8"));
const lin = (h) => [1, 3, 5].map((i) => {
  const c = parseInt(h.slice(i, i + 2), 16) / 255;
  return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4;
});
const lum = (h) => { const [r, g, b] = lin(h); return 0.2126 * r + 0.7152 * g + 0.0722 * b; };
const ratio = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };

// [frente, fundo, mínimo]: 4.5 para texto, 3 para borda, ícone e marcador.
const PARES = [
  ["onPrimary", "primary", 4.5], ["onPrimaryContainer", "primaryContainer", 4.5],
  ["onSecondary", "secondary", 4.5], ["onSecondaryContainer", "secondaryContainer", 4.5],
  ["onTertiary", "tertiary", 4.5], ["onTertiaryContainer", "tertiaryContainer", 4.5],
  ["onError", "error", 4.5], ["onErrorContainer", "errorContainer", 4.5],
  ["onInverseSurface", "inverseSurface", 4.5],
  ...["surface", "surfaceContainerLow", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest"].flatMap((f) => [
    ["onSurface", f, 4.5], ["onSurfaceVariant", f, 4.5], ["primary", f, 4.5], ["error", f, 4.5], ["tertiary", f, 4.5],
    ["mata", f, 4.5], ["rio", f, 4.5], ["outline", f, 3],
  ]),
  ["sobreMilho", "milho", 4.5],
  ["essencial", "surfaceContainerLow", 3], ["importante", "surfaceContainerLow", 3], ["flexivel", "surfaceContainerLow", 3],
];

let falhas = 0;
for (const tema of ["claro", "escuro"]) {
  const cor = { ...t.cor.esquema[tema], ...t.cor.marca[tema] };
  for (const [frente, fundo, min] of PARES) {
    const r = ratio(cor[frente], cor[fundo]);
    if (r < min) { falhas++; console.log(`FALHA ${tema}: ${frente} ${cor[frente]} sobre ${fundo} ${cor[fundo]} = ${r.toFixed(2)}:1 (mín ${min})`); }
  }
  // Cores de gráfico abaixo de 3:1 só valem com rótulo visível: lista para conferência.
  const fundo = cor.surfaceContainerLow;
  const baixas = Object.entries(t.cor.grafico[tema]).filter(([, h]) => ratio(h, fundo) < 3).map(([n, h]) => `${n} ${ratio(h, fundo).toFixed(2)}:1`);
  console.log(`${tema}: ${PARES.length} pares conferidos; gráfico com rótulo obrigatório: ${baixas.join(", ") || "nenhuma"}`);
}
console.log(falhas ? `${falhas} par(es) abaixo do mínimo` : "Todos os pares passam.");
process.exit(falhas ? 1 : 0);
