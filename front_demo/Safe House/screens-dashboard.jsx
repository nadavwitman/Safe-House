// dashboard.jsx — Customer Dashboard / Home screen
// Status hero (All Clear / Warning / Emergency) + sensor grid

const SENSOR_LIST = [
  { id: 'door',    name: 'Front Door',         icon: Ico.Door,    tone: 'sage'  },
  { id: 'kitchen', name: 'Kitchen',            icon: Ico.Kitchen, tone: 'warm'  },
  { id: 'bath',    name: 'Bathroom',           icon: Ico.Bath,    tone: 'sky'   },
  { id: 'toilet',  name: 'Toilet',             icon: Ico.Toilet,  tone: 'cream' },
  { id: 'meds',    name: 'Medication Cabinet', icon: Ico.Pill,    tone: 'plum'  },
  { id: 'bed',     name: 'Bed',                icon: Ico.Bed,     tone: 'sage'  },
  { id: 'living',  name: 'Living Room',        icon: Ico.Sofa,    tone: 'cream' },
];

// Mock sensor reading by status
const SENSOR_READINGS = {
  clear: {
    door:    { ts: 'Today 09:42', state: 'Active',           tone: 'ok' },
    kitchen: { ts: 'Today 08:15', state: 'Active',           tone: 'ok' },
    bath:    { ts: 'Today 07:48', state: 'Recent activity',  tone: 'ok' },
    toilet:  { ts: 'Today 10:02', state: 'Active',           tone: 'ok' },
    meds:    { ts: 'Today 08:30', state: 'Opened on time',   tone: 'ok' },
    bed:     { ts: 'Today 07:12', state: 'Unoccupied',       tone: 'off' },
    living:  { ts: 'Today 10:15', state: 'Active',           tone: 'ok' },
  },
  warning: {
    door:    { ts: 'Today 14:32', state: 'Active',           tone: 'ok' },
    kitchen: { ts: '7h ago',      state: 'No recent activity', tone: 'warn' },
    bath:    { ts: 'Today 07:48', state: 'Recent activity',  tone: 'ok' },
    toilet:  { ts: 'Today 13:12', state: 'Active',           tone: 'ok' },
    meds:    { ts: 'Yesterday 21:00', state: 'Missed evening dose', tone: 'warn' },
    bed:     { ts: 'Today 06:40', state: 'Unoccupied',       tone: 'off' },
    living:  { ts: 'Today 14:18', state: 'Active',           tone: 'ok' },
  },
  emergency: {
    door:    { ts: '2h ago',      state: 'Opened, no return', tone: 'alert' },
    kitchen: { ts: 'Today 06:50', state: 'Active',           tone: 'ok' },
    bath:    { ts: 'Today 07:48', state: 'Recent activity',  tone: 'ok' },
    toilet:  { ts: 'Today 06:55', state: 'Active',           tone: 'ok' },
    meds:    { ts: 'Today 08:30', state: 'Opened on time',   tone: 'ok' },
    bed:     { ts: 'Today 06:20', state: 'Unoccupied',       tone: 'off' },
    living:  { ts: 'Today 07:15', state: 'No recent activity', tone: 'warn' },
  },
  vacation: {
    door:    { ts: 'Today 09:42', state: 'Active',          tone: 'ok' },
    kitchen: { ts: 'Today 08:15', state: 'Active',          tone: 'ok' },
    bath:    { ts: 'Today 07:48', state: 'Recent activity', tone: 'ok' },
    toilet:  { ts: 'Today 10:02', state: 'Active',          tone: 'ok' },
    meds:    { ts: 'Today 08:30', state: 'Opened on time',  tone: 'ok' },
    bed:     { ts: 'Today 07:12', state: 'Unoccupied',      tone: 'off' },
    living:  { ts: 'Today 10:15', state: 'Active',          tone: 'ok' },
  },
  empty: {
    door:    null, kitchen: null, bath: null, toilet: null,
    meds: null, bed: null, living: null,
  },
};

const STATUS_META = {
  clear: {
    label: 'All Clear', tone: 'ok',
    accent: 'var(--sage-600)', accentSoft: 'var(--sage-100)',
    body: 'Everything looks normal. Eleanor is following her usual routine.',
  },
  warning: {
    label: 'Heads Up', tone: 'warn',
    accent: 'var(--warn)', accentSoft: 'var(--warn-soft)',
    body: 'A small anomaly was detected. Nothing urgent — check the alert below.',
  },
  emergency: {
    label: 'Emergency', tone: 'alert',
    accent: 'var(--alert)', accentSoft: 'var(--alert-soft)',
    body: 'Unusual activity that may need immediate attention. Please check in now.',
  },
  vacation: {
    label: 'Vacation Mode', tone: 'neutral',
    accent: '#3F6868', accentSoft: '#E1ECEC',
    body: 'Sensors are still recording, but alerts are off while Eleanor is away.',
  },
};

