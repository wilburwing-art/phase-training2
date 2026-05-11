// proto/history.jsx — Past sessions list

function ScreenHistory({ onBack }) {
  const sessions = loadSessions();
  const [expanded, setExpanded] = React.useState(sessions.length > 0 ? 0 : -1);

  const totalSets = sessions.reduce((n, s) => n + (s.stats?.doneSets || 0), 0);
  const avgRpe = sessions.length
    ? (sessions.reduce((n, s) => n + (parseFloat(s.stats?.avgRpe) || 0), 0) / sessions.length).toFixed(1)
    : '—';

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: PT.bg }}>
      {/* header */}
      <div style={{ padding: '12px 20px 0', flexShrink: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div onClick={onBack} style={{ cursor: 'pointer', padding: 4 }}>
              <PIcon name="chevR" size={16} color={PT.ink2}
                     style={{ transform: 'rotate(180deg)' }}/>
            </div>
            <Micro>HISTORY</Micro>
          </div>
          <Micro>{sessions.length} SESSION{sessions.length !== 1 ? 'S' : ''}</Micro>
        </div>
        <div style={{ marginTop: 8, height: 0.5, background: PT.line }}/>
      </div>

      <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
        {/* title */}
        <div style={{ padding: '20px 20px 0' }}>
          <div style={{ fontFamily: 'Space Grotesk', fontSize: 26, fontWeight: 600,
            letterSpacing: '-0.03em', lineHeight: 1.05, color: PT.ink }}>Past sessions</div>
        </div>

        {/* summary strip */}
        {sessions.length > 0 && (
          <div style={{ padding: '16px 20px 0' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
              {[
                { v: String(sessions.length), l: 'SESSIONS' },
                { v: String(totalSets), l: 'TOTAL SETS' },
                { v: avgRpe, l: 'AVG RPE' },
              ].map((s, i) => (
                <div key={i} style={{ padding: '10px 12px', borderRadius: 10,
                  background: PT.surface, border: `0.5px solid ${PT.line}`, textAlign: 'center' }}>
                  <div style={{ fontFamily: 'Space Grotesk', fontSize: 20, fontWeight: 600,
                    lineHeight: 1, color: PT.ink }}>{s.v}</div>
                  <Micro style={{ fontSize: 9, marginTop: 4, display: 'block' }}>{s.l}</Micro>
                </div>
              ))}
            </div>
          </div>
        )}

        <div style={{ height: 0.5, background: PT.line, margin: '16px 20px 0' }}/>

        {/* empty state */}
        {sessions.length === 0 && (
          <div style={{ padding: '40px 20px', textAlign: 'center' }}>
            <PIcon name="history" size={32} color={PT.ink3}/>
            <div style={{ fontFamily: 'Space Grotesk', fontSize: 18, fontWeight: 600,
              color: PT.ink2, marginTop: 12 }}>No sessions yet</div>
            <div style={{ fontSize: 13, color: PT.ink3, marginTop: 6 }}>
              Complete a workout and it'll show up here.
            </div>
          </div>
        )}

        {/* session list */}
        <div style={{ padding: '0 20px' }}>
          {sessions.map((sess, i) => {
            const isExpanded = expanded === i;
            const ago = Math.round((Date.now() - sess.timestamp) / 86400000);
            const agoStr = ago === 0 ? 'today' : ago === 1 ? 'yesterday' : `${ago}d ago`;

            return (
              <div key={i} style={{ padding: '14px 0',
                borderBottom: i < sessions.length - 1 ? `0.5px solid ${PT.lineSoft}` : 'none' }}>
                {/* row */}
                <div onClick={() => setExpanded(isExpanded ? -1 : i)}
                  style={{ display: 'flex', alignItems: 'center', gap: 10, cursor: 'pointer' }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <span style={{ fontFamily: 'Space Grotesk', fontSize: 16, fontWeight: 600,
                      color: PT.ink }}>{sess.name}</span>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4,
                      flexWrap: 'wrap' }}>
                      <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink3 }}>
                        {new Date(sess.timestamp).toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' })}
                      </span>
                      <span style={{ fontSize: 10, color: PT.ink3 }}>·</span>
                      <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink3 }}>{sess.duration}</span>
                      <span style={{ fontSize: 10, color: PT.ink3 }}>·</span>
                      <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink3 }}>{sess.stats?.doneSets || 0} sets</span>
                      <span style={{ fontSize: 10, color: PT.ink3 }}>·</span>
                      <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink3 }}>rpe {sess.stats?.avgRpe || '—'}</span>
                    </div>
                  </div>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={PT.ink3}
                    strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round"
                    style={{ flexShrink: 0, transform: isExpanded ? 'rotate(180deg)' : 'none',
                      transition: 'transform 0.2s ease' }}>
                    <polyline points="6 9 12 15 18 9"/>
                  </svg>
                </div>

                {/* expanded detail */}
                {isExpanded && sess.exercises && (
                  <div style={{ marginTop: 10, padding: '10px 12px', borderRadius: 10,
                    background: PT.surface, border: `0.5px solid ${PT.line}` }}>
                    {sess.exercises.map((ex, j) => {
                      const setStr = ex.sets.map(s => `${s.weight}×${s.reps}`).join(' · ');
                      const rpes = ex.sets.filter(s => s.rpe).map(s => s.rpe);
                      const rpeStr = rpes.length
                        ? `rpe ${Math.min(...rpes)}${rpes.length > 1 ? '–' + Math.max(...rpes) : ''}`
                        : '';
                      return (
                        <div key={j} style={{ padding: '8px 0',
                          borderBottom: j < sess.exercises.length - 1 ? `0.5px solid ${PT.lineSoft}` : 'none' }}>
                          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                            <span style={{ fontSize: 13, fontWeight: 500, color: PT.ink }}>{ex.name}</span>
                            {rpeStr && <span style={{ fontFamily: 'JetBrains Mono', fontSize: 10.5,
                              color: PT.ink3, flexShrink: 0 }}>{rpeStr}</span>}
                          </div>
                          <div style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink2,
                            marginTop: 3 }}>{setStr || '—'}</div>
                        </div>
                      );
                    })}
                  </div>
                )}
              </div>
            );
          })}
        </div>

        <div style={{ height: 40 }}/>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenHistory });
