// Monta a Paçoca com as peças soltas de pecas/ (de trás para a frente) e grava um PNG.
// Uso, dentro desta pasta: node boneco.mjs saida.png [parada|acena|feliz]
// Dependência: npm install --no-save --prefix docs/design sharp
import { createRequire } from "node:module";
const sharp = createRequire(new URL("../../../", import.meta.url))("sharp");
const P = (n, k = 1, flop = false) => (async () => { let i = sharp(`pecas/${n}.png`); const m = await i.metadata(); i = i.resize(Math.round(m.width * k)); if (flop) i = i.flop(); return i.png().toBuffer(); })();
const estado = process.argv[3] ?? "parada";
const L = [
  [P("07-perna-esq", 0.62), 128, 500], [P("08-perna-dir", 0.62), 246, 500],
  [P("03-tronco"), 96, 228],
  [P("04-pochete", 0.92), 78, 400],
  [P("05-braco-esq", 0.8), 66, 278],
  estado === "acena" ? [P("09-braco-acenando", 0.8), 318, 168] : [P("06-braco-dir", 0.8), 300, 278],
  [P(estado === "feliz" ? "02-cabeca-olhos-fechados" : "01-cabeca"), 68, 0],
];
if (estado === "feliz") L.push([P("10-boca-aberta", 0.62), 192, 196]);
const cs = []; for (const [b, x, y] of L) cs.push({ input: await b, left: x, top: y });
await sharp({ create: { width: 560, height: 680, channels: 4, background: { r: 0, g: 0, b: 0, alpha: 0 } } }).composite(cs).png().toFile(process.argv[2]);
