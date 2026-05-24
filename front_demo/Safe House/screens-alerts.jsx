// screens-alerts.jsx — Alerts: last 7 days of notifications for the customer

// Mock 7-day alerts. Severity 'emergency' | 'warning'. ack=acknowledged
const ALERTS = [
  // Today
  { id: 'a1', day: 'Today',         time: '14:32', severity: 'warning',
    sensor: 'meds',    title: 'Medication cabinet not opened',
    body: 'Evening dose hasn\u2019t been taken yet. Usual time: 9:00 PM.',
    ack: false },
  { id: 'a2', day: 'Today',         time: '02:14', severity: 'emergency',
    sensor: 'door',    title: 'Front door opened, no return',
    body: 'Door opened at 02:14 AM and no return motion detected for 2 hours.',
    ack: false },

  // Yesterday
  { id: 'a3', day: 'Yesterday',     time: '21:48', severity: 'warning',
    sensor: 'kitchen', title: 'No dinner activity detected',
    body: 'Kitchen has been quiet since 5:12 PM. Usually active between 6–7 PM.',
    ack: true },

  // Wed
  { id: 'a4', day: 'Wed May 14',    time: '03:42', severity: 'warning',
    sensor: 'bed',     title: 'Restless night',
    body: '4 bed exits between midnight and 4 AM — outside Eleanor\u2019s pattern.',
    ack: true },

  // Tue
  { id: 'a5', day: 'Tue May 13',    time: '17:20', severity: 'warning',
    sensor: 'living',  title: 'Unusually long stillness',
    body: 'No motion in the living room for 3h 12m during typical active hours.',
    ack: true },

  // Sun (no Mon entries)
  { id: 'a6', day: 'Sun May 11',    time: '09:08', severity: 'emergency',
    sensor: 'bath',    title: 'Fall risk: long stillness in bathroom',
    body: 'No motion in bathroom for 18 minutes after entry. Resolved when motion resumed.',
    ack: true },
];

const SENSOR_BY_ID = Object.fromEntries(SENSOR_LIST.map(s => [s.id, s]));

const SEV = {
  emergency: { tone: 'alert', label: 'Emergency', dotTone: 'alert',
               bg: 'var(--alert-soft)', bd: '#E6BFB1', fg: '#7A3727' },
  warning:   { tone: 'warn',  label: 'Warning',   dotTone: 'warn',
               bg: 'var(--warn-soft)',  bd: '#EAD7A4', fg: '#7A5419' },
};

function AlertItem({ alert, compact = false }) {
  const sev = SEV[alert.severity];
  const sensor = SENSOR_BY_ID[alert.sensor];
  const Icon = sensor?.icon || Ico.Bell;
  const muted = alert.ack;
  return (
    <div style={{
      borderRadius: 16,
      background: 'var(--card)',
      border: '1px solid var(--line)',
      padding: compact ? 13 : 16,
      display: 'flex', gap: 12,
      opacity: muted ? 0.78 : 1,
      position: 'relative',
    }}>
      <div style={{ position: 'relative', flexShrink: 0 }}>
        <IconWell tone={sensor?.tone || 'sage'} size={compact ? 38 : 42}>
          <Icon size={compact ? 18 : 20}/>
        </IconWell>
        <span style={{
          position: 'absolute', top: -2, right: -2,
          width: 14, height: 14, borderRadius: '50%',
          background: alert.severity === 'emergency' ? 'var(--alert)' : 'var(--warn)',
          border: '2px solid var(--card)',
        }}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 5,
            padding: '2px 8px', fontSize: 11, fontWeight: 700,
            background: sev.bg, color: sev.fg, border: `1px solid ${sev.bd}`,
            borderRadius: 999, textTransform: 'uppercase', letterSpacing: '.04em',
          }}>{sev.label}</span>
          <span style={{ fontSize: 12, color: 'var(--ink-500)', fontVariantNumeric: 'tabular-nums' }}>
            {sensor?.name} · {alert.time}
          </span>
          {alert.ack && (
            <span style={{ marginLeft: 'auto', fontSize: 11, color: 'var(--ink-500)', display: 'inline-flex', alignItems: 'center', gap: 4, fontWeight: 600 }}>
              <Ico.Check size={12} sw={2.2} style={{ color: 'var(--sage-700)' }}/> Acknowledged
            </span>
          )}
        </div>
        <div style={{ marginTop: 6, fontSize: 14.5, fontWeight: 700, color: 'var(--ink-900)', lineHeight: 1.3 }}>
          {alert.title}
        </div>
        <div style={{ marginTop: 4, fontSize: 13, color: 'var(--ink-700)', lineHeight: 1.5 }}>
          {alert.body}
        </div>
        {!alert.ack && (
          <div style={{ marginTop: 10, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
            {alert.severity === 'emergency' && (
              <Button size="sm" variant="danger" leading={<Ico.Phone size={14}/>}>Call Eleanor</Button>
            )}
            <Button size="sm" variant={alert.severity === 'emergency' ? 'outline' : 'soft'}>View details</Button>
            <Button size="sm" variant="ghost">Acknowledge</Button>
          </div>
        )}
      </div>
    </div>
  );
}

