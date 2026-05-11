// hd-training-log.jsx — Daily Training Log (one scrollable page)
// Depends: hd-style.jsx (HDIcon, .hd classes), ios-frame.jsx (IOSDevice)

/* ═══ Tiny helpers ══════════════════════════════════════════ */

function TLTrend({ dir }) {
  const m = { up:['↑','var(--hd-ok)'], flat:['→','var(--hd-ink-3)'], down:['↓','var(--hd-danger)'] };
  const [g, c] = m[dir] || m.flat;
  return <span className="mono" style={{ fontSize: 12, color: c, fontWeight: 700 }}>{g}</span>;
}

function TLCheck({ done }) {
  return done ? (
    <div style={{ width: 22, height: 22, borderRadius: 11, background: '#6BE89A',
                   display: 'grid', placeItems: 'center', flexShrink: 0 }}>
      <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="#0A0B0D"
           strokeWidth="3.5" strokeLinecap="round" strokeLinejoin="round">
        <polyline points="20 6 9 17 4 12"/>
      </svg>
    </div>
  ) : (
    <div style={{ width: 22, height: 22, borderRadius: 11, border: '1.5px solid var(--hd-line)',
                   flexShrink: 0 }}/>
  );
}

/* editable-looking value cell */
function TLVal({ v, done, active }) {
  if (done) return (
    <div style={{ textAlign: 'center', fontFamily: 'JetBrains Mono', fontSize: 13.5,
                   color: 'var(--hd-ink-2)', fontVariantNumeric: 'tabular-nums',
                   padding: '6px 0' }}>{v}</div>
  );
  return (
    <div style={{
      padding: '6px 2px', borderRadius: 7, textAlign: 'center',
      fontFamily: 'JetBrains Mono', fontSize: 13.5, fontWeight: 500,
      fontVariantNumeric: 'tabular-nums',
      background: active ? 'rgba(212,255,61,0.06)' : 'var(--hd-elevated)',
      border: `0.5px solid ${active ? 'rgba(212,255,61,0.30)' : 'var(--hd-line)'}`,
      color: active ? 'var(--hd-accent)' : 'var(--hd-ink)',
    }}>{v || '—'}</div>
  );
}

/* thin rest divider between two completed sets */
function TLRest({ t }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '1px 0' }}>
      <div style={{ flex: 1, height: 0.5, background: 'var(--hd-line-soft)' }}/>
      <span className="mono" style={{ fontSize: 10, color: 'var(--hd-accent-dim)',
                                        letterSpacing: '0.04em' }}>{t}</span>
      <div style={{ flex: 1, height: 0.5, background: 'var(--hd-line-soft)' }}/>
    </div>
  );
}

/* live rest-timer card (appears after last completed set) */
function TLActiveRest() {
  return (
    <div style={{
      margin: '6px 0', padding: '10px 12px', borderRadius: 12,
      background: 'var(--hd-accent-wash)', border: '0.5px solid rgba(212,255,61,0.30)',
      display: 'flex', alignItems: 'center', gap: 8,
    }}>
      <div className="pulse" style={{ width: 7, height: 7, borderRadius: 4,
                                        background: 'var(--hd-accent)' }}/>
      <span className="micro" style={{ color: 'var(--hd-accent)', fontSize: 9 }}>REST</span>
      <span style={{ fontFamily: 'JetBrains Mono', fontSize: 22, fontWeight: 600,
                      color: 'var(--hd-accent)', fontVariantNumeric: 'tabular-nums',
                      letterSpacing: '-0.02em' }}>1:15</span>
      <div style={{ flex: 1 }}/>
      <div style={{ display: 'flex', gap: 4 }}>
        <span className="chip" style={{ padding: '4px 8px', fontSize: 10 }}>−15</span>
        <span className="chip" style={{ padding: '4px 8px', fontSize: 10 }}>+15</span>
        <span className="chip" style={{ padding: '4px 8px', fontSize: 10 }}>skip</span>
      </div>
    </div>
  );
}

/* ═══ Exercise block ════════════════════════════════════════ */

const COL = '22px 60px 1fr 1fr 34px 24px';

