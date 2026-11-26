// Mede a distância entre as cores de categoria e entre os níveis de essencialidade para visão normal e para daltonismo.
// Uso: node docs/design/tokens/check-daltonismo.mjs   (só informa; quem decide é a Parte 11)
// Distância = diferença euclidiana no OKLab, multiplicada por 100. Simulação: Machado et al. (2009), severidade 1,0, em RGB linear.
import { readFileSync } from "node:fs";

const t = JSON.parse(readFileSync(new URL("./tokens.json", import.meta.url), "utf8"));
const lin = (h) => [1, 3, 5].map((i) => { const c = parseInt(h.slice(i, i + 2), 16) / 255; return c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4; });
const MATRIZES = {
  "visão normal": [[1, 0, 0], [0, 1, 0], [0, 0, 1]],
  protanopia: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
  deuteranopia: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.01182, 0.04294, 0.968881]],
  tritanopia: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.3039]],
};
const cl = (x) => Math.min(1, Math.max(0, x));
const oklab = ([r, g, b]) => {
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  return [0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s, 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s, 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s];
};
const simula = (h, M) => { const v = lin(h); return oklab(M.map((linha) => cl(linha[0] * v[0] + linha[1] * v[1] + linha[2] * v[2]))); };
const dist = (a, b) => 100 * Math.hypot(a[0] - b[0], a[1] - b[1], a[2] - b[2]);

function menorPar(rotulos, cores, M) {
  let pior = { d: Infinity };
  for (let i = 0; i < cores.length; i++) for (let j = i + 1; j < cores.length; j++) {
    const d = dist(simula(cores[i], M), simula(cores[j], M));
    if (d < pior.d) pior = { d, a: rotulos[i], b: rotulos[j] };
  }
  return pior;
}

for (const tema of ["claro", "escuro"]) {
  const grupos = t.cor.categorias.filter((k) => k.id !== "outros");
  const rotulos = grupos.map((k) => k.nome), cores = grupos.map((k) => t.cor.grafico[tema][k.cor]);
  const m = t.cor.marca[tema];
  console.log(`\n${tema}: menor distância entre dois dos ${grupos.length} grupos da rosca e entre os 3 níveis de essencialidade`);
  console.log("condição".padEnd(14) + "grupos (par mais próximo)".padEnd(58) + "essencialidade (par mais próximo)");
  for (const [nome, M] of Object.entries(MATRIZES)) {
    const g = menorPar(rotulos, cores, M);
    const e = menorPar(["Essencial", "Importante", "Flexível"], [m.essencial, m.importante, m.flexivel], M);
    console.log(nome.padEnd(14) + `${g.d.toFixed(1)} (${g.a} × ${g.b})`.padEnd(58) + `${e.d.toFixed(1)} (${e.a} × ${e.b})`);
  }
}
