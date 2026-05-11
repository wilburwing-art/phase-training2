// hd-style.jsx — HD visual system for PhaseTraining
// "Modern athletic" — near-black, electric-lime accent, technical sans.
// Used across all HD screens. Self-contained; no dependency on wire-style.

if (typeof document !== 'undefined' && !document.getElementById('hd-styles')) {
  const s = document.createElement('style');
  s.id = 'hd-styles';
  s.textContent = `
    :root {
      --hd-bg: #0A0B0D;
      --hd-surface: #14161A;
      --hd-elevated: #1C1F24;
      --hd-elevated-2: #24282F;
      --hd-line: #2A2E35;
      --hd-line-soft: #1F2229;
      --hd-ink: #F5F5F0;
      --hd-ink-2: #B5B7BD;   /* v0.2 a11y — was #A8AAB0, now 8.4:1 */
      --hd-ink-3: #7A7D85;   /* v0.2 a11y — was #5E6169 (3.8:1), now 4.7:1 AA */
      --hd-accent: #D4FF3D;
      --hd-accent-ink: #0A0B0D;
      --hd-accent-dim: #8FA82A;
      --hd-accent-wash: rgba(212,255,61,0.04);
      --hd-accent-ribbon: linear-gradient(180deg, rgba(212,255,61,0.10), rgba(212,255,61,0.02));
      --hd-accent-ribbon-line: rgba(212,255,61,0.35);
      --hd-danger: #FF6B4A;
      --hd-ok: #6BE89A;
    }
    .hd {
      font-family: 'Inter', -apple-system, system-ui, sans-serif;
      color: var(--hd-ink);
      background: var(--hd-bg);
      -webkit-font-smoothing: antialiased;
      font-feature-settings: 'cv11', 'ss01', 'ss03';
    }
    .hd * { box-sizing: border-box; }
    .hd .display { font-family: 'Space Grotesk', sans-serif; letter-spacing: -0.03em; font-weight: 600; }
    .hd .mono { font-family: 'JetBrains Mono', monospace; }
    .hd .micro { font-size: 10px; letter-spacing: 0.14em; text-transform: uppercase; font-weight: 500; color: var(--hd-ink-3); font-family: 'JetBrains Mono', monospace; }
    .hd .ink { color: var(--hd-ink); }
    .hd .ink-2 { color: var(--hd-ink-2); }
    .hd .ink-3 { color: var(--hd-ink-3); }
    .hd .accent { color: var(--hd-accent); }
    .hd .surface { background: var(--hd-surface); }
    .hd .elevated { background: var(--hd-elevated); }
    .hd .line { border: 0.5px solid var(--hd-line); }
    .hd .line-b { border-bottom: 0.5px solid var(--hd-line); }
    .hd .line-t { border-top: 0.5px solid var(--hd-line); }
    .hd .r-sm { border-radius: 8px; }
    .hd .r-md { border-radius: 14px; }
    .hd .r-lg { border-radius: 20px; }
    .hd .r-xl { border-radius: 28px; }
    .hd .pill { border-radius: 999px; }
    .hd .btn {
      display: inline-flex; align-items: center; justify-content: center;
      gap: 8px; padding: 14px 20px; border-radius: 14px;
      font-family: 'Inter', sans-serif; font-weight: 600; font-size: 15px;
      letter-spacing: -0.01em; border: 0.5px solid var(--hd-line);
      background: var(--hd-elevated); color: var(--hd-ink);
      cursor: pointer; transition: all .15s;
    }
    .hd .btn-primary {
      background: var(--hd-accent); color: var(--hd-accent-ink);
      border-color: var(--hd-accent);
      font-weight: 700;
    }
    .hd .btn-ghost { background: transparent; }
    .hd .chip {
      display: inline-flex; align-items: center; gap: 5px;
      padding: 4px 10px; border-radius: 999px;
      font-size: 11px; font-weight: 500;
      background: var(--hd-elevated); color: var(--hd-ink-2);
      border: 0.5px solid var(--hd-line);
      font-family: 'JetBrains Mono', monospace;
      letter-spacing: 0.02em;
    }
    .hd .chip-solid {
      background: var(--hd-ink); color: var(--hd-bg); border-color: var(--hd-ink);
    }
    .hd .chip-accent {
      background: var(--hd-accent); color: var(--hd-accent-ink); border-color: var(--hd-accent);
    }
    .hd .divider { height: 0.5px; background: var(--hd-line); }
    .hd .divider-dashed { height: 0.5px;
      background-image: linear-gradient(to right, var(--hd-line) 50%, transparent 50%);
      background-size: 6px 0.5px; background-repeat: repeat-x;
    }
    @keyframes hd-pulse {
      0%, 100% { opacity: 0.55; }
      50% { opacity: 1; }
    }
    .hd .pulse { animation: hd-pulse 1.6s ease-in-out infinite; }
  `;
  document.head.appendChild(s);
}

// ─────────────────────────────────────────────────────────────
// Role chip — single-letter code in a monospace pill (modern athletic
// vocabulary). ANT, PRE, MOB, STR, FDN, POW, CON.
// ─────────────────────────────────────────────────────────────
function HDRole({ role }) {
  const map = {
    antagonist: 'ANT', antag: 'ANT',
    prehab: 'PRE', mobility: 'MOB',
    strength: 'STR', foundation: 'FDN', base: 'FDN',
    power: 'POW', conditioning: 'CON', cond: 'CON',
  };
  return <span className="chip">{map[role] || role.toUpperCase()}</span>;
}

// ─────────────────────────────────────────────────────────────
// Exercise silhouette — abstract anatomical line-art. Not realistic.
// Different `kind` produces different figures. Used wherever an
// exercise needs an image. Stroke in accent on dark bg.
// ─────────────────────────────────────────────────────────────
function HDFigure({ kind = 'facepull', size = 56, tone = 'accent' }) {
  const c = tone === 'accent' ? 'var(--hd-accent, #D4FF3D)' : '#F5F5F0';
  const sw = 1.75;
  const paths = {
    // simplified anatomical figures. head = circle, torso = line,
    // limbs = angled lines. each kind has a distinct pose.
    facepull: (
      <g stroke={c} strokeWidth={sw} fill="none" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="32" cy="16" r="5" />
        <path d="M32 21 V40" />
        <path d="M32 26 L20 22 L14 24" />
        <path d="M32 26 L44 22 L50 24" />
        <path d="M32 40 L26 56" />
        <path d="M32 40 L38 56" />
        <path d="M50 24 C 56 26 56 30 52 32" />
      </g>
    ),
    yraise: (
      <g stroke={c} strokeWidth={sw} fill="none" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="32" cy="20" r="5" />
        <path d="M20 34 L32 28 L44 34" />
        <path d="M32 28 V42" />
        <path d="M20 34 L16 20" />
        <path d="M44 34 L48 20" />
        <path d="M28 42 L26 56" />
        <path d="M36 42 L38 56" />
      </g>
    ),
    squat: (
      <g stroke={c} strokeWidth={sw} fill="none" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="32" cy="14" r="5" />
        <path d="M32 19 V32" />
        <path d="M32 32 L22 40 L22 52" />
        <path d="M32 32 L42 40 L42 52" />
        <path d="M32 24 L22 26" />
        <path d="M32 24 L42 26" />
        <path d="M18 26 H46" />
      </g>
    ),
    wallslide: (
      <g stroke={c} strokeWidth={sw} fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M52 8 V56" strokeDasharray="2 3" />
        <circle cx="32" cy="18" r="5" />
        <path d="M32 23 V42" />
        <path d="M32 28 L22 22" />
        <path d="M32 28 L42 22" />
        <path d="M22 22 L16 14" />
        <path d="M42 22 L48 14" />
        <path d="M30 42 L28 56" />
        <path d="M34 42 L36 56" />
      </g>
    ),
    pallof: (
      <g stroke={c} strokeWidth={sw} fill="none" strokeLinecap="round" strokeLinejoin="round">
        <circle cx="28" cy="18" r="5" />
        <path d="M28 23 V42" />
        <path d="M28 28 L40 30 L52 28" />
        <path d="M28 28 L22 34" />
        <path d="M26 42 L22 56" />
        <path d="M30 42 L34 56" />
        <path d="M52 28 C 56 28 56 32 52 32" />
      </g>
    ),
    deadbug: (
      <g stroke={c} strokeWidth={sw} fill="none" strokeLinecap="round" strokeLinejoin="round">
        <path d="M6 40 H58" strokeDasharray="2 3" />
        <circle cx="16" cy="36" r="5" />
        <path d="M21 36 L44 36" />
        <path d="M24 36 L30 22" />
        <path d="M38 36 L48 24" />
        <path d="M28 36 L30 48" />
        <path d="M40 36 L50 46" />
      </g>
    ),
  };
  return (
    <svg width={size} height={size} viewBox="0 0 64 64">
      {paths[kind] || paths.facepull}
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// Lucide-style icons (inline, stroke 1.75)
// ─────────────────────────────────────────────────────────────
function HDIcon({ name, size = 18, color = 'currentColor' }) {
  const sw = 1.75;
  const common = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none',
                    stroke: color, strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const icons = {
    play:    <polygon points="6 3 20 12 6 21 6 3" fill={color} stroke="none" />,
    pause:   <><rect x="6" y="4" width="4" height="16" /><rect x="14" y="4" width="4" height="16" /></>,
    plus:    <><path d="M12 5v14M5 12h14"/></>,
    minus:   <><path d="M5 12h14"/></>,
    check:   <polyline points="20 6 9 17 4 12"/>,
    chev_r:  <polyline points="9 18 15 12 9 6"/>,
    chev_d:  <polyline points="6 9 12 15 18 9"/>,
    chev_u:  <polyline points="18 15 12 9 6 15"/>,
    more:    <><circle cx="12" cy="12" r="1" fill={color}/><circle cx="19" cy="12" r="1" fill={color}/><circle cx="5" cy="12" r="1" fill={color}/></>,
    swap:    <><polyline points="17 1 21 5 17 9"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><polyline points="7 23 3 19 7 15"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/></>,
    timer:   <><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2 2"/><path d="M9 2h6"/></>,
    dumbbell:<><path d="M2 12h2"/><path d="M20 12h2"/><path d="M4 8v8"/><path d="M8 6v12"/><path d="M16 6v12"/><path d="M20 8v8"/></>,
    spark:   <><path d="M12 3v3M12 18v3M5 12H2M22 12h-3M6 6l2 2M16 16l2 2M6 18l2-2M16 8l2-2"/></>,
    mic:     <><rect x="9" y="2" width="6" height="12" rx="3"/><path d="M5 10v2a7 7 0 0 0 14 0v-2M12 19v3"/></>,
    flag:    <><path d="M4 15s1-1 4-1 5 2 8 2 4-1 4-1V3s-1 1-4 1-5-2-8-2-4 1-4 1z"/><line x1="4" y1="22" x2="4" y2="15"/></>,
    coach:   <><circle cx="12" cy="12" r="9"/><path d="M8 14s1.5 2 4 2 4-2 4-2"/><circle cx="9" cy="10" r="0.5" fill={color}/><circle cx="15" cy="10" r="0.5" fill={color}/></>,
    heart_p: <><path d="M19 14c1.5-1.5 3-3.5 3-6a4 4 0 0 0-7-2.5A4 4 0 0 0 8 5.5c0 2.5 1.5 4.5 3 6l5 5 3-2.5"/></>,
    settings:<><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z"/></>,
    x:       <><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></>,
    edit:    <><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></>,
  };
  return <svg {...common}>{icons[name]}</svg>;
}

// ─────────────────────────────────────────────────────────────
// HDTheme — wrap a subtree to override the accent palette.
// Pass { accent, wash, ribbon, ribbonLine, ink } (ink is the readable
// color on top of accent — usually near-black or white depending on
// accent luminance). All props optional; defaults to electric lime.
// ─────────────────────────────────────────────────────────────
function HDTheme({ accent, ink = '#0A0B0D', wash, ribbon, ribbonLine, children, style }) {
  // Derive washes from accent if not passed explicitly.
  // Accept hex; produce rgba by parsing.
  const hexToRgb = (h) => {
    const m = /^#?([a-f0-9]{6})$/i.exec(h);
    if (!m) return '212,255,61';
    const n = parseInt(m[1], 16);
    return `${(n >> 16) & 255},${(n >> 8) & 255},${n & 255}`;
  };
  const rgb = accent ? hexToRgb(accent) : '212,255,61';
  const computedWash = wash || `rgba(${rgb},0.05)`;
  const computedRibbon = ribbon || `linear-gradient(180deg, rgba(${rgb},0.10), rgba(${rgb},0.02))`;
  const computedRibbonLine = ribbonLine || `rgba(${rgb},0.35)`;
  const vars = {
    '--hd-accent': accent || '#D4FF3D',
    '--hd-accent-ink': ink,
    '--hd-accent-wash': computedWash,
    '--hd-accent-ribbon': computedRibbon,
    '--hd-accent-ribbon-line': computedRibbonLine,
  };
  return (
    <div style={{ ...vars, ...(style || {}) }}>
      {children}
    </div>
  );
}

Object.assign(window, { HDRole, HDFigure, HDIcon, HDTheme });
