// Kettle — parametric SVG source of truth (mascot #2).
//
// An anthropomorphized kettlebell, sibling to the Repelican. Five poses, each
// a periodic function of time so it loops seamlessly. This file is the design
// reference; the app re-implements the same geometry natively in
// PhaseTraining/Components/KettleView.swift (Canvas + TimelineView), where the
// loops actually animate. Keep the two in sync when the rig changes.
//
// Run:  node handoff/mascot2/generate.mjs
// Emits a representative still per pose (kettle-<pose>.svg) plus kettle.svg
// (neutral flex). Motion lives in KettleView; these stills are for reference.
//
// Palette binds to PhaseTraining brand tokens (see MASCOT2.md / Theme.swift):
//   cast body = ink #F5F5F0 · handle = accent #D4FF3D · feet = danger #FF6B4A
// Shades (#DEDED6 / #C7C7BD / #E24A2C) are derived tints, not tokens.

import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const C = { ink:'#F5F5F0', shade:'#DEDED6', deep:'#C7C7BD', coral:'#FF6B4A', coralDk:'#E24A2C', accent:'#D4FF3D', accentDk:'#8FA82A', eye:'#14161A' };
const TAU = Math.PI*2, LIMB = 8, HAND = 7;
const seg=(a,b,w,col)=>`<line x1="${a[0]}" y1="${a[1]}" x2="${b[0]}" y2="${b[1]}" stroke="${col}" stroke-width="${w}" stroke-linecap="round"/>`;
const poly=(pts,w,col)=>{let d=`M ${pts[0][0]} ${pts[0][1]}`;for(let i=1;i<pts.length;i++)d+=` L ${pts[i][0]} ${pts[i][1]}`;return `<path d="${d}" fill="none" stroke="${col}" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>`;};
const dot=(x,y,r,col)=>`<circle cx="${x}" cy="${y}" r="${r}" fill="${col}"/>`;
const arm=(sh,el,fi)=>seg(sh,el,LIMB,C.shade)+seg(el,fi,LIMB,C.shade)+dot(fi[0],fi[1],HAND,C.shade);
const shoe=(ft)=>`<path d="M ${ft[0]-9} ${ft[1]} q -4 8 2 10 l 14 0 q 3 -6 -2 -10 z" fill="${C.coral}"/>`+dot(ft[0]-2,ft[1]-1,3,C.coralDk);

function face(cx,cy,mouth){
  const m = mouth==='open'
    ? `<path d="M ${cx-6} ${cy+14} q 6 8 12 0 q -6 -3 -12 0 z" fill="${C.coralDk}"/>`
    : `<path d="M ${cx-7} ${cy+13} q 7 7 14 0" fill="none" stroke="${C.eye}" stroke-width="2.4" stroke-linecap="round"/>`;
  return `${dot(cx-11,cy,6.5,'#fff')}${dot(cx+11,cy,6.5,'#fff')}${dot(cx-9,cy+1,3.1,C.eye)}${dot(cx+13,cy+1,3.1,C.eye)}${dot(cx-10,cy-1,1.1,C.accent)}${dot(cx+12,cy-1,1.1,C.accent)}${m}`;
}
function body(mouth,squash=0){
  const ry=46*(1+squash), rx=46*(1-squash*0.6);
  return `
    <path d="M 56 90 L 56 66 Q 56 42 80 42 Q 104 42 104 66 L 104 90" fill="none" stroke="${C.accent}" stroke-width="12" stroke-linecap="round"/>
    <path d="M 60 84 L 64 98 L 96 98 L 100 84 Z" fill="${C.ink}"/>
    <ellipse cx="80" cy="124" rx="${rx}" ry="${ry}" fill="${C.ink}" stroke="${C.deep}" stroke-width="2"/>
    <ellipse cx="66" cy="108" rx="15" ry="11" fill="#fff" opacity=".32"/>
    <circle cx="80" cy="128" r="23" fill="none" stroke="${C.deep}" stroke-width="1.5" opacity=".45"/>
    ${face(80,118,mouth)}`;
}
const wrap=(dy,rot,cx,cy,inner)=>`<g transform="translate(0 ${dy}) rotate(${rot} ${cx} ${cy})">${inner}</g>`;

