// proto/app.jsx — Main app shell with screen navigation
// Screens: start → log → complete → (back to start)
// History accessible from start screen

function ProtoApp() {
  // Screen: 'start' | 'log' | 'complete' | 'history'
  const [screen, setScreen] = React.useState(() => {
    // Resume active session if one exists
    const active = loadActiveSession();
    return active ? 'log' : 'start';
  });

  const [session, setSession] = React.useState(() => loadActiveSession());

  function handleStart() {
    const newSession = createSession('upper-1');
    setSession(newSession);
    saveActiveSession(newSession);
    setScreen('log');
  }

  function handleFinish() {
    const finished = { ...session, endTime: Date.now() };
    setSession(finished);
    setScreen('complete');
  }

  function handleSave() {
    setSession(null);
    setScreen('start');
  }

  return (
    <div style={{ width: 402, height: 874, position: 'relative', overflow: 'hidden',
      borderRadius: 44, background: PT.bg,
      boxShadow: '0 0 0 2px #2A2E35, 0 20px 60px rgba(0,0,0,0.6)',
      fontFamily: 'Inter, -apple-system, system-ui, sans-serif',
      WebkitFontSmoothing: 'antialiased', color: PT.ink,
    }}>
      {/* Status bar */}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 54, zIndex: 50,
        padding: '14px 28px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        background: 'linear-gradient(to bottom, #0A0B0D 80%, transparent)',
      }}>
        <span style={{ fontFamily: 'Inter', fontSize: 15, fontWeight: 600, color: PT.ink,
          letterSpacing: '-0.01em' }}>
          {new Date().toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' })}
        </span>
        <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
          {/* signal bars */}
          <svg width="16" height="12" viewBox="0 0 16 12">
            {[0,1,2,3].map(i => (
              <rect key={i} x={i * 4} y={9 - i * 3} width="3" height={3 + i * 3}
                rx="0.5" fill={i < 3 ? PT.ink : PT.ink3}/>
            ))}
          </svg>
          {/* battery */}
          <svg width="24" height="12" viewBox="0 0 24 12">
            <rect x="0" y="1" width="20" height="10" rx="2" fill="none" stroke={PT.ink} strokeWidth="1"/>
            <rect x="21" y="3.5" width="2" height="5" rx="0.5" fill={PT.ink3}/>
            <rect x="1.5" y="2.5" width="14" height="7" rx="1" fill={PT.ink}/>
          </svg>
        </div>
      </div>

      {/* Screen content (below status bar) */}
      <div style={{ position: 'absolute', top: 54, left: 0, right: 0, bottom: 0,
        display: 'flex', flexDirection: 'column' }}>

        {screen === 'start' && (
          <div style={{ height: '100%', position: 'relative' }}>
            <ScreenStart onStart={handleStart}/>
            {/* history button */}
            <div onClick={() => setScreen('history')} style={{
              position: 'absolute', top: 12, right: 20,
              display: 'flex', alignItems: 'center', gap: 6,
              padding: '6px 12px', borderRadius: 8,
              background: PT.surface, border: `0.5px solid ${PT.line}`,
              cursor: 'pointer', zIndex: 10,
            }}>
              <PIcon name="history" size={13} color={PT.ink3}/>
              <span style={{ fontFamily: 'JetBrains Mono', fontSize: 10, color: PT.ink3,
                letterSpacing: '0.1em', textTransform: 'uppercase' }}>History</span>
            </div>
          </div>
        )}

        {screen === 'log' && session && (
          <ScreenLog session={session} setSession={setSession} onFinish={handleFinish}/>
        )}

        {screen === 'complete' && session && (
          <ScreenComplete session={session} onSave={handleSave}/>
        )}

        {screen === 'history' && (
          <ScreenHistory onBack={() => setScreen('start')}/>
        )}
      </div>

      {/* Home indicator */}
      <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 3, background: PT.ink3, opacity: 0.3 }}/>
    </div>
  );
}

Object.assign(window, { ProtoApp });