function alertsByDay(items) {
  const groups = [];
  for (const a of items) {
    const last = groups[groups.length - 1];
    if (last && last.day === a.day) last.items.push(a);
    else groups.push({ day: a.day, items: [a] });
  }
  return groups;
}

function FilterChip({ label, count, active, onClick, tone = 'neutral' }) {
  const dotMap = { neutral: '#9DA89A', alert: 'var(--alert)', warn: 'var(--warn)', ok: 'var(--sage-600)' };
  return (
    <button onClick={onClick}
      style={{
        display: 'inline-flex', alignItems: 'center', gap: 7,
        padding: '7px 12px', borderRadius: 999, cursor: 'pointer',
        border: `1px solid ${active ? 'var(--sage-700)' : 'var(--line-2)'}`,
        background: active ? 'var(--sage-100)' : 'var(--card)',
        color: active ? 'var(--sage-800)' : 'var(--ink-700)',
        fontSize: 13, fontWeight: 600, transition: 'background .15s, border-color .15s',
        whiteSpace: 'nowrap',
      }}>
      <span style={{ width: 7, height: 7, borderRadius: '50%', background: dotMap[tone] }}/>
      {label}
      {typeof count === 'number' && (
        <span style={{
          minWidth: 18, padding: '0 6px', height: 18, borderRadius: 9,
          background: active ? 'var(--sage-200)' : 'var(--bg-soft)',
          color: active ? 'var(--sage-800)' : 'var(--ink-600)',
          fontSize: 11, fontWeight: 700, display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        }}>{count}</span>
      )}
    </button>
  );
}

