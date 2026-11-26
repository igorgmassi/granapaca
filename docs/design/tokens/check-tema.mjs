// Confere se as cores de granapaca_theme.dart batem com o tokens.json (só leitura; sai com código 1 se algo diferir).
// Uso: node docs/design/tokens/check-tema.mjs
import { readFileSync } from "node:fs";

const t = JSON.parse(readFileSync(new URL("./tokens.json", import.meta.url), "utf8"));
const dart = readFileSync(new URL("./granapaca_theme.dart", import.meta.url), "utf8");
const bloco = (ini, fim) => { const i = dart.indexOf(ini); return dart.slice(i, dart.indexOf(fim, i)); };
const argb = (h) => `0xFF${h.slice(1).toUpperCase()}`;

let ok = 0, falhas = 0;
const confere = (texto, nome, hex, onde) => {
  const m = texto.match(new RegExp(`${nome}: (?:const )?Color\\((0x[0-9A-Fa-f]{8})\\)`));
  if (m && `0xFF${m[1].slice(4).toUpperCase()}` === argb(hex)) ok++;
  else { falhas++; console.log(`DIFERE ${onde} ${nome}: tokens ${hex}, tema ${m ? m[1] : "ausente"}`); }
};

// ColorScheme do Material 3: toda chave de cor.esquema.
for (const [tema, ini, fim] of [["claro", "const _claro", "const _escuro"], ["escuro", "const _escuro", "/// Tema do app"]]) {
  const b = bloco(ini, fim);
  for (const [k, v] of Object.entries(t.cor.esquema[tema])) confere(b, k, v, `esquema.${tema}`);
}

// GranaTokens: marca (o escuro herda do claro o que não troca) e os 8 grupos da rosca, na ordem fixa.
const claro = bloco("static final claro", "static final escuro"), escuro = bloco("static final escuro", "@override");
for (const [tema, b] of [["claro", claro], ["escuro", escuro]]) {
  for (const [k, v] of Object.entries(t.cor.marca[tema])) {
    if (tema === "escuro" && !b.includes(`${k}: const Color`)) { if (v !== t.cor.marca.claro[k]) { falhas++; console.log(`DIFERE marca.escuro ${k}: falta no tema`); } else ok++; continue; }
    confere(b, k, v, `marca.${tema}`);
  }
  const ordem = t.cor.grafico.ordemDaRosca.filter((id) => id !== "outros").map((id) => t.cor.grafico[tema][t.cor.categorias.find((c) => c.id === id).cor].slice(1).toUpperCase());
  const pos = ordem.map((h) => b.indexOf(`0xFF${h}`));
  if (pos.some((p) => p < 0) || pos.some((p, i) => i && p < pos[i - 1])) { falhas++; console.log(`DIFERE grafico.${tema}: cores ausentes ou fora da ordem da rosca`); } else ok += ordem.length;
  confere(b, "outros", t.cor.grafico[tema].outros, `grafico.${tema}`);
}

// O que o JSON tem e o tema ainda não: informativo, não conta como falha.
const faltam = ["movimento.duracao.pulsoCarregamento", "cor.grafico.sequencial", "cor.categorias", "sombra", "tamanho", "layout"].filter((c) => {
  const chaveDart = { "movimento.duracao.pulsoCarregamento": "pulsoCarregamento", "cor.grafico.sequencial": "sequencial", "cor.categorias": "categorias", sombra: "sombra", tamanho: "circuloCategoria", layout: "larguraMaxima" }[c];
  return !dart.includes(chaveDart);
});
console.log(`${ok} valores conferidos, ${falhas} diferença(s).`);
if (faltam.length) console.log(`Ainda fora do tema Dart: ${faltam.join(", ")}`);
process.exit(falhas ? 1 : 0);
