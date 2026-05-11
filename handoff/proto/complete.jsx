// proto/complete.jsx — Post-session summary screen

function ScreenComplete({ session, onSave }) {
  const [feel, setFeel] = React.useState(null);
  const [note, setNote] = React.useState('');

  const elapsed = session.endTime ? session.endTime - session.startTime : Date.now() - session.startTime;
  const stats = sessionStats(session);
  const duration = fmtElapsed(elapsed);

  // Find PRs (compare to previous)
  const prev = getPreviousSession(session.templateId);
  const prs = [];
  session.exercises.forEach(ex => {
    const prevEx = prev?.exercises?.find(e => e.id === ex.id);
    if (!prevEx) return;
    const maxW = Math.max(...ex.sets.filter(s => s.done && s.weight).map(s => Number(s.weight)));
    const prevMaxW = Math.max(...prevEx.sets.filter(s => s.weight).map(s => Number(s.weight)));
    if (maxW > prevMaxW) prs.push({ name: ex.name, diff: `+${maxW - prevMaxW} ${ex.unit}` });
  });

  function handleSave() {
    const record = {
      templateId: session.templateId,
      name: session.name,
      timestamp: session.startTime,
      duration,
      feel,
      note,
      stats,
      exercises: session.exercises.map(ex => ({
        id: ex.id, name: ex.name,
        sets: ex.sets.filter(s => s.done).map(s => ({
          weight: Number(s.weight) || 0,
          reps: Number(s.reps) || 0,
          rpe: Number(s.rpe) || 0,
        })),
      })),
    };
    const sessions = loadSessions();
    sessions.unshift(record);
    saveSessions(sessions);
    clearActiveSession();
    onSave();
  }

  const feels = ['Too easy', 'Easy', 'Right', 'Hard', 'Too much'];

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: PT.bg }}>
      {/* top bar */}
      <div style={{ padding: '12px 20px 0', flexShrink: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Micro>SESSION COMPLETE</Micro>
          <Micro>{new Date().toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' }).toUpperCase()}</Micro>
        </div>
        <div style={{ marginTop: 10, height: 3, background: PT.accent, borderRadius: 2 }}/>
      </div>

      {/* scrollable */}
      <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
        <div style={{ padding: '24px 20px 0' }}>
          <div style={{ fontFamily: 'Space Grotesk', fontSize: 34, fontWeight: 600,
            letterSpacing: '-0.03em', lineHeight: 1, color: PT.ink }}>Done.</div>
          <div style={{ fontSize: 13, color: PT.ink2, marginTop: 8 }}>{session.name}</div>
        </div>

        {/* stats */}
        <div style={{ padding: '20px 20px 0' }}>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
            {[
              { v: duration.slice(2), l: 'DURATION' },
              { v: String(stats.doneSets), l: 'SETS' },
              { v: stats.avgRpe, l: 'AVG RPE' },
            ].map((s, i) => (
              <div key={i} style={{ padding: '14px 12px', borderRadius: 12,
                background: PT.surface, border: `0.5px solid ${PT.line}` }}>
                <Micro style={{ fontSize: 9 }}>{s.l}</Micro>
                <div style={{ fontFamily: 'Space Grotesk', fontSize: 26, fontWeight: 600,
                  marginTop: 6, lineHeight: 1, color: PT.ink }}>{s.v}</div>
              </div>
            ))}
          </div>
        </div>

        {/* PRs */}
        {prs.length > 0 && (
          <div style={{ padding: '16px 20px 0' }}>
            <div style={{ padding: '12px 14px', borderRadius: 12,
              background: PT.accentWash, border: `0.5px solid ${PT.accentBorder}` }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                <PIcon name="spark" size={13} color={PT.accent}/>
                <Micro accent style={{ fontSize: 9 }}>{prs.length} PR{prs.length > 1 ? 'S' : ''} THIS SESSION</Micro>
              </div>
              <div style={{ marginTop: 8, display: 'flex', gap: 5, flexWrap: 'wrap' }}>
                {prs.map((pr, i) => (
                  <PChip key={i} active style={{ fontSize: 10 }}>
                    {pr.name.toUpperCase()} {pr.diff}
                  </PChip>
                ))}
              </div>
            </div>
          </div>
        )}

        {/* exercise summary */}
        <div style={{ padding: '20px 20px 0' }}>
          <Micro>EXERCISES</Micro>
          <div style={{ marginTop: 8 }}>
            {session.exercises.map((ex, i) => {
              const doneSets = ex.sets.filter(s => s.done);
              if (doneSets.length === 0) return null;
              const summary = doneSets.map(s => `${s.weight}×${s.reps}`).join(' · ');
              const rpes = doneSets.filter(s => s.rpe).map(s => s.rpe);
              const rpeStr = rpes.length ? `rpe ${Math.min(...rpes)}–${Math.max(...rpes)}` : '';
              return (
                <div key={ex.id} style={{ padding: '10px 0',
                  borderBottom: i < session.exercises.length - 1 ? `0.5px solid ${PT.lineSoft}` : 'none',
                  display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 10 }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <span style={{ fontFamily: 'Space Grotesk', fontSize: 14, fontWeight: 500,
                      color: PT.ink }}>{ex.name}</span>
                    <div style={{ fontFamily: 'JetBrains Mono', fontSize: 10.5, color: PT.ink3,
                      marginTop: 3 }}>{summary}</div>
                  </div>
                  {rpeStr && <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11,
                    color: PT.ink2, whiteSpace: 'nowrap', flexShrink: 0 }}>{rpeStr}</span>}
                </div>
              );
            })}
          </div>
        </div>

        {/* feel */}
        <div style={{ padding: '20px 20px 0' }}>
          <Micro>HOW DID IT FEEL?</Micro>
          <div style={{ display: 'flex', gap: 5, marginTop: 10 }}>
            {feels.map(f => (
              <PChip key={f} active={feel === f} onClick={() => setFeel(f)}
                style={{ flex: 1, justifyContent: 'center', padding: '10px 2px', fontSize: 11 }}>
                {f}
              </PChip>
            ))}
          </div>
        </div>

        {/* note */}
        <div style={{ padding: '18px 20px 0' }}>
          <Micro>NOTE (OPTIONAL)</Micro>
          <textarea value={note} onChange={e => setNote(e.target.value)}
            placeholder="Tap to add a note..."
            style={{
              marginTop: 8, width: '100%', minHeight: 56, padding: '12px 14px', borderRadius: 12,
              background: PT.surface, border: `0.5px solid ${PT.line}`, resize: 'vertical',
              fontFamily: 'Inter', fontSize: 13, color: PT.ink, lineHeight: 1.45,
              outline: 'none', boxSizing: 'border-box',
            }}/>
        </div>

        <div style={{ height: 120 }}/>
      </div>

      {/* save */}
      <div style={{ position: 'absolute', left: 20, right: 20, bottom: 46, zIndex: 20 }}>
        <PBtn primary onClick={handleSave}>
          <span>Save session</span>
          <PIcon name="check" size={16} color={PT.accentInk}/>
        </PBtn>
      </div>
    </div>
  );
}

Object.assign(window, { ScreenComplete });
