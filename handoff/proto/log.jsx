// proto/log.jsx — The core training log screen
// Scrollable, all exercises, inline inputs, rest timer, set completion.

function ScreenLog({ session, setSession, onFinish }) {
  const [restTimer, setRestTimer] = React.useState(null); // { exIdx, setIdx, remaining, total }
  const [now, setNow] = React.useState(Date.now());

  // Elapsed clock
  React.useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);

  // Rest timer countdown
  React.useEffect(() => {
    if (!restTimer || restTimer.remaining <= 0) return;
    const t = setInterval(() => {
      setRestTimer(prev => {
        if (!prev || prev.remaining <= 1) return null;
        return { ...prev, remaining: prev.remaining - 1 };
      });
    }, 1000);
    return () => clearInterval(t);
  }, [restTimer?.remaining > 0]);

  const elapsed = now - session.startTime;
  const stats = sessionStats(session);

  // Update a set field
  function updateSet(exIdx, setIdx, field, value) {
    const next = { ...session, exercises: session.exercises.map((ex, ei) => {
      if (ei !== exIdx) return ex;
      return { ...ex, sets: ex.sets.map((s, si) => {
        if (si !== setIdx) return s;
        return { ...s, [field]: value };
      })};
    })};
    setSession(next);
    saveActiveSession(next);
  }

  // Toggle set done
  function toggleSet(exIdx, setIdx) {
    const set = session.exercises[exIdx].sets[setIdx];
    const wasDone = set.done;
    updateSet(exIdx, setIdx, 'done', !wasDone);

    // Start rest timer when marking a set done (if not the last set)
    if (!wasDone) {
      const ex = session.exercises[exIdx];
      const hasMoreSets = setIdx < ex.sets.length - 1;
      if (hasMoreSets) {
        setRestTimer({ exIdx, setIdx, remaining: ex.rest, total: ex.rest });
      }
    }
  }

  // Add a set to an exercise
  function addSet(exIdx) {
    const next = { ...session, exercises: session.exercises.map((ex, ei) => {
      if (ei !== exIdx) return ex;
      const lastSet = ex.sets[ex.sets.length - 1];
      return { ...ex, sets: [...ex.sets, {
        num: ex.sets.length + 1,
        weight: lastSet?.weight || '',
        reps: lastSet?.reps || String(ex.targetReps),
        rpe: '', done: false,
      }]};
    })};
    setSession(next);
    saveActiveSession(next);
  }

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', background: PT.bg }}>
      {/* Sticky header */}
      <div style={{ padding: '10px 20px 0', flexShrink: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <PIcon name="timer" size={14} color={PT.ink3}/>
            <span style={{ fontFamily: 'JetBrains Mono', fontSize: 17, fontWeight: 500,
              fontVariantNumeric: 'tabular-nums', color: PT.ink }}>{fmtElapsed(elapsed)}</span>
          </div>
          <PBtn primary style={{ width: 'auto', padding: '8px 20px', borderRadius: 10 }}
                onClick={onFinish}>Finish</PBtn>
        </div>
        {/* progress */}
        <div style={{ marginTop: 10, marginBottom: 10, height: 3, background: PT.lineSoft,
          borderRadius: 2, position: 'relative', overflow: 'hidden' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0,
            width: `${(stats.doneSets / stats.totalSets) * 100}%`,
            background: PT.accent, borderRadius: 2, transition: 'width 0.3s ease' }}/>
        </div>
      </div>

      {/* Scrollable body */}
      <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
        {/* title */}
        <div style={{ padding: '12px 20px 8px' }}>
          <div style={{ fontFamily: 'Space Grotesk', fontSize: 24, fontWeight: 600,
            letterSpacing: '-0.03em', color: PT.ink }}>{session.name}</div>
          <div style={{ fontSize: 12, color: PT.ink3, marginTop: 4 }}>
            {session.exercises.length} exercises · {stats.doneSets}/{stats.totalSets} sets logged
          </div>
        </div>

        <div style={{ height: 0.5, background: PT.line, margin: '4px 20px 0' }}/>

        {/* Exercises */}
        {session.exercises.map((ex, exIdx) => {
          const allDone = ex.sets.every(s => s.done);
          const firstUndone = ex.sets.findIndex(s => !s.done);
          const grid = '22px 58px 1fr 1fr 34px 24px';

          return (
            <React.Fragment key={ex.id}>
              <div style={{ padding: '0 20px' }}>
                {/* exercise header */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '14px 0 6px' }}>
                  {allDone && (
                    <div style={{ width: 18, height: 18, borderRadius: 9, background: 'rgba(107,232,154,0.15)',
                      display: 'grid', placeItems: 'center', flexShrink: 0 }}>
                      <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke={PT.ok}
                           strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
                        <polyline points="20 6 9 17 4 12"/>
                      </svg>
                    </div>
                  )}
                  <span style={{ fontFamily: 'Space Grotesk', fontSize: 16, fontWeight: 600,
                    letterSpacing: '-0.02em', color: allDone ? PT.ink2 : PT.ink }}>{ex.name}</span>
                  {ex.type && <span style={{ fontSize: 11, color: PT.ink3 }}>({ex.type})</span>}
                  <div style={{ flex: 1 }}/>
                  <div style={{ padding: 4, border: `0.5px solid ${PT.line}`, borderRadius: 8,
                    cursor: 'pointer', display: 'grid', placeItems: 'center' }}>
                    <PIcon name="more" size={14} color={PT.ink3}/>
                  </div>
                </div>

                {/* column headers */}
                <div style={{ display: 'grid', gridTemplateColumns: grid, gap: 4,
                  paddingBottom: 5, borderBottom: `0.5px solid ${PT.line}` }}>
                  {['SET', 'PREV', (ex.unit || 'lbs').toUpperCase(), 'REPS', 'RPE', ''].map((h, i) => (
                    <Micro key={i} style={{ fontSize: 9, textAlign: i === 1 ? 'left' : 'center' }}>{h}</Micro>
                  ))}
                </div>

                {/* set rows */}
                {ex.sets.map((s, si) => {
                  const isActive = si === firstUndone;
                  const prevSet = ex.prevSets?.[si];
                  const prevLabel = prevSet ? `${prevSet.weight}×${prevSet.reps}` : '—';

                  return (
                    <React.Fragment key={si}>
                      <div style={{
                        display: 'grid', gridTemplateColumns: grid, gap: 4,
                        padding: '6px 0', alignItems: 'center', position: 'relative',
                      }}>
                        {isActive && <div style={{ position: 'absolute', left: -20, top: 0, bottom: 0,
                          width: 2, background: PT.accent, borderRadius: 1 }}/>}
                        <span style={{ fontFamily: 'JetBrains Mono', fontSize: 11, textAlign: 'center',
                          color: s.done ? PT.ink3 : isActive ? PT.accent : PT.ink2 }}>{s.num}</span>
                        <span style={{ fontFamily: 'JetBrains Mono', fontSize: 10.5, color: PT.ink3,
                          fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap',
                          overflow: 'hidden', textOverflow: 'ellipsis' }}>{prevLabel}</span>
                        <NumCell value={s.weight} done={s.done} active={isActive}
                          onChange={v => updateSet(exIdx, si, 'weight', v)}/>
                        <NumCell value={s.reps} done={s.done} active={isActive}
                          onChange={v => updateSet(exIdx, si, 'reps', v)}/>
                        <NumCell value={s.rpe} done={s.done} active={isActive} placeholder="—"
                          onChange={v => updateSet(exIdx, si, 'rpe', v)}/>
                        <div style={{ display: 'grid', placeItems: 'center' }}>
                          <CheckDot done={s.done} onTap={() => toggleSet(exIdx, si)}/>
                        </div>
                      </div>

                      {/* rest indicators */}
                      {s.done && ex.sets[si + 1]?.done && (
                        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '1px 0' }}>
                          <div style={{ flex: 1, height: 0.5, background: PT.lineSoft }}/>
                          <span style={{ fontFamily: 'JetBrains Mono', fontSize: 10,
                            color: PT.accentDim }}>{fmtTime(ex.rest)}</span>
                          <div style={{ flex: 1, height: 0.5, background: PT.lineSoft }}/>
                        </div>
                      )}

                      {/* active rest timer */}
                      {restTimer && restTimer.exIdx === exIdx && restTimer.setIdx === si && (
                        <div style={{
                          margin: '6px 0', padding: '10px 12px', borderRadius: 12,
                          background: PT.accentWash, border: `0.5px solid ${PT.accentBorder}`,
                          display: 'flex', alignItems: 'center', gap: 8,
                        }}>
                          <div style={{ width: 7, height: 7, borderRadius: 4, background: PT.accent,
                            animation: 'ptpulse 1.6s ease-in-out infinite' }}/>
                          <Micro accent>REST</Micro>
                          <span style={{ fontFamily: 'JetBrains Mono', fontSize: 22, fontWeight: 600,
                            color: PT.accent, fontVariantNumeric: 'tabular-nums',
                            letterSpacing: '-0.02em' }}>{fmtTime(restTimer.remaining)}</span>
                          <div style={{ flex: 1 }}/>
                          <PChip onClick={() => setRestTimer(p => p ? { ...p, remaining: p.remaining + 15 } : p)}
                            style={{ padding: '4px 8px', fontSize: 10 }}>+15</PChip>
                          <PChip onClick={() => setRestTimer(null)}
                            style={{ padding: '4px 8px', fontSize: 10 }}>skip</PChip>
                        </div>
                      )}
                    </React.Fragment>
                  );
                })}

                {/* add set */}
                <div onClick={() => addSet(exIdx)} style={{ padding: '8px 0', textAlign: 'center',
                  fontSize: 12, color: PT.ink3, cursor: 'pointer' }}>
                  + Add Set ({fmtTime(ex.rest)})
                </div>
              </div>

              {exIdx < session.exercises.length - 1 && (
                <div style={{ height: 0.5, background: PT.line, margin: '0 20px' }}/>
              )}
            </React.Fragment>
          );
        })}

        <div style={{ height: 40 }}/>
      </div>
    </div>
  );
}

// Inject keyframe for pulse
if (typeof document !== 'undefined' && !document.getElementById('pt-pulse-kf')) {
  const s = document.createElement('style');
  s.id = 'pt-pulse-kf';
  s.textContent = `@keyframes ptpulse { 0%,100% { opacity: 1; } 50% { opacity: 0.35; } }`;
  document.head.appendChild(s);
}

Object.assign(window, { ScreenLog });
