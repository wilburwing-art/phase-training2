// proto/start.jsx — Session Start screen
// Pick workout, see last session, start.

function ScreenStart({ onStart }) {
  const tmpl = WORKOUT_TEMPLATES['upper-1'];
  const prev = getPreviousSession('upper-1');
  const totalSets = tmpl.exercises.reduce((n, e) => n + e.targetSets, 0);

  const prevLabel = prev
    ? `${Math.round((Date.now() - prev.timestamp) / 86400000)} days ago · ${prev.duration} · ${prev.stats.doneSets} sets`
    : 'No previous session';

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: PT.bg }}>
      {/* top bar */}
      <div style={{ padding: '12px 20px 0', flexShrink: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Micro>{new Date().toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).toUpperCase()}</Micro>
          <Micro>~45 MIN · {tmpl.exercises.length} EX · {totalSets} SETS</Micro>
        </div>
        <div style={{ marginTop: 8, height: 0.5, background: PT.line }}/>
      </div>

      {/* scrollable */}
      <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
        {/* hero */}
        <div style={{ padding: '24px 20px 0' }}>
          <div style={{ fontFamily: 'Space Grotesk, sans-serif', fontSize: 34, fontWeight: 600,
            letterSpacing: '-0.03em', lineHeight: 1, color: PT.ink }}>
            Upper Body<br/>Day 1
          </div>
          <div style={{ fontSize: 13, marginTop: 10, color: PT.ink2, lineHeight: 1.5 }}>
            {tmpl.category} · Week 18
          </div>
        </div>

        {/* last session */}
        <div style={{ padding: '20px 20px 0' }}>
          <div style={{ padding: '12px 14px', borderRadius: 12,
            background: PT.surface, border: `0.5px solid ${PT.line}` }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
              <Micro>LAST SESSION</Micro>
              <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink3 }}>
                {prev ? `${Math.round((Date.now() - prev.timestamp) / 86400000)}d ago` : '—'}
              </span>
            </div>
            <div style={{ fontFamily: 'JetBrains Mono', fontSize: 12, color: PT.ink2,
              marginTop: 6, lineHeight: 1.6 }}>
              {prev ? `${prev.duration} · ${prev.stats.doneSets} sets · avg rpe ${prev.stats.avgRpe}` : 'First time — weights will be empty'}
            </div>
          </div>
        </div>

        {/* exercise list */}
        <div style={{ padding: '20px 20px 0' }}>
          <Micro>TODAY'S EXERCISES</Micro>
          <div style={{ marginTop: 8 }}>
            {tmpl.exercises.map((ex, i) => {
              const prevEx = prev?.exercises?.find(e => e.id === ex.id);
              const prevW = prevEx?.sets?.[0]?.weight;
              return (
                <div key={ex.id} style={{
                  display: 'flex', alignItems: 'center', gap: 12, padding: '13px 0',
                  borderBottom: i < tmpl.exercises.length - 1 ? `0.5px solid ${PT.lineSoft}` : 'none',
                }}>
                  <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink3,
                    width: 20, textAlign: 'right' }}>
                    {String(i + 1).padStart(2, '0')}
                  </span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                      <span style={{ fontFamily: 'Space Grotesk', fontSize: 15, fontWeight: 600,
                        color: PT.ink }}>{ex.name}</span>
                      {ex.type && <span style={{ fontSize: 11, color: PT.ink3 }}>({ex.type})</span>}
                    </div>
                    <div style={{ fontFamily: 'JetBrains Mono', fontSize: 11, color: PT.ink3, marginTop: 2 }}>
                      {ex.targetSets} sets · {prevW ? `${prevW} ${ex.unit}` : 'no prev'} · {ex.targetReps} reps
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>

        <div style={{ height: 120 }}/>
      </div>

      {/* CTA */}
      <div style={{ position: 'absolute', left: 20, right: 20, bottom: 46, zIndex: 20 }}>
        <PBtn primary onClick={onStart}>
          <span>Start workout</span>
          <PIcon name="chevR" size={16} color={PT.accentInk}/>
        </PBtn>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenStart });
