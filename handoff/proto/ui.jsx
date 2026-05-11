// proto/ui.jsx — Shared UI components for the prototype
// Tiny, reusable bits: icons, chips, cells, etc.

/* ── Color tokens (inline, no CSS vars needed) ── */
const PT = {
  bg: '#0A0B0D', surface: '#14161A', elevated: '#1C1F24',
  line: '#2A2E35', lineSoft: '#1F2229',
  ink: '#F5F5F0', ink2: '#B5B7BD', ink3: '#7A7D85',
  accent: '#D4FF3D', accentInk: '#0A0B0D', accentDim: '#8FA82A',
  accentWash: 'rgba(212,255,61,0.04)', accentBorder: 'rgba(212,255,61,0.30)',
  ok: '#6BE89A', danger: '#FF6B4A',
};

/* ── Icon (minimal inline SVGs) ── */
function PIcon({ name, size = 18, color = 'currentColor' }) {
  const p = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none',
    stroke: color, strokeWidth: 1.75, strokeLinecap: 'round', strokeLinejoin: 'round' };
  const icons = {
    check:   <polyline points="20 6 9 17 4 12"/>,
    chevR:   <polyline points="9 18 15 12 9 6"/>,
    chevD:   <polyline points="6 9 12 15 18 9"/>,
    chevU:   <polyline points="18 15 12 9 6 15"/>,
    x:       <><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></>,
    plus:    <><path d="M12 5v14M5 12h14"/></>,
    minus:   <><path d="M5 12h14"/></>,
    more:    <><circle cx="12" cy="12" r="1" fill={color}/><circle cx="19" cy="12" r="1" fill={color}/><circle cx="5" cy="12" r="1" fill={color}/></>,
    timer:   <><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2 2"/><path d="M9 2h6"/></>,
    edit:    <><path d="M12 20h9"/><path d="M16.5 3.5a2.121 2.121 0 0 1 3 3L7 19l-4 1 1-4L16.5 3.5z"/></>,
    spark:   <><path d="M12 3v3M12 18v3M5 12H2M22 12h-3M6 6l2 2M16 16l2 2M6 18l2-2M16 8l2-2"/></>,
    history: <><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></>,
  };
  return <svg {...p}>{icons[name]}</svg>;
}

/* ── Micro label ── */
function Micro({ children, style, accent }) {
  return (
    <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '0.14em',
      textTransform: 'uppercase', fontWeight: 500, color: accent ? PT.accent : PT.ink3, ...style }}>
      {children}
    </span>
  );
}

/* ── Trend arrow ── */
function Trend({ dir }) {
  const m = { up: ['↑', PT.ok], flat: ['→', PT.ink3], down: ['↓', PT.danger] };
  const [g, c] = m[dir] || m.flat;
  return <span style={{ fontFamily: 'JetBrains Mono', fontSize: 12, color: c, fontWeight: 700 }}>{g}</span>;
}

/* ── Green check circle ── */
function CheckDot({ done, size = 22, onTap }) {
  if (done) return (
    <div onClick={onTap} style={{ width: size, height: size, borderRadius: size / 2,
      background: PT.ok, display: 'grid', placeItems: 'center', cursor: 'pointer', flexShrink: 0 }}>
      <svg width={size * 0.5} height={size * 0.5} viewBox="0 0 24 24" fill="none"
           stroke={PT.bg} strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="20 6 9 17 4 12"/>
      </svg>
    </div>
  );
  return (
    <div onClick={onTap} style={{ width: size, height: size, borderRadius: size / 2,
      border: `1.5px solid ${PT.line}`, cursor: 'pointer', flexShrink: 0 }}/>
  );
}

/* ── Button ── */
function PBtn({ children, primary, style, onClick, disabled }) {
  return (
    <button onClick={onClick} disabled={disabled} style={{
      display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
      padding: primary ? '16px 20px' : '10px 16px',
      borderRadius: 14, border: primary ? 'none' : `0.5px solid ${PT.line}`,
      background: primary ? PT.accent : PT.elevated,
      color: primary ? PT.accentInk : PT.ink,
      fontFamily: 'Inter, sans-serif', fontWeight: primary ? 700 : 500,
      fontSize: primary ? 15 : 13, cursor: 'pointer',
      opacity: disabled ? 0.4 : 1, width: '100%',
      letterSpacing: '-0.01em', ...style,
    }}>
      {children}
    </button>
  );
}

/* ── Chip ── */
function PChip({ children, active, onClick, style }) {
  return (
    <span onClick={onClick} style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      padding: '4px 10px', borderRadius: 999,
      fontSize: 11, fontWeight: 500, cursor: onClick ? 'pointer' : 'default',
      fontFamily: 'JetBrains Mono, monospace', letterSpacing: '0.02em',
      background: active ? PT.accent : PT.elevated,
      color: active ? PT.accentInk : PT.ink2,
      border: `0.5px solid ${active ? PT.accent : PT.line}`,
      ...style,
    }}>
      {children}
    </span>
  );
}

/* ── Number input cell ── */
function NumCell({ value, onChange, active, done, placeholder = '—', width }) {
  if (done) return (
    <div style={{ textAlign: 'center', fontFamily: 'JetBrains Mono', fontSize: 13.5,
      color: PT.ink2, fontVariantNumeric: 'tabular-nums', padding: '6px 0' }}>{value || placeholder}</div>
  );
  return (
    <input
      type="text" inputMode="decimal" value={value} placeholder={placeholder}
      onChange={e => onChange(e.target.value)}
      style={{
        width: width || '100%', padding: '7px 2px', borderRadius: 7, textAlign: 'center',
        fontFamily: 'JetBrains Mono', fontSize: 13.5, fontWeight: 500,
        fontVariantNumeric: 'tabular-nums', outline: 'none', boxSizing: 'border-box',
        background: active ? 'rgba(212,255,61,0.06)' : PT.elevated,
        border: `0.5px solid ${active ? PT.accentBorder : PT.line}`,
        color: active ? PT.accent : PT.ink,
      }}
    />
  );
}

/* ── Format seconds as M:SS ── */
function fmtTime(sec) {
  const m = Math.floor(sec / 60);
  const s = sec % 60;
  return `${m}:${String(s).padStart(2, '0')}`;
}

/* ── Format elapsed as H:MM:SS ── */
function fmtElapsed(ms) {
  const sec = Math.floor(ms / 1000);
  const h = Math.floor(sec / 3600);
  const m = Math.floor((sec % 3600) / 60);
  const s = sec % 60;
  return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
}

Object.assign(window, {
  PT, PIcon, Micro, Trend, CheckDot, PBtn, PChip, NumCell, fmtTime, fmtElapsed,
});
