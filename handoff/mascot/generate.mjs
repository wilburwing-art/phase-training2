// The Repelican — parametric SVG source of truth.
//
// One character, one `bulk` parameter (0.0 … 1.0) that drives torso width,
// arm thickness, and the flex bump. This is the design reference; the shipped
// app re-implements the same geometry natively in
// PhaseTraining/Components/RepelicanView.swift (Canvas), so `bulk` stays a
// live value there. Keep the two in sync when the silhouette changes.
//
// Run:  node handoff/mascot/generate.mjs
// Emits repelican-lean.svg (0.0), repelican-athletic.svg (0.55),
// repelican-swole.svg (1.0), and repelican.svg (canonical = athletic).
//
// Palette is bound to PhaseTraining brand tokens (see MASCOT.md / Theme.swift):
//   feathers  = ink      #F5F5F0     bill + feet = danger #FF6B4A
//   headband/wristbands = accent #D4FF3D
// Shades (#DEDED6 / #C7C7BD / #E24A2C / #FF8A6E) are derived tints, not tokens.

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const C = {
  ink: "#F5F5F0", shade: "#DEDED6", deep: "#C7C7BD",
  coral: "#FF6B4A", coralDk: "#E24A2C", pouch: "#FF8A6E",
  accent: "#D4FF3D", accentDk: "#8FA82A", bg: "#0A0B0D", eye: "#14161A",
};

