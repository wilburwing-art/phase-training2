// hd-session-start.jsx — Minimal "what am I doing today" screen
// Shows today's workout, exercise list, and Start button.

function HDSessionStart() {
  const exercises = [
    { name: 'Bench Press', type: 'Barbell', sets: 5, info: '135→155 lb · 5 reps' },
    { name: 'Pull Up', type: null, sets: 4, info: '+25 lb · 5 reps' },
    { name: 'Overhead Press', type: 'Barbell', sets: 4, info: '100 lb · 8 reps' },
    { name: 'Incline Row', type: 'Dumbbell', sets: 4, info: '50 lb · 10 reps' },
    { name: 'Skullcrusher', type: 'Barbell', sets: 3, info: '70 lb · 10 reps' },
    { name: 'Face Pull', type: 'Cable', sets: 3, info: '30 lb · 15 reps' },
  ];
  const totalSets = exercises.reduce((n, e) => n + e.sets, 0);

  return (
    <IOSDevice dark width={402} height={874}>
      <div className="hd" style={{ height: '100%', display: 'flex', flexDirection: 'column',
                                     background: 'var(--hd-bg)', paddingTop: 54 }}>

        {/* top bar */}
        <div style={{ padding: '12px 20px 0', flexShrink: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span className="micro">SUN, MAY 11</span>
            <span className="micro">~45 MIN · {exercises.length} EX · {totalSets} SETS</span>
          </div>
          <div style={{ marginTop: 8, height: 0.5, background: 'var(--hd-line)' }}/>
        </div>

        {/* scrollable body */}
        <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>

          {/* hero */}
          <div style={{ padding: '24px 20px 0' }}>
            <div className="display" style={{ fontSize: 34, fontWeight: 600,
              letterSpacing: '-0.03em', lineHeight: 1 }}>
              Upper Body<br/>Day 1
            </div>
            <div className="ink-2" style={{ fontSize: 13, marginTop: 10, lineHeight: 1.5 }}>
              Push / pull / accessories · Week 18
            </div>
          </div>

          {/* last session summary */}
          <div style={{ padding: '20px 20px 0' }}>
            <div style={{ padding: '12px 14px', borderRadius: 12,
              background: 'var(--hd-surface)', border: '0.5px solid var(--hd-line)' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span className="micro" style={{ fontSize: 9 }}>LAST SESSION</span>
                <span className="mono ink-3" style={{ fontSize: 11 }}>4 days ago</span>
              </div>
              <div className="mono" style={{ fontSize: 12, color: 'var(--hd-ink-2)', marginTop: 6, lineHeight: 1.6 }}>
                42 min · 23 sets · avg RPE 7.1 · bench 135×5
              </div>
            </div>
          </div>

          {/* exercise list */}
          <div style={{ padding: '20px 20px 0' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                           marginBottom: 6 }}>
              <span className="micro">TODAY'S EXERCISES</span>
              <button className="btn btn-ghost" style={{ padding: 4, minWidth: 'auto',
                border: '0.5px solid var(--hd-line)', borderRadius: 8 }}>
                <HDIcon name="edit" size={13} color="var(--hd-ink-3)"/>
              </button>
            </div>

            {exercises.map((ex, i) => (
              <div key={i} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '13px 0',
                borderBottom: i < exercises.length - 1 ? '0.5px solid var(--hd-line-soft)' : 'none',
              }}>
                <span className="mono ink-3" style={{ fontSize: 11, width: 20, textAlign: 'right' }}>
                  {String(i + 1).padStart(2, '0')}
                </span>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <span className="display" style={{ fontSize: 15, fontWeight: 600 }}>{ex.name}</span>
                    {ex.type && <span className="ink-3" style={{ fontSize: 11 }}>({ex.type})</span>}
                  </div>
                  <div className="mono ink-3" style={{ fontSize: 11, marginTop: 2 }}>
                    {ex.sets} sets · {ex.info}
                  </div>
                </div>
              </div>
            ))}
          </div>

          <div style={{ height: 120 }}/>
        </div>

        {/* bottom action */}
        <div style={{ position: 'absolute', left: 20, right: 20, bottom: 46, zIndex: 20 }}>
          <button className="btn btn-primary" style={{ width: '100%', padding: '16px 20px',
            fontSize: 15, fontWeight: 700, borderRadius: 14 }}>
            <span>Start workout</span>
            <HDIcon name="chev_r" size={16} color="var(--hd-accent-ink)"/>
          </button>
        </div>
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { HDSessionStart });
