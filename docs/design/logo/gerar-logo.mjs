// Gera logo, símbolo e ícones do GranaPaCá em SVG (Identidade Toca Editorial — Opção B: Paca Deitada Evoluída).
// Uso: node docs/design/logo/gerar-logo.mjs
import { writeFileSync } from "node:fs";

const SANS = "'Plus Jakarta Sans', 'Inter', system-ui, -apple-system, sans-serif";

// ---------- Silhueta da paca deitada (sem contorno preto, focinho alongado e pintas limpas) ----------
// Quadro base 256x256 (centrada em 128, 134), reutilizada no logo, símbolo e ícones.
const PACA_CORPO =
  "M46 164 C41 134 62 104 108 100 C125 98 139 97 148 90 " +
  "C146 79 153 72 161 75 C165 77 167 81 168 85 " +
  "C173 78 180 76 186 82 C189 86 188 92 185 96 " +
  "C204 100 223 112 224 127 C225 141 213 149 197 149 " +
  "C186 149 178 146 169 144 C174 152 174 163 165 171 " +
  "C154 181 133 184 106 184 C71 184 50 177 46 164 Z";

// Dobra suave da patinha frontal descansando sob o queixo.
const PACA_PATA_DOBRA = "M128 167 C142 167 156 161 163 150";
// Olho fechado sereno (arco delicado de paca descansando).
const PACA_OLHO = "M177 118 Q186 125 195 118";
// Narina discreta na ponta do focinho alongado.
const PACA_NARINA = "M213 125 Q217 127 215 131";

// Pintas ovais em duas fileiras leves no flanco (5 no símbolo/ícone, 3 maiores no favicon).
const PINTAS_5 = [
  [80, 129, 7.2, 4.2, -18],
  [103, 121, 7.8, 4.4, -12],
  [127, 119, 7.2, 4.1, -6],
  [74, 147, 7.6, 4.4, -14],
  [99, 141, 8.2, 4.6, -10],
];
const PINTAS_3 = [
  [84, 129, 9.2, 5.4, -16],
  [112, 122, 9.5, 5.6, -10],
  [91, 149, 9.4, 5.4, -12],
];

function pacaDeitada({ corpo, detalhe, pintas = PINTAS_5, olho = true, dobra = true, narina = true }) {
  const dots = pintas
    .map(([x, y, rx, ry, rot]) => `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" transform="rotate(${rot} ${x} ${y})" fill="${detalhe}"/>`)
    .join("");
  return [
    `<path d="${PACA_CORPO}" fill="${corpo}"/>`,
    dots,
    olho ? `<path d="${PACA_OLHO}" fill="none" stroke="${detalhe}" stroke-width="5.0" stroke-linecap="round"/>` : "",
    narina ? `<path d="${PACA_NARINA}" fill="none" stroke="${detalhe}" stroke-width="4.0" stroke-linecap="round"/>` : "",
    dobra ? `<path d="${PACA_PATA_DOBRA}" fill="none" stroke="${detalhe}" stroke-width="4.6" stroke-linecap="round"/>` : "",
  ].join("");
}

// Versão com máscara vazada para monocromático (Android temático e logo mono).
function pacaVazada(id, cor, { pintas = PINTAS_5, olho = true, dobra = true, narina = true } = {}) {
  const dots = pintas
    .map(([x, y, rx, ry, rot]) => `<ellipse cx="${x}" cy="${y}" rx="${rx}" ry="${ry}" transform="rotate(${rot} ${x} ${y})" fill="#000"/>`)
    .join("");
  const mask =
    `<mask id="${id}"><path d="${PACA_CORPO}" fill="#fff"/>${dots}` +
    (olho ? `<path d="${PACA_OLHO}" fill="none" stroke="#000" stroke-width="5.2" stroke-linecap="round"/>` : "") +
    (narina ? `<path d="${PACA_NARINA}" fill="none" stroke="#000" stroke-width="4.2" stroke-linecap="round"/>` : "") +
    (dobra ? `<path d="${PACA_PATA_DOBRA}" fill="none" stroke="#000" stroke-width="4.8" stroke-linecap="round"/>` : "") +
    `</mask>`;
  return { defs: mask, body: `<rect width="256" height="256" fill="${cor}" mask="url(#${id})"/>` };
}

// ---------- Logo (Opção B — Paca Deitada Evoluída sobre "PaCá") ----------
const LOGO = {
  cor: { grana: "#231C16", paca: "#A84C19", bicho: "#B85C28", detalhe: "#FAF8F5", fundo: null },
  escuro: { grana: "#F5F1EC", paca: "#E5965C", bicho: "#E5965C", detalhe: "#14110F", fundo: "#14110F" },
  mono: { grana: "currentColor", paca: "currentColor", bicho: "currentColor", detalhe: null, fundo: null },
};