function StatusHero({ status = 'clear', resident = 'Eleanor', compact = false }) {
  const meta = STATUS_META[status];
  const ringSize = compact ? 138 : 168;
  const isVacation = status === 'vacation';
  // Compose icon by status
  const Glyph =
    status === 'emergency' ? Ico.Alert :
    status === 'warning'   ? Ico.Bell  :
    isVacation             ? Ico.Suitcase :
    Ico.HomeCheck;

  return (
    <Card padding={compact ? 18 : 22} style={{ background: 'var(--card)', overflow: 'hidden', position: 'relative' }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 6 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.1em' }}>Status</div>
        <Tag tone={meta.tone === 'ok' ? 'sage' : meta.tone === 'warn' ? 'warn' : meta.tone === 'alert' ? 'alert' : 'neutral'} icon={<StatusDot tone={isVacation ? 'ok' : meta.tone} size={7} pulse={status !== 'clear' && !isVacation}/>}>{isVacation ? 'Live · alerts off' : 'Live'}</Tag>
      </div>
      <div style={{ display: 'flex', justifyContent: 'center', marginTop: 8 }}>
        <div style={{
          width: ringSize, height: ringSize, position: 'relative',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          {/* outer pulse ring */}
          <div style={{
            position: 'absolute', inset: 0, borderRadius: '50%',
            background: `radial-gradient(circle, ${meta.accentSoft} 0%, transparent 65%)`,
          }}/>
          <div style={{
            position: 'absolute', inset: 10, borderRadius: '50%',
            border: `1.5px solid ${meta.accent}`, opacity: .6,
            animation: (status !== 'clear' && !isVacation) ? 'shPulse 2.4s ease-out infinite' : 'none',
            borderStyle: isVacation ? 'dashed' : 'solid',
          }}/>
          <div style={{
            position: 'absolute', inset: 22, borderRadius: '50%',
            border: `1px solid ${meta.accent}`, opacity: .35,
          }}/>
          <div style={{
            width: ringSize * 0.46, height: ringSize * 0.46, borderRadius: '50%',
            background: 'var(--card-2)', border: `2px solid ${meta.accent}`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: meta.accent, boxShadow: '0 4px 14px rgba(80,90,75,.10)',
          }}>
            <Glyph size={ringSize * 0.22} sw={1.6}/>
          </div>
        </div>
      </div>
      <div style={{ textAlign: 'center', marginTop: 8 }}>
        <div style={{ fontSize: 13, color: 'var(--ink-500)' }}>Status:</div>
        <div className="sh-display" style={{ fontSize: compact ? 30 : 36, lineHeight: 1.1, color: meta.accent, marginTop: 2 }}>{meta.label}</div>
        <div style={{ marginTop: 8, fontSize: 13.5, color: 'var(--ink-600)', maxWidth: 360, marginInline: 'auto', lineHeight: 1.5 }}>
          {meta.body}
        </div>
      </div>
    </Card>
  );
}

function AlertBanner({ status, sensor = 'Front Door', message = 'Door opened at 02:14 AM — no return detected for 2 hours.', onAck, onCall }) {
  if (status === 'clear') return null;
  const isEmergency = status === 'emergency';
  return (
    <div style={{
      borderRadius: 18,
      background: isEmergency ? 'var(--alert-soft)' : 'var(--warn-soft)',
      border: `1px solid ${isEmergency ? '#E6BFB1' : '#EAD7A4'}`,
      padding: 16, display: 'flex', gap: 12, alignItems: 'flex-start',
      animation: 'shFade .4s ease',
    }}>
      <div style={{
        width: 38, height: 38, borderRadius: '50%',
        background: isEmergency ? '#E89B86' : '#D9B36C',
        color: '#FBF8F0', display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
        {isEmergency ? <Ico.Alert size={20}/> : <Ico.Bell size={20}/>}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <div style={{ fontSize: 14.5, fontWeight: 700, color: isEmergency ? '#7A3727' : '#7A5419' }}>
            {isEmergency ? 'Emergency' : 'Warning'} · {sensor}
          </div>
          <span style={{ fontSize: 12, color: isEmergency ? '#9C5840' : '#9C7A2F' }}>just now</span>
        </div>
        <div style={{ marginTop: 4, fontSize: 13.5, color: isEmergency ? '#7A3727' : '#7A5419', lineHeight: 1.5 }}>
          {message}
        </div>
        <div style={{ marginTop: 12, display: 'flex', gap: 8, flexWrap: 'wrap' }}>
          {isEmergency && <Button size="sm" variant="danger" leading={<Ico.Phone size={16}/>}>Call Eleanor</Button>}
          <Button size="sm" variant={isEmergency ? 'outline' : 'soft'}>View details</Button>
          <Button size="sm" variant="ghost">Acknowledge</Button>
        </div>
      </div>
    </div>
  );
}

function SensorCard({ sensor, reading, dense = false }) {
  const Icon = sensor.icon;
  const empty = !reading;
  return (
    <div style={{
      background: 'var(--card)', borderRadius: 18,
      border: '1px solid var(--line)',
      padding: dense ? 14 : 16,
      display: 'flex', flexDirection: 'column', gap: 10,
      boxShadow: 'var(--shadow-sm)',
      position: 'relative', minHeight: dense ? 0 : 118,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
        <IconWell tone={sensor.tone} size={dense ? 36 : 40}>
          <Icon size={dense ? 18 : 20}/>
        </IconWell>
        <div style={{ minWidth: 0, flex: 1 }}>
          <div style={{ fontSize: 13.5, fontWeight: 700, color: 'var(--ink-900)', lineHeight: 1.2 }}>{sensor.name}</div>
          <div style={{ fontSize: 11.5, color: 'var(--ink-500)', marginTop: 2, fontVariantNumeric: 'tabular-nums' }}>
            {empty ? 'No data yet' : reading.ts}
          </div>
        </div>
        {!empty && (
          <div style={{ position: 'absolute', top: 12, right: 12 }}>
            <StatusDot tone={reading.tone} size={8}/>
          </div>
        )}
      </div>
      <div style={{
        fontSize: 12.5, color: empty ? 'var(--ink-400)' : 'var(--ink-700)',
        fontWeight: 600,
      }}>
        {empty ? (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: 'var(--ink-400)' }}>
            <span style={{ width: 14, height: 1.5, background: 'var(--ink-300)', display: 'inline-block', borderRadius: 1 }}/>
            Waiting for first reading
          </span>
        ) : reading.state}
      </div>
    </div>
  );
}

// ── Mobile dashboard ─────────────────────────────────────────
function DashboardMobile({ status = 'clear', hasData = true }) {
  const readings = hasData ? SENSOR_READINGS[status] : SENSOR_READINGS.empty;
  const alertCount = status === 'emergency' ? 1 : status === 'warning' ? 1 : 0;
  const showAlert = status === 'warning' || status === 'emergency';
  return (
    <MobileShell active="home" alertCount={alertCount}>
      <div style={{ padding: '22px 20px 0' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <Wordmark size="sm"/>
          <div style={{ position: 'relative' }}>
            <button style={{
              width: 40, height: 40, borderRadius: '50%', border: '1px solid var(--line)',
              background: 'var(--card)', color: 'var(--ink-700)', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Ico.Bell size={18}/>
              {alertCount > 0 && (
                <span style={{
                  position: 'absolute', top: -2, right: -2, width: 16, height: 16,
                  background: 'var(--alert)', color: '#FBF8F0', borderRadius: '50%',
                  fontSize: 10, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  border: '2px solid var(--bg-cream)',
                }}>{alertCount}</span>
              )}
            </button>
          </div>
        </div>
        <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div>
            <div style={{ fontSize: 12, color: 'var(--ink-500)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.08em' }}>Watching over</div>
            <div className="sh-display" style={{ fontSize: 24, color: 'var(--ink-900)', marginTop: 2 }}>Eleanor’s House</div>
          </div>
          <button style={{
            display: 'inline-flex', alignItems: 'center', gap: 4, padding: '6px 10px',
            background: 'var(--card)', border: '1px solid var(--line)', borderRadius: 999,
            fontSize: 12, color: 'var(--ink-700)', cursor: 'pointer',
          }}>Switch <Ico.ChevronDown size={14}/></button>
        </div>
      </div>

      <div style={{ padding: '16px 20px 0', display: 'grid', gap: 14 }}>
        <StatusHero status={status} compact/>
        {showAlert && (
          <AlertBanner
            status={status}
            sensor={status === 'emergency' ? 'Front Door' : 'Medication Cabinet'}
            message={status === 'emergency'
              ? 'Door opened at 02:14 AM and no return detected for 2 hours. This is outside Eleanor’s usual pattern.'
              : 'Evening medication dose hasn’t been taken yet. Usual time: 9:00 PM.'}
          />
        )}
        <div style={{ marginTop: 6, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <div className="sh-display" style={{ fontSize: 18, color: 'var(--ink-900)' }}>Sensors</div>
          <span style={{ fontSize: 12, color: 'var(--ink-500)' }}>{SENSOR_LIST.length} active</span>
        </div>
        <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) minmax(0,1fr)', gap: 10 }}>
          {SENSOR_LIST.map(s => (
            <SensorCard key={s.id} sensor={s} reading={readings[s.id]} dense/>
          ))}
        </div>
      </div>
    </MobileShell>
  );
}

// ── Desktop dashboard ────────────────────────────────────────
function DashboardDesktop({ status = 'clear', hasData = true }) {
  const readings = hasData ? SENSOR_READINGS[status] : SENSOR_READINGS.empty;
  const alertCount = status === 'emergency' ? 1 : status === 'warning' ? 1 : 0;
  const showAlert = status === 'warning' || status === 'emergency';
  return (
    <DesktopShell active="home" alertCount={alertCount} residentName="Eleanor Reyes"
      topbar={
        <div style={{
          padding: '20px 36px', borderBottom: '1px solid var(--line)',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          background: 'var(--bg-cream)',
        }}>
          <div>
            <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>Watching over</div>
            <div className="sh-display" style={{ fontSize: 28, color: 'var(--ink-900)', marginTop: 2 }}>Eleanor’s House</div>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <Button variant="outline" size="sm" leading={<Ico.Refresh size={14}/>}>Refresh</Button>
            <Button variant="soft" size="sm" trailing={<Ico.ChevronDown size={14}/>}>Switch house</Button>
            <button style={{
              width: 40, height: 40, borderRadius: '50%', border: '1px solid var(--line)',
              background: 'var(--card)', cursor: 'pointer', display: 'flex',
              alignItems: 'center', justifyContent: 'center', color: 'var(--ink-700)',
              position: 'relative',
            }}>
              <Ico.Bell size={18}/>
              {alertCount > 0 && (
                <span style={{
                  position: 'absolute', top: -2, right: -2, width: 18, height: 18,
                  background: 'var(--alert)', color: '#FBF8F0', borderRadius: '50%',
                  fontSize: 10.5, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  border: '2px solid var(--bg-cream)',
                }}>{alertCount}</span>
              )}
            </button>
          </div>
        </div>
      }
    >
      <div style={{ padding: 36, display: 'grid', gap: 24 }}>
        {/* row: status + alert area side by side */}
        <div style={{ display: 'grid', gridTemplateColumns: '420px 1fr', gap: 24 }}>
          <StatusHero status={status}/>
          <div style={{ display: 'grid', gap: 16, alignContent: 'start' }}>
            {showAlert && (
              <AlertBanner
                status={status}
                sensor={status === 'emergency' ? 'Front Door' : 'Medication Cabinet'}
                message={status === 'emergency'
                  ? 'Door opened at 02:14 AM and no return detected for 2 hours. This is outside Eleanor’s usual pattern.'
                  : 'Evening medication dose hasn’t been taken yet. Usual time: 9:00 PM.'}
              />
            )}
            <Card padding={20}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                <div className="sh-display" style={{ fontSize: 20, color: 'var(--ink-900)' }}>Today at a glance</div>
                <span style={{ fontSize: 12, color: 'var(--ink-500)' }}>{new Date().toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' })}</span>
              </div>
              <div style={{ marginTop: 14, display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12 }}>
                {[
                  { label: 'Wake', value: '6:48 AM', icon: <Ico.Sun size={16}/> },
                  { label: 'Meds taken', value: status === 'warning' ? '1 of 2' : '2 of 2', icon: <Ico.Pill size={16}/> },
                  { label: 'Transitions', value: '14', icon: <Ico.ArrowRight size={16}/> },
                  { label: 'Outside', value: '38 min', icon: <Ico.Suitcase size={16}/> },
                ].map((m, i) => (
                  <div key={i} style={{
                    padding: '12px 14px', borderRadius: 14, background: 'var(--bg-soft)',
                    border: '1px solid var(--line)',
                  }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11.5, color: 'var(--ink-500)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.06em' }}>{m.icon}{m.label}</div>
                    <div className="sh-display" style={{ fontSize: 22, color: 'var(--ink-900)', marginTop: 4 }}>{m.value}</div>
                  </div>
                ))}
              </div>
            </Card>
          </div>
        </div>

        {/* Sensor grid */}
        <div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
            <div className="sh-display" style={{ fontSize: 22, color: 'var(--ink-900)' }}>Sensors</div>
            <div style={{ fontSize: 12.5, color: 'var(--ink-500)' }}>Updated 4 seconds ago</div>
          </div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 14 }}>
            {SENSOR_LIST.map(s => (
              <SensorCard key={s.id} sensor={s} reading={readings[s.id]}/>
            ))}
          </div>
        </div>
      </div>
    </DesktopShell>
  );
}

Object.assign(window, {
  DashboardMobile, DashboardDesktop, SensorCard, StatusHero, AlertBanner, SENSOR_LIST,
});