function kFlex(t){
  const ph=(t%1.1)/1.1, flex=0.5-0.5*Math.cos(TAU*ph);
  const el=[26,98-3*flex], elR=[134,98-3*flex], fy=80-6*flex, fx=50-2*flex, op=(0.25+0.75*flex).toFixed(2);
  const limbs=arm([40,110],el,[fx,fy])+arm([120,110],elR,[160-fx,fy])+dot(el[0],el[1],8+6*flex,C.shade)+dot(elR[0],elR[1],8+6*flex,C.shade)
    +seg([66,152],[60,176],LIMB,C.shade)+shoe([60,176])+seg([94,152],[100,176],LIMB,C.shade)+shoe([100,176]);
  const ticks=`<g stroke="${C.accent}" stroke-width="3" stroke-linecap="round" opacity="${op}"><line x1="${34-3*flex}" y1="74" x2="${27-5*flex}" y2="69"/><line x1="${126+3*flex}" y1="74" x2="${133+5*flex}" y2="69"/></g>`;
  return wrap(-2.5*flex,0,80,120, ticks+body(flex>0.62?'open':'smile',0.04*flex)+limbs);
}
function kStretch(t){
  const u=(t%3)/3, s=Math.sin(TAU*u), breathe=0.5-0.5*Math.cos(TAU*u), reachY=58-3*breathe;
  const limbs=poly([[40,110],[58,80],[74,reachY+3]],LIMB,C.shade)+poly([[120,110],[102,80],[86,reachY+3]],LIMB,C.shade)+dot(80,reachY,8,C.shade)
    +seg([64,152],[56,176],LIMB,C.shade)+shoe([56,176])+seg([96,152],[104,176],LIMB,C.shade)+shoe([104,176]);
  const arc=`<path d="M 52 ${(52-2*breathe).toFixed(1)} q 28 -12 56 0" fill="none" stroke="${C.accentDk}" stroke-width="2" stroke-dasharray="3 4" opacity="${(0.35+0.4*breathe).toFixed(2)}"/>`;
  return `<g transform="translate(0 ${(-1.5*breathe).toFixed(2)}) rotate(${(7*s).toFixed(2)} 80 152)">${arc+body('smile')+limbs}</g>`;
}
function kSnow(t){
  const u=(t%1.7)/1.7, c=Math.sin(TAU*u);
  const limbs=arm([40,110],[30,92],[44-7*c,72-2*c])+arm([120,110],[134,116],[132+5*c,118+9*c])
    +poly([[70,152],[62,166],[64,172]],LIMB,C.shade)+poly([[94,152],[102,166],[100,172]],LIMB,C.shade);
  const board=`<g transform="rotate(${(-12+5*c).toFixed(2)} 80 178)"><rect x="26" y="174" width="108" height="11" rx="5.5" fill="${C.accent}"/><rect x="58" y="169" width="10" height="8" rx="2" fill="${C.coral}"/><rect x="92" y="169" width="10" height="8" rx="2" fill="${C.coral}"/></g>`;
  let snow=''; for(let i=0;i<6;i++){const f=((u+i*0.16)%1); snow+=dot(30-26*f,176-12*f,2.4*(1-f),'#fff');}
  return wrap((-1.2*(1-Math.abs(c))).toFixed(2),(5*c).toFixed(2),80,130, `<g opacity=".8">${snow}</g>`+body(Math.abs(c)>0.6?'open':'smile')+limbs+board);
}
function kClimb(t){
  const u=(t%2.4)/2.4, reach=0.5-0.5*Math.cos(TAU*u);
  const holds=dot(46,56,7,C.accent)+dot(120,92,6,C.accent)+dot(54,150,6,C.accent)+dot(40,104,5,C.accent);
  const lh=[58+(46-58)*reach,118+(56-118)*reach];
  const inner=body('smile')+poly([[52,112],[45,90],lh],LIMB,C.shade)+dot(lh[0],lh[1],HAND,C.shade)
    +poly([[112,112],[118,100],[120,92]],LIMB,C.shade)+dot(120,92,HAND,C.shade)
    +poly([[70,152],[60,152+7*(1-reach)],[54,150]],LIMB,C.shade)+shoe([54,150])+poly([[92,152],[99,150],[90,144]],LIMB,C.shade);
  const chalk=reach>0.72?`<g fill="#fff" opacity="${(0.6*(reach-0.72)/0.28).toFixed(2)}">${dot(46,52,3,'#fff')}${dot(51,48,2,'#fff')}${dot(41,49,1.6,'#fff')}</g>`:'';
  return `<g transform="rotate(7 80 120)">${holds}<g transform="translate(0 ${(-2*reach).toFixed(2)})">${inner}</g>${chalk}</g>`;
}
function kBike(t){
  const u=(t%1)/1, th=TAU*u, K=[80,178], rp=10, B=[38,176], F=[126,176], S=[80,166], H=[116,150];
  const pedL=[K[0]+rp*Math.cos(th),K[1]+rp*Math.sin(th)], pedR=[K[0]+rp*Math.cos(th+Math.PI),K[1]+rp*Math.sin(th+Math.PI)];
  const wheel=(c,a0)=>{let g=`<circle cx="${c[0]}" cy="${c[1]}" r="16" fill="none" stroke="${C.deep}" stroke-width="3"/>`;for(let k=0;k<4;k++){const a=a0+k*Math.PI/4;g+=seg([c[0]+3*Math.cos(a),c[1]+3*Math.sin(a)],[c[0]+14*Math.cos(a),c[1]+14*Math.sin(a)],1.5,C.deep);}return g+dot(c[0],c[1],2.5,C.accent);};
  const frame=poly([B,S,H],3,C.accent)+poly([B,K],3,C.accent)+poly([K,H],3,C.accent)+poly([S,K],3,C.accent)+poly([H,F],3,C.accent)+seg(H,[H[0]+9,H[1]-7],3,C.accent);
  const bike=wheel(B,-th*1.7)+wheel(F,-th*1.7)+frame+dot(K[0],K[1],3,C.deep);
  const legs=poly([[74,168],[pedL[0]-3,pedL[1]-7],pedL],LIMB,C.shade)+shoe(pedL)+poly([[88,168],[pedR[0]+3,pedR[1]-7],pedR],LIMB,C.shade)+shoe(pedR);
  const arms=poly([[102,120],[110,136],[H[0]-1,H[1]-2]],LIMB,C.shade)+dot(H[0]-1,H[1]-2,HAND,C.shade);
  const speed=`<g stroke="${C.accent}" stroke-width="3" stroke-linecap="round" opacity="${(0.3+0.4*Math.abs(Math.sin(th))).toFixed(2)}"><line x1="8" y1="120" x2="24" y2="120"/><line x1="4" y1="134" x2="22" y2="134"/><line x1="10" y1="148" x2="26" y2="148"/></g>`;
  return wrap((1.1*Math.sin(2*th)).toFixed(2),-4,80,124, speed+bike+body('smile')+arms+legs);
}

const svg=inner=>`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 160 200" width="160" height="200">${inner}</svg>\n`;
const here = dirname(fileURLToPath(import.meta.url));
// Representative still per pose (phase chosen to show the pose clearly).
const stills = [
  ['kettle.svg',           kFlex,    0.00],
  ['kettle-flex.svg',      kFlex,    0.55],
  ['kettle-stretch.svg',   kStretch, 2.25],
  ['kettle-snowboard.svg', kSnow,    0.42],
  ['kettle-climb.svg',     kClimb,   1.20],
  ['kettle-bike.svg',      kBike,    0.12],
];
for (const [file, fn, t] of stills) {
  writeFileSync(join(here, file), svg(fn(t)));
  console.log('wrote', file);
}
