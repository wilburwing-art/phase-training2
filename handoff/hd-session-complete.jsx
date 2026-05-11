// hd-session-complete.jsx — Post-workout summary, save & close
// Minimal: time, sets, PRs, overall feel, save.

function HDSessionComplete() {
  const stats = [
    { v: '42:08', l: 'DURATION' },
    { v: '23', l: 'SETS' },
    { v: '7.1', l: 'AVG RPE' },
  ];

  const exercises = [
    { n: 'Bench Press', s: '135→155 × 5 · 5 sets', rpe: '6–9', pr: true },
    { n: 'Pull Up', s: '+25 × 5 · 4 sets', rpe: '6–8' },
    { n: 'Overhead Press', s: '100 × 8 · 4 sets', rpe: '6–7' },
    { n: 'Incline Row', s: '50 × 10 · 4 sets', rpe: '6–7' },
    { n: 'Skullcrusher', s: '70 × 10 · 3 sets', rpe: '7–8' },
    { n: 'Face Pull', s: '30 × 15 · 3 sets', rpe: '5–6' },
  ];

  return (
    <IOSDevice dark width={402} height={874}>
      <div className="hd" style={{ height: '100%', display: 'flex', flexDirection: 'column',
                                     background: 'var(--hd-bg)', paddingTop: 54 }}>

        {/* top bar */}
        <div style={{ padding: '12px 20px 0', flexShrink: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span className="micro">SESSION COMPLETE</span>
            <span className="micro">SUN, MAY 11</span>
          </div>
          {/* full progress bar */}
          <div style={{ marginTop: 10, height: 3, background: 'var(--hd-accent)', borderRadius: 2 }}/>
        </div>

        {/* scrollable */}
        <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>

          {/* hero */}
          <div style={{ padding: '24px 20px 0' }}>
            <div className="display" style={{ fontSize: 34, fontWeight: 600,
              letterSpacing: '-0.03em', lineHeight: 1 }}>
              Done.
            </div>
            <div className="ink-2" style={{ fontSize: 13, marginTop: 8 }}>
              Upper Body Day 1 · Week 18
            </div>
          </div>

          {/* stat blocks */}
          <div style={{ padding: '20px 20px 0' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
              {stats.map((s, i) => (
                <div key={i} style={{ padding: '14px 12px', borderRadius: 12,
                  background: 'var(--hd-surface)', border: '0.5px solid var(--hd-line)' }}>
                  <div className="micro" style={{ fontSize: 9 }}>{s.l}</div>
                  <div className="display" style={{ fontSize: 26, fontWeight: 600,
                    marginTop: 6, lineHeight: 1 }}>{s.v}</div>
                </div>
              ))}
            </div>
          </div>

          {/* PR ribbon */}
          <div style={{ padding: '16px 20px 0' }}>
            <div style={{ padding: '12px 14px', borderRadius: 12,
              background: 'var(--hd-accent-wash)',
              border: '0.5px solid rgba(212,255,61,0.30)' }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <HDIcon name="spark" size={13} color="var(--hd-accent)"/>
                <span className="micro" style={{ color: 'var(--hd-accent)', fontSize: 9 }}>
                  1 PR THIS SESSION
                </span>
              </div>
              <div style={{ marginTop: 8, display: 'flex', gap: 5 }}>
                <span className="chip chip-accent" style={{ fontSize: 10 }}>BENCH +20 LB TOP SET</span>
                <span className="chip" style={{ fontSize: 10 }}>VOL +12% WoW</span>
              </div>
            </div>
          </div>

          {/* exercise summary */}
          <div style={{ padding: '20px 20px 0' }}>
            <span className="micro">EXERCISES</span>
            <div style={{ marginTop: 8 }}>
              {exercises.map((ex, i) => (
                <div key={i} style={{
                  padding: '10px 0',
                  borderBottom: i < exercises.length - 1 ? '0.5px solid var(--hd-line-soft)' : 'none',
                  display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10,
                }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span className="display" style={{ fontSize: 14, fontWeight: 500 }}>{ex.n}</span>
                      {ex.pr && (
                        <span className="chip chip-accent" style={{ fontSize: 9, padding: '1px 6px' }}>PR</span>
                      )}
                    </div>
                    <div className="mono ink-3" style={{ fontSize: 10.5, marginTop: 3 }}>{ex.s}</div>
                  </div>
                  <span className="mono ink-2" style={{ fontSize: 11, whiteSpace: 'nowrap',
                    flexShrink: 0 }}>rpe {ex.rpe}</span>
                </div>
              ))}
            </div>
          </div>

          {/* overall feel */}
          <div style={{ padding: '20px 20px 0' }}>
            <span className="micro">HOW DID IT FEEL?</span>
            <div style={{ display: 'flex', gap: 5, marginTop: 10 }}>
              {['Too easy', 'Easy', 'Right', 'Hard', 'Too much'].map((t, i) => {
                const active = t === 'Right';
                return (
                  <div key={i} className={active ? 'chip chip-accent' : 'chip'}
                       style={{ flex: 1, textAlign: 'center', padding: '10px 2px',
                                 display: 'flex', justifyContent: 'center', fontSize: 11 }}>
                    {t}
                  </div>
                );
              })}
            </div>
          </div>

          {/* note */}
          <div style={{ padding: '18px 20px 0' }}>
            <span className="micro">NOTE (OPTIONAL)</span>
            <div style={{
              marginTop: 8, padding: '12px 14px', borderRadius: 12,
              background: 'var(--hd-surface)', border: '0.5px solid var(--hd-line)',
              minHeight: 48, fontSize: 13, color: 'var(--hd-ink-3)', lineHeight: 1.45,
            }}>
              Tap to add a note...
            </div>
          </div>

          <div style={{ height: 120 }}/>
        </div>

        {/* save button */}
        <div style={{ position: 'absolute', left: 20, right: 20, bottom: 46, zIndex: 20 }}>
          <button className="btn btn-primary" style={{ width: '100%', padding: '16px 20px',
            fontSize: 15, fontWeight: 700, borderRadius: 14 }}>
            <span>Save session</span>
            <HDIcon name="check" size={16} color="var(--hd-accent-ink)"/>
          </button>
        </div>
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { HDSessionComplete });
