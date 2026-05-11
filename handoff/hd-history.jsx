// hd-history.jsx — Session history list + detail
// Minimal: list of past sessions, tap to expand and see sets.
// This is what makes the "Previous" column meaningful.

function HDHistory() {
  const sessions = [
    {
      date: 'Wed, May 7',
      name: 'Upper Body Day 1',
      time: '42 min', sets: 23, rpe: '7.1',
      ago: '4 days ago',
      exercises: [
        { n: 'Bench Press', detail: '135×5 · 135×5 · 135×5 · 135×5 · 135×5', rpe: '6–7' },
        { n: 'Pull Up', detail: '+25×5 · +25×5 · +25×5 · +25×4', rpe: '6–8' },
        { n: 'Overhead Press', detail: '95×8 · 95×8 · 95×8 · 95×7', rpe: '6–7' },
        { n: 'Incline Row', detail: '50×10 · 50×10 · 50×10 · 50×10', rpe: '6–7' },
        { n: 'Skullcrusher', detail: '65×10 · 65×10 · 65×10', rpe: '7' },
        { n: 'Face Pull', detail: '30×15 · 30×15 · 30×15', rpe: '5–6' },
      ],
      expanded: true,
    },
    {
      date: 'Mon, May 5',
      name: 'Lower Body Day 1',
      time: '38 min', sets: 18, rpe: '7.4',
      ago: '6 days ago',
      exercises: [
        { n: 'Back Squat', detail: '185×5 · 195×5 · 205×5 · 205×4', rpe: '7–9' },
        { n: 'Romanian DL', detail: '155×8 · 155×8 · 155×8', rpe: '7' },
        { n: 'Walking Lunge', detail: '40×10 · 40×10 · 40×10', rpe: '6–7' },
        { n: 'Leg Curl', detail: '80×12 · 80×12 · 80×10', rpe: '7' },
        { n: 'Calf Raise', detail: '135×15 · 135×15 · 135×15', rpe: '5–6' },
      ],
    },
    {
      date: 'Sat, May 3',
      name: 'Upper Body Day 2',
      time: '40 min', sets: 20, rpe: '6.8',
      ago: '8 days ago',
    },
    {
      date: 'Thu, May 1',
      name: 'Lower Body Day 2',
      time: '35 min', sets: 16, rpe: '7.0',
      ago: '10 days ago',
    },
    {
      date: 'Tue, Apr 29',
      name: 'Upper Body Day 1',
      time: '44 min', sets: 23, rpe: '6.9',
      ago: '12 days ago',
    },
    {
      date: 'Sun, Apr 27',
      name: 'Lower Body Day 1',
      time: '36 min', sets: 18, rpe: '7.2',
      ago: '14 days ago',
    },
  ];

  return (
    <IOSDevice dark width={402} height={874}>
      <div className="hd" style={{ height: '100%', display: 'flex', flexDirection: 'column',
                                     background: 'var(--hd-bg)', paddingTop: 54 }}>

        {/* header */}
        <div style={{ padding: '12px 20px 0', flexShrink: 0 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <span className="micro">HISTORY</span>
            <span className="micro">WEEK 18</span>
          </div>
          <div style={{ marginTop: 8, height: 0.5, background: 'var(--hd-line)' }}/>
        </div>

        {/* scrollable */}
        <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>

          {/* title */}
          <div style={{ padding: '20px 20px 0' }}>
            <div className="display" style={{ fontSize: 26, fontWeight: 600,
              letterSpacing: '-0.03em', lineHeight: 1.05 }}>
              Past sessions
            </div>
            <div className="ink-3" style={{ fontSize: 12, marginTop: 5 }}>
              {sessions.length} sessions · last 2 weeks
            </div>
          </div>

          {/* week summary strip */}
          <div style={{ padding: '16px 20px 0' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 8 }}>
              {[
                { v: '6', l: 'SESSIONS' },
                { v: '138', l: 'TOTAL SETS' },
                { v: '7.1', l: 'AVG RPE' },
              ].map((s, i) => (
                <div key={i} style={{ padding: '10px 12px', borderRadius: 10,
                  background: 'var(--hd-surface)', border: '0.5px solid var(--hd-line)',
                  textAlign: 'center' }}>
                  <div className="display" style={{ fontSize: 20, fontWeight: 600, lineHeight: 1 }}>{s.v}</div>
                  <div className="micro" style={{ fontSize: 9, marginTop: 4 }}>{s.l}</div>
                </div>
              ))}
            </div>
          </div>

          <div style={{ height: 0.5, background: 'var(--hd-line)', margin: '16px 20px 0' }}/>

          {/* session list */}
          <div style={{ padding: '0 20px' }}>
            {sessions.map((sess, i) => (
              <div key={i} style={{
                padding: '14px 0',
                borderBottom: i < sessions.length - 1 ? '0.5px solid var(--hd-line-soft)' : 'none',
              }}>
                {/* session header row */}
                <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
                      <span className="display" style={{ fontSize: 16, fontWeight: 600 }}>{sess.name}</span>
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 4 }}>
                      <span className="mono ink-3" style={{ fontSize: 11 }}>{sess.date}</span>
                      <span className="ink-3" style={{ fontSize: 10 }}>·</span>
                      <span className="mono ink-3" style={{ fontSize: 11 }}>{sess.time}</span>
                      <span className="ink-3" style={{ fontSize: 10 }}>·</span>
                      <span className="mono ink-3" style={{ fontSize: 11 }}>{sess.sets} sets</span>
                      <span className="ink-3" style={{ fontSize: 10 }}>·</span>
                      <span className="mono ink-3" style={{ fontSize: 11 }}>rpe {sess.rpe}</span>
                    </div>
                  </div>
                  <HDIcon name={sess.expanded ? 'chev_u' : 'chev_d'} size={14} color="var(--hd-ink-3)"/>
                </div>

                {/* expanded exercise detail */}
                {sess.expanded && sess.exercises && (
                  <div style={{ marginTop: 10, padding: '10px 12px', borderRadius: 10,
                    background: 'var(--hd-surface)', border: '0.5px solid var(--hd-line)' }}>
                    {sess.exercises.map((ex, j) => (
                      <div key={j} style={{
                        padding: '8px 0',
                        borderBottom: j < sess.exercises.length - 1 ? '0.5px solid var(--hd-line-soft)' : 'none',
                      }}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                          <span style={{ fontSize: 13, fontWeight: 500, color: 'var(--hd-ink)' }}>{ex.n}</span>
                          <span className="mono ink-3" style={{ fontSize: 10.5, flexShrink: 0 }}>rpe {ex.rpe}</span>
                        </div>
                        <div className="mono ink-2" style={{ fontSize: 11, marginTop: 3 }}>{ex.detail}</div>
                      </div>
                    ))}
                  </div>
                )}

                {/* collapsed: second session has exercise names inline */}
                {!sess.expanded && sess.exercises && (
                  <div className="mono ink-3" style={{ fontSize: 10.5, marginTop: 6, lineHeight: 1.5 }}>
                    {sess.exercises.map(e => e.n).join(' · ')}
                  </div>
                )}
              </div>
            ))}
          </div>

          <div style={{ height: 40 }}/>
        </div>
      </div>
    </IOSDevice>
  );
}

Object.assign(window, { HDHistory });
