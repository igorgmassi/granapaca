// Recorte da Paçoca ilustrada: tira o fundo branco com transparência suave e sem a mistura com o branco na borda.
// Lê origem/*.png (RGB sobre branco) e grava ./pacoca-*.png (RGBA) e ../../telas/pacoca-mini.json.
// Uso: node docs/design/mascote/ilustrada/recorte.mjs
// Dependência (uma vez, fora do Git): npm install --no-save --prefix docs/design sharp
import sharp from "sharp";
import { readdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const R = 3;         // faixa de borda, em pixels: onde o desenho se mistura com o fundo
const BRANCO = 247;  // canal mínimo do fundo puro
const QUASE = 236;   // canal mínimo do "quase fundo": ruído de compressão e rampa fraca em volta da borda
const JANELA = 5;    // raio da janela onde o pixel de borda procura a cor do interior; sem nada ali, é estrutura fina
const PESO_DIST = 0.5;                  // entre candidatas iguais, fica a mais próxima
const PESO_ALFA = [0, 0, 3000, 10000];  // preferência por alfa cheio, pela profundidade na faixa (0 a R)
// Brancos fechados que NÃO são buraco, por pose: um ponto (x, y) dentro de cada um. Aqui, os dois dentes.
const MANTER = { "06-comemorando": [[151, 126], [144, 129]] };
const VIZ = [[-1, -1], [0, -1], [1, -1], [-1, 0], [1, 0], [-1, 1], [0, 1], [1, 1]];

export async function recortar(arq, log = () => {}) {
  const { data: d, info } = await sharp(arq).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const w = info.width, h = info.height, n = w * h;
  const nome = arq.replace(/^.*pacoca-|\.png$/g, "");
  const minimo = (i) => Math.min(d[3 * i], d[3 * i + 1], d[3 * i + 2]);
  const vizinhos = (i, f) => { const x = i % w, y = (i - x) / w;
    for (const [dx, dy] of VIZ) { const xx = x + dx, yy = y + dy; if (xx >= 0 && yy >= 0 && xx < w && yy < h) f(yy * w + xx); } };

  // 1. Fundo: o branco puro ligado à borda da imagem.
  const fundo = new Uint8Array(n), fila = new Int32Array(n);
  let ini = 0, fim = 0;
  const poe = (i) => { if (!fundo[i] && minimo(i) >= BRANCO) { fundo[i] = 1; fila[fim++] = i; } };
  for (let x = 0; x < w; x++) { poe(x); poe((h - 1) * w + x); }
  for (let y = 0; y < h; y++) { poe(y * w); poe(y * w + w - 1); }
  while (ini < fim) { const i = fila[ini++], x = i % w, y = (i - x) / w;
    if (x > 0) poe(i - 1); if (x < w - 1) poe(i + 1); if (y > 0) poe(i - w); if (y < h - 1) poe(i + w); }

  // 2. Buracos: branco puro fechado dentro do desenho (o vão entre o braço e a cabeça). Olho e boca são
  //    escuros em volta, então o brilho do olho fica; os dentes ficam pela lista MANTER.
  const visto = new Uint8Array(n);
  for (let s = 0; s < n; s++) {
    if (fundo[s] || visto[s] || minimo(s) < BRANCO) continue;
    const comp = [s]; visto[s] = 1;
    for (let k = 0; k < comp.length; k++) vizinhos(comp[k], (j) => { if (!visto[j] && !fundo[j] && minimo(j) >= BRANCO) { visto[j] = 1; comp.push(j); } });
    if (comp.length < 8) continue;
    const anel = new Set(comp); let borda = comp;      // a cor a 4 px de distância, fora da rampa suave
    for (let k = 0; k < 4; k++) { const prox = []; for (const i of borda) vizinhos(i, (j) => { if (!anel.has(j)) { anel.add(j); prox.push(j); } }); borda = prox; }
    const lum = borda.reduce((a, j) => a + 0.299 * d[3 * j] + 0.587 * d[3 * j + 1] + 0.114 * d[3 * j + 2], 0) / Math.max(borda.length, 1);
    const fica = (MANTER[nome] ?? []).some(([mx, my]) => comp.includes(my * w + mx));
    const buraco = !fica && lum >= 105;
    log(`  branco fechado: ${comp.length} px em (${s % w},${(s / w) | 0}), em volta ${lum.toFixed(0)} -> ${buraco ? "buraco" : "fica"}`);
    if (buraco) for (const i of comp) fundo[i] = 1;
  }

  // 3. Quase fundo: pixels muito claros ligados ao fundo. tipo: 0 fundo, 1 quase, 2 faixa, 3 interior.
  const tipo = new Uint8Array(n).fill(3);
  let frente = [];
  for (let i = 0; i < n; i++) if (fundo[i]) { tipo[i] = 0; frente.push(i); }
  for (let k = 0; k < frente.length; k++) vizinhos(frente[k], (j) => { if (tipo[j] === 3 && minimo(j) >= QUASE) { tipo[j] = 1; frente.push(j); } });
  // 4. Faixa de borda: até R pixels do fundo ou do quase fundo. prof = distância até lá (0 no quase fundo).
  const prof = new Uint8Array(n);
  for (let k = 1; k <= R; k++) { const prox = [];
    for (const i of frente) vizinhos(i, (j) => { if (tipo[j] === 3) { tipo[j] = 2; prof[j] = k; prox.push(j); } });
    frente = prox; }

  // Alfa: quanto do pixel é desenho. pixel = alfa × F + (1 − alfa) × branco.
  const mede = (i, fr, fg, fb) => { const ar = 255 - fr, ag = 255 - fg, ab = 255 - fb, q = ar * ar + ag * ag + ab * ab;
    return q < 1 ? 0 : Math.min(1, Math.max(0, ((255 - d[3 * i]) * ar + (255 - d[3 * i + 1]) * ag + (255 - d[3 * i + 2]) * ab) / q)); };
  // O que sobra ao explicar o pixel i como mistura da cor (r, g, b) com o branco.
  const sobra = (i, r, g, b) => { const a = mede(i, r, g, b), f = [r, g, b]; let e = 0;
    for (let c = 0; c < 3; c++) { const v = d[3 * i + c] - (a * f[c] + (1 - a) * 255); e += v * v; }
    return [e, a]; };
  // Custo da candidata: a sobra, mais a distância até ela, mais a preferência por alfa cheio longe do fundo
  // (um creme sombreado é creme, não um caramelo meio transparente).
  const custo = (i, r, g, b, dist2) => { const [e, a] = sobra(i, r, g, b);
    return [e + PESO_DIST * dist2 + PESO_ALFA[prof[i]] * (1 - a) ** 2, a]; };

  // 5. Cor de frente F e alfa de cada pixel da faixa. Candidatas: as cores do interior numa janela em volta.
  const F = new Float32Array(3 * n), sabe = new Uint8Array(n), alfa = new Float32Array(n), cand = new Int32Array(n).fill(-1);
  const melhor = new Float32Array(n).fill(Infinity), finos = [];
  for (let i = 0; i < n; i++) {
    if (tipo[i] === 3) { alfa[i] = 1; sabe[i] = 1; for (let c = 0; c < 3; c++) F[3 * i + c] = d[3 * i + c]; continue; }
    if (tipo[i] === 0) continue;
    const x = i % w, y = (i - x) / w;
    for (let yy = Math.max(0, y - JANELA); yy <= Math.min(h - 1, y + JANELA); yy++)
      for (let xx = Math.max(0, x - JANELA); xx <= Math.min(w - 1, x + JANELA); xx++) { const j = yy * w + xx; if (tipo[j] !== 3) continue;
        const [e, a] = custo(i, d[3 * j], d[3 * j + 1], d[3 * j + 2], (xx - x) ** 2 + (yy - y) ** 2);
        if (e < melhor[i]) { melhor[i] = e; cand[i] = j; alfa[i] = a; } }
    if (cand[i] < 0 && tipo[i] === 2) finos.push(i);
  }

  // 6. Estruturas finas (bigodes): não têm interior por perto. Os pixels mais escuros de cada matiz viram
  //    candidatas gerais, que valem para a imagem toda.
  const dir = (i) => { const v = [255 - d[3 * i], 255 - d[3 * i + 1], 255 - d[3 * i + 2]], m = Math.hypot(...v) || 1; return v.map((k) => k / m); };
  const paleta = [];
  let resto = finos.filter((i) => 255 - minimo(i) >= 60).sort((a, b) => minimo(a) - minimo(b));
  while (resto.length >= 12 && paleta.length < 4) {
    const u = dir(resto[0]), igual = (i) => { const k = dir(i); return k[0] * u[0] + k[1] * u[1] + k[2] * u[2] > 0.985; };
    const grupo = resto.filter(igual), esc = grupo.slice(0, Math.max(1, grupo.length >> 3));
    const cor = [0, 1, 2].map((c) => esc.reduce((s, i) => s + d[3 * i + c], 0) / esc.length);
    if (grupo.length >= 12) paleta.push(cor);
    // Sai da fila o que essa cor já explica: a beira clara do bigode tem o matiz torto pelo ruído, mas é bigode.
    resto = resto.filter((i) => !igual(i) && sobra(i, ...cor)[0] > 300);
  }
  log(`  ${finos.length} px finos, cores: ${paleta.map((p) => p.map((v) => v.toFixed(0)).join(",")).join(" | ") || "nenhuma"}`);
  const fino = new Uint8Array(n);
  for (let i = 0; i < n; i++) { if (tipo[i] === 0 || tipo[i] === 3) continue;
    for (const p of paleta) { const [e, a] = custo(i, p[0], p[1], p[2], (JANELA + 1) ** 2);
      if (e < melhor[i]) { melhor[i] = e; cand[i] = -2; alfa[i] = a; fino[i] = 1; for (let c = 0; c < 3; c++) F[3 * i + c] = p[c]; } }
    if (cand[i] === -1) { alfa[i] = 0; continue; }
    sabe[i] = 1;
    // 7. Pixel opaco fica com a própria cor (a linha da boca não some); o resto fica com a cor limpa da candidata.
    if (alfa[i] >= 0.995) for (let c = 0; c < 3; c++) F[3 * i + c] = d[3 * i + c];
    else if (cand[i] >= 0) for (let c = 0; c < 3; c++) F[3 * i + c] = d[3 * cand[i] + c];
    if (alfa[i] < 0.04) alfa[i] = 0;   // abaixo de 4% é ruído
  }

  // 8. A cor vaza alguns pixels para dentro do fundo, para a ampliação não puxar branco.
  for (let k = 0; k < 6; k++) { const novos = [];
    for (let i = 0; i < n; i++) { if (sabe[i]) continue; let r = 0, g = 0, b = 0, c = 0;
      vizinhos(i, (j) => { if (sabe[j]) { r += F[3 * j]; g += F[3 * j + 1]; b += F[3 * j + 2]; c++; } });
      if (c) novos.push([i, r / c, g / c, b / c]); }
    for (const [i, r, g, b] of novos) { sabe[i] = 1; F[3 * i] = r; F[3 * i + 1] = g; F[3 * i + 2] = b; } }

  const rgba = Buffer.alloc(4 * n);
  for (let i = 0; i < n; i++) for (let c = 0; c < 3; c++) rgba[4 * i + c] = Math.round(sabe[i] ? F[3 * i + c] : 255);
  for (let i = 0; i < n; i++) rgba[4 * i + 3] = Math.round(alfa[i] * 255);

  // Conferência: o recorte posto de volta sobre o branco tem de dar a imagem de origem.
  let fora = 0, visiveis = 0;
  for (let i = 0; i < n; i++) { if (tipo[i] === 0) continue; visiveis++; const a = rgba[4 * i + 3] / 255;
    for (let c = 0; c < 3; c++) if (Math.abs(a * rgba[4 * i + c] + (1 - a) * 255 - d[3 * i + c]) > 24) { fora++; break; } }
  log(`  sobre o branco: ${fora} de ${visiveis} pixels fora da origem (${(100 * fora / visiveis).toFixed(2)}%)`);
  return { rgba, w, h, alfa, fino, fora: fora / visiveis };
}

if (process.argv[1].endsWith("recorte.mjs")) {
  const aqui = new URL(".", import.meta.url), mini = {};
  for (const arq of readdirSync(new URL("origem/", aqui)).filter((a) => a.endsWith(".png")).sort()) {
    console.log(arq);
    const { rgba, w, h, fora } = await recortar(fileURLToPath(new URL(`origem/${arq}`, aqui)), console.log);
    if (fora > 0.005) throw new Error(`${arq}: o recorte se afastou da origem em ${(100 * fora).toFixed(2)}% dos pixels`);
    const img = sharp(rgba, { raw: { width: w, height: h, channels: 4 } });
    await img.clone().png({ compressionLevel: 9 }).toFile(fileURLToPath(new URL(arq, aqui)));
    // Miniatura embutida nas folhas de tela (telas/kit.mjs).
    const m = await img.clone().resize({ width: 240, height: 240, fit: "inside" }).webp({ quality: 90, alphaQuality: 100 }).toBuffer({ resolveWithObject: true });
    mini[arq.replace(/^pacoca-\d+-|\.png$/g, "")] = { w: m.info.width, h: m.info.height, uri: `data:image/webp;base64,${m.data.toString("base64")}` };
  }
  writeFileSync(new URL("../../telas/pacoca-mini.json", aqui), JSON.stringify(mini, null, 1) + "\n");
}