// Front-facing double-biceps flex. Geometry mirrors RepelicanView.draw().
export function pelican(b) {
  const cx = 130;
  const bodyRX = 34 + b * 20;
  const bodyCY = 206, bodyRY = 60 + b * 6;
  const limb = 8 + b * 8;
  const bicep = 8 + b * 17;
  const headR = 34, headCY = 90;
  const shoulderY = 170;
  const shX = bodyRX * 0.62;

  const sh = [cx - shX, shoulderY];
  const el = [cx - (bodyRX + limb + 22), shoulderY - 12];
  const fist = [cx - (headR - 4), 78];
  const wri = [el[0] * 0.35 + fist[0] * 0.65, el[1] * 0.35 + fist[1] * 0.65];

  const arm = (x1, y1, x2, y2) =>
    `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" stroke="${C.shade}" stroke-width="${limb * 2}" stroke-linecap="round"/>`;
  const armPair = (a, c) =>
    arm(a[0], a[1], c[0], c[1]) + arm(2 * cx - a[0], a[1], 2 * cx - c[0], c[1]);
  const dot = (x, y, r, fill) => `<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}"/>`;
  const bandPair = (p, r, col) =>
    `<circle cx="${p[0]}" cy="${p[1]}" r="${r}" fill="none" stroke="${col}" stroke-width="6" stroke-linecap="round"/>` +
    `<circle cx="${2 * cx - p[0]}" cy="${p[1]}" r="${r}" fill="none" stroke="${col}" stroke-width="6" stroke-linecap="round"/>`;

  let ticks = "";
  if (b > 0.75) {
    ticks = [-1, 1].map((s) => {
      const gx = cx + s * (bodyRX + limb + 30);
      return `<g stroke="${C.accent}" stroke-width="3" stroke-linecap="round" opacity=".9">
        <line x1="${gx}" y1="126" x2="${gx + s * 10}" y2="126"/>
        <line x1="${gx - s * 2}" y1="140" x2="${gx + s * 12}" y2="140"/></g>`;
    }).join("");
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 260 300" width="260" height="300" role="img" aria-label="The Repelican, ${Math.round(b * 100)} percent bulk">
  <defs>
    <linearGradient id="body" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${C.ink}"/><stop offset="1" stop-color="${C.deep}"/>
    </linearGradient>
  </defs>
  ${ticks}
  <!-- feet -->
  <g fill="${C.coral}">
    <path d="M ${cx - 24} 262 q -16 6 -18 20 q 18 6 30 -2 q 4 -10 -12 -18 z"/>
    <path d="M ${cx + 24} 262 q 16 6 18 20 q -18 6 -30 -2 q -4 -10 12 -18 z"/>
    <rect x="${cx - 24}" y="248" width="9" height="20" rx="4" fill="${C.coralDk}"/>
    <rect x="${cx + 15}" y="248" width="9" height="20" rx="4" fill="${C.coralDk}"/>
  </g>
  <!-- torso -->
  <ellipse cx="${cx}" cy="${bodyCY}" rx="${bodyRX}" ry="${bodyRY}" fill="url(#body)" stroke="${C.deep}" stroke-width="2"/>
  <path d="M ${cx} 168 q 0 ${28 + b * 14} 0 ${44 + b * 16}" stroke="${C.deep}" stroke-width="2" fill="none" opacity=".55"/>
  ${b > 0.4 ? `<path d="M ${cx - bodyRX * 0.5} 176 q ${bodyRX * 0.5} ${10 + b * 10} 0 ${26 + b * 10}" stroke="${C.deep}" stroke-width="2" fill="none" opacity=".4"/>
  <path d="M ${cx + bodyRX * 0.5} 176 q ${-bodyRX * 0.5} ${10 + b * 10} 0 ${26 + b * 10}" stroke="${C.deep}" stroke-width="2" fill="none" opacity=".4"/>` : ""}
  <!-- arms -->
  ${armPair(sh, el)}
  ${armPair(el, fist)}
  ${dot(el[0] + limb * 0.3, el[1] - limb * 0.2, bicep, C.ink)}
  ${dot(2 * cx - (el[0] + limb * 0.3), el[1] - limb * 0.2, bicep, C.ink)}
  ${b > 0.4 ? `<path d="M ${el[0] - bicep * 0.5} ${el[1] - bicep * 0.6} q ${bicep * 0.5} ${-bicep * 0.4} ${bicep} ${bicep * 0.2}" stroke="${C.deep}" stroke-width="2" fill="none" opacity=".5"/>
  <path d="M ${2 * cx - (el[0] - bicep * 0.5)} ${el[1] - bicep * 0.6} q ${-bicep * 0.5} ${-bicep * 0.4} ${-bicep} ${bicep * 0.2}" stroke="${C.deep}" stroke-width="2" fill="none" opacity=".5"/>` : ""}
  ${dot(fist[0], fist[1], limb + 2, C.shade)}
  ${dot(2 * cx - fist[0], fist[1], limb + 2, C.shade)}
  ${bandPair(wri, limb + 1, C.accent)}
  <!-- head -->
  <circle cx="${cx}" cy="${headCY}" r="${headR}" fill="url(#body)" stroke="${C.deep}" stroke-width="2"/>
  <path d="M ${cx - headR + 2} ${headCY - 12} a ${headR} ${headR} 0 0 1 ${2 * headR - 4} 0 l 0 9 a ${headR} ${headR} 0 0 0 ${-(2 * headR - 4)} 0 z" fill="${C.accent}"/>
  <rect x="${cx - headR + 2}" y="${headCY - 6}" width="${2 * headR - 4}" height="4" fill="${C.accentDk}" opacity=".6"/>
  <path d="M ${cx + headR - 6} ${headCY - 4} q 20 2 30 16 q -14 -2 -20 2 q 2 -10 -10 -18 z" fill="${C.accent}"/>
  <!-- eyes -->
  ${dot(cx - 12, headCY + 3, 7, "#fff")}${dot(cx + 12, headCY + 3, 7, "#fff")}
  ${dot(cx - 10, headCY + 4, 3.4, C.eye)}${dot(cx + 14, headCY + 4, 3.4, C.eye)}
  ${dot(cx - 11, headCY + 2.4, 1.2, C.accent)}${dot(cx + 13, headCY + 2.4, 1.2, C.accent)}
  <!-- bill + pouch -->
  <path d="M ${cx - 14} ${headCY + 12} q 14 6 28 0 q 6 20 -2 36 q -12 10 -24 0 q -8 -16 -2 -36 z" fill="${C.coral}" stroke="${C.coralDk}" stroke-width="2"/>
  <path d="M ${cx - 9} ${headCY + 22} q 9 6 18 0 q 2 12 -3 22 q -6 6 -12 0 q -5 -10 -3 -22 z" fill="${C.pouch}"/>
  <circle cx="${cx}" cy="${headCY + 58}" r="3" fill="${C.coralDk}"/>
</svg>
`;
}

const here = dirname(fileURLToPath(import.meta.url));
const builds = [
  ["repelican-lean.svg", 0.0],
  ["repelican-athletic.svg", 0.55],
  ["repelican-swole.svg", 1.0],
  ["repelican.svg", 0.55], // canonical
];
for (const [file, b] of builds) {
  writeFileSync(join(here, file), pelican(b));
  console.log("wrote", file, "(bulk", b + ")");
}