function TLExercise({ name, type, trend, unit, rest, sets, resting }) {
  const allDone = sets.every(s => s.done);
  return (
    <div style={{ padding: '0 20px' }}>
      {/* header */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, padding: '14px 0 6px' }}>
        {allDone && (
          <div style={{ width: 18, height: 18, borderRadius: 9, background: 'rgba(107,232,154,0.15)',
                         display: 'grid', placeItems: 'center', flexShrink: 0 }}>
            <svg width="10" height="10" viewBox="0 0 24 24" fill="none" stroke="#6BE89A"
                 strokeWidth="3" strokeLinecap="round" strokeLinejoin="round">
              <polyline points="20 6 9 17 4 12"/>
            </svg>
          </div>
        )}
        <span className="display" style={{ fontSize: 16, fontWeight: 600, letterSpacing: '-0.02em',
          color: allDone ? 'var(--hd-ink-2)' : 'var(--hd-ink)' }}>{name}</span>
        {type && <span className="ink-3" style={{ fontSize: 11 }}>({type})</span>}
        <TLTrend dir={trend}/>
        <div style={{ flex: 1 }}/>
        <button className="btn btn-ghost" style={{ padding: 4, minWidth: 'auto',
          border: '0.5px solid var(--hd-line)', borderRadius: 8 }}>
          <HDIcon name="more" size={14} color="var(--hd-ink-3)"/>
        </button>
      </div>

      {/* column headers */}
      <div style={{ display: 'grid', gridTemplateColumns: COL, gap: 4,
                     paddingBottom: 5, borderBottom: '0.5px solid var(--hd-line)' }}>
        {['SET','PREV', (unit || 'lbs').toUpperCase(), 'REPS', 'RPE', ''].map((h, i) => (
          <span key={i} className="micro"
                style={{ fontSize: 9, textAlign: i === 1 ? 'left' : 'center' }}>{h}</span>
        ))}
      </div>

      {/* set rows */}
      {sets.map((s, i) => (
        <React.Fragment key={i}>
          <div style={{
            display: 'grid', gridTemplateColumns: COL, gap: 4,
            padding: '6px 0', alignItems: 'center', position: 'relative',
          }}>
            {s.active && <div style={{ position: 'absolute', left: -20, top: 0, bottom: 0,
                                         width: 2, background: 'var(--hd-accent)', borderRadius: 1 }}/>}
            <span className="mono" style={{ fontSize: 11, textAlign: 'center',
              color: s.done ? 'var(--hd-ink-3)' : s.active ? 'var(--hd-accent)' : 'var(--hd-ink-2)' }}>
              {s.num}
            </span>
            <span className="mono" style={{ fontSize: 10.5, color: 'var(--hd-ink-3)',
              fontVariantNumeric: 'tabular-nums', whiteSpace: 'nowrap',
              overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {s.prev || '—'}
            </span>
            <TLVal v={s.w} done={s.done} active={s.active}/>
            <TLVal v={s.r} done={s.done} active={s.active}/>
            <TLVal v={s.rpe} done={s.done} active={s.active}/>
            <div style={{ display: 'grid', placeItems: 'center' }}>
              <TLCheck done={s.done}/>
            </div>
          </div>
          {/* rest indicators */}
          {s.done && sets[i + 1]?.done && <TLRest t={rest || '2:00'}/>}
          {s.done && sets[i + 1] && !sets[i + 1].done && resting && <TLActiveRest/>}
        </React.Fragment>
      ))}

      {/* add set */}
      <div style={{ padding: '8px 0', textAlign: 'center', fontSize: 12, color: 'var(--hd-ink-3)',
                     cursor: 'pointer' }}>
        + Add Set ({rest || '2:00'})
      </div>
    </div>
  );
}

/* ═══ Main training log ═════════════════════════════════════ */

const TL_EXERCISES = [
  {
    name: 'Bench Press', type: 'Barbell', trend: 'up', unit: 'lbs', rest: '2:00',
    sets: [
      { num: 1, prev: '135×5', w: '135', r: '5', rpe: '6', done: true },
      { num: 2, prev: '135×5', w: '145', r: '5', rpe: '7', done: true },
      { num: 3, prev: '135×5', w: '155', r: '5', rpe: '7', done: true },
      { num: 4, prev: '135×5', w: '155', r: '5', rpe: '8', done: true },
      { num: 5, prev: '135×5', w: '155', r: '4', rpe: '9', done: true },
    ],
  },
  {
    name: 'Pull Up', type: null, trend: 'flat', unit: '+lbs', rest: '2:00', resting: true,
    sets: [
      { num: 1, prev: '+25×5', w: '25', r: '5', rpe: '6', done: true },
      { num: 2, prev: '+25×5', w: '25', r: '5', rpe: '7', done: true },
      { num: 3, prev: '+25×5', w: '25', r: '5', active: true },
      { num: 4, prev: null,    w: '25', r: '5' },
    ],
  },
  {
    name: 'Overhead Press', type: 'Barbell', trend: 'up', unit: 'lbs', rest: '2:00',
    sets: [
      { num: 1, prev: '95×8', w: '100', r: '8' },
      { num: 2, prev: '95×8', w: '100', r: '8' },
      { num: 3, prev: '95×8', w: '100', r: '8' },
      { num: 4, prev: '95×8', w: '100', r: '8' },
    ],
  },
  {
    name: 'Incline Row', type: 'Dumbbell', trend: 'flat', unit: 'lbs', rest: '1:30',
    sets: [
      { num: 1, prev: '50×10', w: '50', r: '10' },
      { num: 2, prev: '50×10', w: '50', r: '10' },
      { num: 3, prev: '50×10', w: '50', r: '10' },
      { num: 4, prev: '50×10', w: '50', r: '10' },
    ],
  },
  {
    name: 'Skullcrusher', type: 'Barbell', trend: 'up', unit: 'lbs', rest: '1:30',
    sets: [
      { num: 1, prev: '65×10', w: '70', r: '10' },
      { num: 2, prev: '65×10', w: '70', r: '10' },
      { num: 3, prev: '65×10', w: '70', r: '10' },
    ],
  },
  {
    name: 'Face Pull', type: 'Cable', trend: 'flat', unit: 'lbs', rest: '1:00',
    sets: [
      { num: 1, prev: '30×15', w: '30', r: '15' },
      { num: 2, prev: '30×15', w: '30', r: '15' },
      { num: 3, prev: '30×15', w: '30', r: '15' },
    ],
  },
];

function HDTrainingLog() {
  /* ── progress calc ── */
  const totalSets = TL_EXERCISES.reduce((n, e) => n + e.sets.length, 0);
  const doneSets  = TL_EXERCISES.reduce((n, e) => n + e.sets.filter(s => s.done).length, 0);
  const pct = Math.round((doneSets / totalSets) * 100);

  return (
    <IOSDevice dark width={402} height={874}>
      <div className="hd" style={{ height: '100%', display: 'flex', flexDirection: 'column',
                                     background: 'var(--hd-bg)', paddingTop: 54 }}>

        {/* ─── Sticky header ─── */}
        <div style={{ padding: '10px 20px 0', flexShrink: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <button className="btn btn-ghost" style={{ padding: 4, minWidth: 'auto', border: 'none' }}>
                <HDIcon name="x" size={18} color="var(--hd-ink-2)"/>
              </button>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                <HDIcon name="timer" size={14} color="var(--hd-ink-3)"/>
                <span className="mono" style={{ fontSize: 17, fontWeight: 500,
                  fontVariantNumeric: 'tabular-nums', color: 'var(--hd-ink)' }}>0:24:18</span>
              </div>
            </div>
            <button className="btn btn-primary" style={{ padding: '8px 20px', borderRadius: 10,
              fontSize: 13, fontWeight: 700 }}>
              Finish
            </button>
          </div>
          {/* progress */}
          <div style={{ marginTop: 10, marginBottom: 10, height: 3, background: 'var(--hd-line-soft)',
                         borderRadius: 2, position: 'relative', overflow: 'hidden' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0,
                           width: `${pct}%`, background: 'var(--hd-accent)', borderRadius: 2,
                           transition: 'width 0.4s ease' }}/>
            {[1,2,3,4,5].map(i => (
              <div key={i} style={{ position: 'absolute', top: 0, bottom: 0,
                                     left: `${(i / 6) * 100}%`, width: 1,
                                     background: 'var(--hd-bg)' }}/>
            ))}
          </div>
        </div>

        {/* ─── Scrollable body ─── */}
        <div style={{ flex: 1, overflowY: 'auto', WebkitOverflowScrolling: 'touch' }}>
          {/* title */}
          <div style={{ padding: '14px 20px 8px' }}>
            <div className="display" style={{ fontSize: 26, fontWeight: 600,
              letterSpacing: '-0.03em', lineHeight: 1.05 }}>
              Upper Body Day 1
            </div>
            <div className="ink-3" style={{ fontSize: 12, marginTop: 5 }}>
              Sun, May 11 · 6 exercises · {doneSets}/{totalSets} sets logged
            </div>
          </div>

          <div style={{ height: 0.5, background: 'var(--hd-line)', margin: '4px 20px 0' }}/>

          {/* exercise blocks */}
          {TL_EXERCISES.map((ex, i) => (
            <React.Fragment key={i}>
              <TLExercise {...ex}/>
              {i < TL_EXERCISES.length - 1 && (
                <div style={{ height: 0.5, background: 'var(--hd-line)', margin: '0 20px' }}/>
              )}
            </React.Fragment>
          ))}

          {/* add exercise */}
          <div style={{ padding: '14px 20px 40px' }}>
            <div style={{ padding: '12px', borderRadius: 12, border: '0.5px dashed var(--hd-line)',
              textAlign: 'center', fontSize: 13, color: 'var(--hd-ink-3)' }}>
              + Add Exercise
            </div>
          </div>
        </div>

      </div>
    </IOSDevice>
  );
}

Object.assign(window, { HDTrainingLog, TLExercise, TLVal, TLCheck, TLTrend,
                          TLRest, TLActiveRest, TL_EXERCISES });