function AlertsContent({ desktop = false }) {
  const [filter, setFilter] = React.useState('all');
  const filtered = ALERTS.filter(a => {
    if (filter === 'all') return true;
    if (filter === 'unack') return !a.ack;
    return a.severity === filter;
  });
  const counts = {
    all: ALERTS.length,
    emergency: ALERTS.filter(a => a.severity === 'emergency').length,
    warning: ALERTS.filter(a => a.severity === 'warning').length,
    unack: ALERTS.filter(a => !a.ack).length,
  };
  const groups = alertsByDay(filtered);

  const summaryRow = (
    <div style={{
      display: 'grid', gridTemplateColumns: 'repeat(3, minmax(0,1fr))', gap: 10,
      marginBottom: 14,
    }}>
      {[
        { label: 'Total · 7 days', value: counts.all,       tone: 'neutral' },
        { label: 'Emergencies',    value: counts.emergency, tone: 'alert'   },
        { label: 'Warnings',       value: counts.warning,   tone: 'warn'    },
      ].map(b => (
        <div key={b.label} style={{
          padding: '12px 12px', borderRadius: 14,
          background: 'var(--card)', border: '1px solid var(--line)',
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.06em' }}>
            <StatusDot tone={b.tone === 'neutral' ? 'ok' : b.tone} size={7}/>
            {b.label}
          </div>
          <div className="sh-display sh-numeric" style={{ fontSize: 24, color: 'var(--ink-900)', marginTop: 4, lineHeight: 1 }}>
            {b.value}
          </div>
        </div>
      ))}
    </div>
  );

  const filterRow = (
    <div style={{ display: 'flex', gap: 7, flexWrap: 'wrap', marginBottom: 14 }}>
      <FilterChip label="All"        count={counts.all}       active={filter === 'all'}        onClick={() => setFilter('all')}        tone="ok"/>
      <FilterChip label="Unread"     count={counts.unack}     active={filter === 'unack'}      onClick={() => setFilter('unack')}      tone="alert"/>
      <FilterChip label="Emergency"  count={counts.emergency} active={filter === 'emergency'}  onClick={() => setFilter('emergency')}  tone="alert"/>
      <FilterChip label="Warning"    count={counts.warning}   active={filter === 'warning'}    onClick={() => setFilter('warning')}    tone="warn"/>
    </div>
  );

  const empty = (
    <div style={{
      padding: 28, textAlign: 'center', borderRadius: 18,
      background: 'var(--sage-50)', border: '1px solid var(--sage-200)',
    }}>
      <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 12 }}>
        <IconWell tone="sage" size={56}><Ico.Check size={26} sw={2}/></IconWell>
      </div>
      <div className="sh-display" style={{ fontSize: 20, color: 'var(--ink-900)' }}>All quiet</div>
      <div style={{ marginTop: 6, fontSize: 13.5, color: 'var(--ink-700)', maxWidth: 280, marginInline: 'auto', lineHeight: 1.5 }}>
        No alerts match this filter. Everything has been calm.
      </div>
    </div>
  );

  return (
    <div>
      {summaryRow}
      {filterRow}
      {groups.length === 0 ? empty : (
        <div style={{ display: 'grid', gap: 18 }}>
          {groups.map(g => (
            <section key={g.day}>
              <div style={{
                display: 'flex', alignItems: 'baseline', gap: 8, marginBottom: 8,
                paddingInline: 2,
              }}>
                <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>{g.day}</div>
                <div style={{ flex: 1, height: 1, background: 'var(--line)' }}/>
                <div style={{ fontSize: 11, color: 'var(--ink-500)' }}>{g.items.length} {g.items.length === 1 ? 'alert' : 'alerts'}</div>
              </div>
              <div style={{ display: 'grid', gap: 8 }}>
                {g.items.map(a => <AlertItem key={a.id} alert={a} compact={!desktop}/>)}
              </div>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}

function AlertsMobile() {
  const unack = ALERTS.filter(a => !a.ack).length;
  return (
    <MobileShell active="alerts" alertCount={unack} badgeOn="alerts">
      <MobileTopBar
        subtitle="Last 7 days"
        title="Alerts"
        right={
          <button style={{
            width: 38, height: 38, borderRadius: '50%', border: '1px solid var(--line)',
            background: 'var(--card)', color: 'var(--ink-700)', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Ico.Settings size={17}/>
          </button>
        }
      />
      <div style={{ padding: '0 20px' }}>
        <AlertsContent/>
      </div>
    </MobileShell>
  );
}

function AlertsDesktop() {
  const unack = ALERTS.filter(a => !a.ack).length;
  return (
    <DesktopShell active="alerts" alertCount={unack} residentName="Eleanor Reyes"
      topbar={
        <div style={{
          padding: '20px 36px', borderBottom: '1px solid var(--line)',
          background: 'var(--bg-cream)',
        }}>
          <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>Last 7 days</div>
          <div className="sh-display" style={{ fontSize: 28, color: 'var(--ink-900)', marginTop: 2 }}>Alerts</div>
        </div>
      }>
      <div style={{ padding: 36, maxWidth: 880 }}>
        <AlertsContent desktop/>
      </div>
    </DesktopShell>
  );
}

Object.assign(window, { AlertsMobile, AlertsDesktop, AlertsContent, ALERTS });
