// proto/data.jsx — Workout templates, localStorage persistence, state helpers

const WORKOUT_TEMPLATES = {
  'upper-1': {
    id: 'upper-1',
    name: 'Upper Body Day 1',
    category: 'Push / Pull / Accessories',
    exercises: [
      { id: 'bench', name: 'Bench Press', type: 'Barbell', unit: 'lbs', targetSets: 5, targetReps: 5, rest: 120 },
      { id: 'pullup', name: 'Pull Up', type: null, unit: '+lbs', targetSets: 4, targetReps: 5, rest: 120 },
      { id: 'ohp', name: 'Overhead Press', type: 'Barbell', unit: 'lbs', targetSets: 4, targetReps: 8, rest: 120 },
      { id: 'row', name: 'Incline Row', type: 'Dumbbell', unit: 'lbs', targetSets: 4, targetReps: 10, rest: 90 },
      { id: 'skull', name: 'Skullcrusher', type: 'Barbell', unit: 'lbs', targetSets: 3, targetReps: 10, rest: 90 },
      { id: 'facepull', name: 'Face Pull', type: 'Cable', unit: 'lbs', targetSets: 3, targetReps: 15, rest: 60 },
    ],
  },
};

const DB_KEY = 'pt_sessions';
const ACTIVE_KEY = 'pt_active_session';

function loadSessions() {
  try { return JSON.parse(localStorage.getItem(DB_KEY)) || []; }
  catch { return []; }
}

function saveSessions(sessions) {
  localStorage.setItem(DB_KEY, JSON.stringify(sessions));
}

function saveActiveSession(session) {
  localStorage.setItem(ACTIVE_KEY, JSON.stringify(session));
}

function loadActiveSession() {
  try { return JSON.parse(localStorage.getItem(ACTIVE_KEY)); }
  catch { return null; }
}

function clearActiveSession() {
  localStorage.removeItem(ACTIVE_KEY);
}

// Get previous session data for a given template
function getPreviousSession(templateId) {
  const sessions = loadSessions();
  return sessions.filter(s => s.templateId === templateId).sort((a, b) => b.timestamp - a.timestamp)[0] || null;
}

// Build a fresh session from template + previous data
function createSession(templateId) {
  const tmpl = WORKOUT_TEMPLATES[templateId];
  const prev = getPreviousSession(templateId);

  const exercises = tmpl.exercises.map(ex => {
    const prevEx = prev?.exercises?.find(e => e.id === ex.id);
    const sets = Array.from({ length: ex.targetSets }, (_, i) => {
      const prevSet = prevEx?.sets?.[i];
      return {
        num: i + 1,
        weight: prevSet ? String(prevSet.weight) : '',
        reps: prevSet ? String(prevSet.reps) : String(ex.targetReps),
        rpe: '',
        done: false,
      };
    });
    return { ...ex, sets, prevSets: prevEx?.sets || [] };
  });

  return {
    templateId,
    name: tmpl.name,
    category: tmpl.category,
    startTime: Date.now(),
    exercises,
  };
}

// Calculate session stats
function sessionStats(session) {
  let totalSets = 0, doneSets = 0, totalRpe = 0, rpeCount = 0;
  session.exercises.forEach(ex => {
    ex.sets.forEach(s => {
      totalSets++;
      if (s.done) {
        doneSets++;
        if (s.rpe && !isNaN(Number(s.rpe))) { totalRpe += Number(s.rpe); rpeCount++; }
      }
    });
  });
  return { totalSets, doneSets, avgRpe: rpeCount ? (totalRpe / rpeCount).toFixed(1) : '—' };
}

Object.assign(window, {
  WORKOUT_TEMPLATES, loadSessions, saveSessions, saveActiveSession,
  loadActiveSession, clearActiveSession, getPreviousSession,
  createSession, sessionStats, DB_KEY, ACTIVE_KEY,
});