function logo(nome, { respiro = false } = {}) {
  const c = LOGO[nome];
  const m = respiro ? 44 : 20;
  const W = 524, H = 172;
  const vb = [-m, -m, W + 2 * m, H + 2 * m];
  const fundo = respiro ? "#FAF8F5" : c.fundo;
  const guia = respiro
    ? `<rect x="0" y="0" width="${W}" height="${H}" fill="none" stroke="#8A7B6D" stroke-width="1.5" stroke-dasharray="8 6"/>` +
      `<rect x="${-m + 2}" y="${-m + 2}" width="${W + 2 * m - 4}" height="${H + 2 * m - 4}" fill="none" stroke="#B53720" stroke-width="2" stroke-dasharray="10 6"/>`
    : "";

  // Paca deitada pousada com respiro limpo logo acima de "aC" (sem tocar no "P" nem no acento do "á").
  let defs = "";
  let bichoSvg = "";
  const tx = "translate(320 -26) scale(0.56)";
  if (nome === "mono") {
    const v = pacaVazada("pacaLogoMono", "currentColor");
    defs = `<defs>${v.defs}</defs>`;
    bichoSvg = `<g transform="${tx}">${v.body}</g>`;
  } else {
    bichoSvg = `<g transform="${tx}">${pacaDeitada({ corpo: c.bicho, detalhe: c.detalhe })}</g>`;
  }

  return (
    `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vb.join(" ")}" role="img" aria-labelledby="t">` +
    `<title id="t">Grana PaCá</title>${defs}` +
    (fundo ? `<rect x="${vb[0]}" y="${vb[1]}" width="${vb[2]}" height="${vb[3]}" fill="${fundo}"/>` : "") +
    guia +
    bichoSvg +
    `<text x="18" y="148" font-family="${SANS}" font-size="82" font-weight="700" letter-spacing="-2.4">` +
    `<tspan fill="${c.grana}">Grana </tspan><tspan fill="${c.paca}">PaCá</tspan></text>` +
    `</svg>\n`
  );
}

// ---------- Símbolo e ícones do app (Paca Deitada) ----------
const svg256 = (titulo, corpo, defs = "") =>
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" role="img" aria-labelledby="t"><title id="t">${titulo}</title>${defs}${corpo}</svg>\n`;
const fundo = (cor, rx = 0) => (cor ? `<rect width="256" height="256"${rx ? ` rx="${rx}"` : ""} fill="${cor}"/>` : "");
const escala = (k, dx, dy, corpo) => `<g transform="translate(${128 + dx} ${128 + dy}) scale(${k}) translate(-134 -131)">${corpo}</g>`;

const simboloSvg = () =>
  svg256("Símbolo do GranaPaCá", escala(1.12, 0, 2, pacaDeitada({ corpo: "#A84C19", detalhe: "#FAF8F5" })));

const iconeClaro = () =>
  svg256(
    "Ícone do GranaPaCá",
    fundo("#A84C19") + escala(1.06, 0, 2, pacaDeitada({ corpo: "#FAF8F5", detalhe: "#A84C19" }))
  );

const iconeEscuro = () =>
  svg256(
    "Ícone do GranaPaCá, aparência escura",
    fundo("#1E1A17") + escala(1.06, 0, 2, pacaDeitada({ corpo: "#E5965C", detalhe: "#1E1A17" }))
  );

const iconeTingido = () => {
  const v = pacaVazada("pacaTingido", "#D8D4CE");
  return svg256("Ícone do GranaPaCá, aparência tingida", escala(1.06, 0, 2, v.body), `<defs>${v.defs}</defs>`);
};

// Android adaptativo: círculo seguro de 66 dp dentro de 108 dp (~61% do quadro).
const iconeAndroidFrente = () =>
  svg256("Frente do ícone adaptativo", escala(0.74, 0, 2, pacaDeitada({ corpo: "#FAF8F5", detalhe: "#A84C19" })));

const iconeAndroidMono = () => {
  const v = pacaVazada("pacaMono", "#000000", { pintas: PINTAS_3 });
  return svg256("Ícone monocromático", escala(0.74, 0, 2, v.body), `<defs>${v.defs}</defs>`);
};

const faviconSvg = () =>
  svg256(
    "GranaPaCá",
    fundo("#A84C19", 56) + escala(1.14, 0, 2, pacaDeitada({ corpo: "#FAF8F5", detalhe: "#A84C19", pintas: PINTAS_3, narina: false }))
  );

const ARQUIVOS = {
  "logo-cor.svg": logo("cor"),
  "logo-escuro.svg": logo("escuro"),
  "logo-mono.svg": logo("mono"),
  "logo-respiro.svg": logo("cor", { respiro: true }),
  "simbolo.svg": simboloSvg(),
  "icone-ios-claro.svg": iconeClaro(),
  "icone-ios-escuro.svg": iconeEscuro(),
  "icone-ios-tingido.svg": iconeTingido(),
  "icone-android-fundo.svg": svg256("Fundo do ícone adaptativo", fundo("#A84C19")),
  "icone-android-frente.svg": iconeAndroidFrente(),
  "icone-android-mono.svg": iconeAndroidMono(),
  "favicon.svg": faviconSvg(),
};

const pasta = new URL("./", import.meta.url);
for (const [nome, conteudo] of Object.entries(ARQUIVOS)) writeFileSync(new URL(nome, pasta), conteudo);
console.log(`${Object.keys(ARQUIVOS).length} SVGs gravados em docs/design/logo`);
