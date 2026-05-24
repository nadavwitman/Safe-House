// summary.jsx — Weekly Summary screen with two charts + metric cards + AI insights

const DAYS = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

// Mock weekly data
const SLEEP_DATA = [
  { day: 'Mon', hours: 7.2, interruptions: 1 },
  { day: 'Tue', hours: 6.4, interruptions: 3 },
  { day: 'Wed', hours: 7.6, interruptions: 0 },
  { day: 'Thu', hours: 5.8, interruptions: 4 },
  { day: 'Fri', hours: 6.9, interruptions: 2 },
  { day: 'Sat', hours: 7.1, interruptions: 1 },
  { day: 'Sun', hours: 7.4, interruptions: 1 },
];
const ACTIVITY_DATA = [
  { day: 'Mon', transitions: 22, kitchen: 6, outside: 45 },
  { day: 'Tue', transitions: 18, kitchen: 4, outside: 20 },
  { day: 'Wed', transitions: 24, kitchen: 7, outside: 60 },
  { day: 'Thu', transitions: 16, kitchen: 3, outside: 0  },
  { day: 'Fri', transitions: 20, kitchen: 5, outside: 35 },
  { day: 'Sat', transitions: 26, kitchen: 8, outside: 75 },
  { day: 'Sun', transitions: 23, kitchen: 6, outside: 50 },
];

// ── Sleep chart — line for hours + bars for interruptions ───
function SleepChart({ width = 560, height = 220, dense = false }) {
  const pad = { l: 36, r: 16, t: 16, b: 28 };
  const w = width - pad.l - pad.r;
  const h = height - pad.t - pad.b;
  const maxHrs = 10;
  const maxInt = 5;
  const innerInset = w * 0.04; // pull both ends inward so bars don't kiss the axes
  const stepX = (w - innerInset * 2) / (SLEEP_DATA.length - 1);
  const xAt = i => pad.l + innerInset + i * stepX;
  const yAt = hrs => pad.t + h - (hrs / maxHrs) * h;

  const linePts = SLEEP_DATA.map((d, i) => `${xAt(i)},${yAt(d.hours)}`).join(' ');
  const areaPath = `M${xAt(0)},${pad.t + h} L${linePts.replace(/ /g, ' L')} L${xAt(SLEEP_DATA.length - 1)},${pad.t + h} Z`;

  const barW = stepX * 0.38;
  const barMaxH = h * 0.78;
  return (
    <svg width="100%" height={height} viewBox={`0 0 ${width} ${height}`} style={{ display: 'block' }}>
      <defs>
        <linearGradient id="sleepArea" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%"  stopColor="#8FAA8C" stopOpacity=".25"/>
          <stop offset="100%" stopColor="#8FAA8C" stopOpacity="0"/>
        </linearGradient>
      </defs>
      {/* y grid */}
      {[0, 2, 4, 6, 8, 10].map(v => (
        <g key={v}>
          <line x1={pad.l} x2={pad.l + w} y1={yAt(v)} y2={yAt(v)} stroke="#E2D9C2" strokeDasharray="2 4"/>
          <text x={pad.l - 8} y={yAt(v) + 3} fontSize="10" fill="#82917F" textAnchor="end" fontFamily="Manrope">{v}h</text>
        </g>
      ))}
      {/* interruption bars (right axis-ish, scaled smaller) */}
      {SLEEP_DATA.map((d, i) => {
        const bh = d.interruptions === 0 ? 4 : Math.max(8, (d.interruptions / maxInt) * barMaxH);
        return (
          <rect key={i}
            x={xAt(i) - barW / 2} y={pad.t + h - bh} width={barW} height={bh}
            rx="3" fill="#C99544" opacity={d.interruptions === 0 ? 0.18 : 0.7}/>
        );
      })}
      {/* area under line */}
      <path d={areaPath} fill="url(#sleepArea)"/>
      {/* line */}
      <polyline points={linePts} fill="none" stroke="#4F6B53" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
      {/* dots */}
      {SLEEP_DATA.map((d, i) => (
        <g key={i}>
          <circle cx={xAt(i)} cy={yAt(d.hours)} r="4.5" fill="#FBF8F0" stroke="#4F6B53" strokeWidth="1.8"/>
        </g>
      ))}
      {/* x labels */}
      {SLEEP_DATA.map((d, i) => (
        <text key={i} x={xAt(i)} y={pad.t + h + 18} fontSize="11" fill="#82917F" textAnchor="middle" fontFamily="Manrope">{d.day}</text>
      ))}
    </svg>
  );
}

// ── Activity chart — grouped bars ─────────────────────────────
function ActivityChart({ width = 560, height = 220 }) {
  const pad = { l: 36, r: 16, t: 16, b: 28 };
  const w = width - pad.l - pad.r;
  const h = height - pad.t - pad.b;
  const max = 80; // accommodate outside minutes
  const groupW = w / ACTIVITY_DATA.length;
  const barW = (groupW - 8) / 3;
  const colors = ['#6B8B6E', '#C99544', '#704863'];
  const labels = ['Transitions', 'Kitchen', 'Outside (min)'];
  const keys = ['transitions', 'kitchen', 'outside'];

  return (
    <svg width="100%" height={height} viewBox={`0 0 ${width} ${height}`} style={{ display: 'block' }}>
      {[0, 20, 40, 60, 80].map(v => {
        const y = pad.t + h - (v / max) * h;
        return (
          <g key={v}>
            <line x1={pad.l} x2={pad.l + w} y1={y} y2={y} stroke="#E2D9C2" strokeDasharray="2 4"/>
            <text x={pad.l - 8} y={y + 3} fontSize="10" fill="#82917F" textAnchor="end" fontFamily="Manrope">{v}</text>
          </g>
        );
      })}
      {ACTIVITY_DATA.map((d, i) => {
        const groupX = pad.l + i * groupW + 4;
        return (
          <g key={i}>
            {keys.map((k, j) => {
              const bh = (d[k] / max) * h;
              return (
                <rect key={k}
                  x={groupX + j * barW} y={pad.t + h - bh}
                  width={barW - 1.5} height={bh}
                  rx="3" fill={colors[j]}
                  opacity={d[k] === 0 ? 0.2 : 0.92}/>
              );
            })}
            <text x={groupX + (groupW - 8) / 2} y={pad.t + h + 18}
              fontSize="11" fill="#82917F" textAnchor="middle" fontFamily="Manrope">{d.day}</text>
          </g>
        );
      })}
    </svg>
  );
}

// ── Chart card wrapper ───────────────────────────────────────
function ChartCard({ title, subtitle, legend, children, compact = false }) {
  return (
    <Card padding={compact ? 14 : 20}>
      <div style={{ display: 'flex', alignItems: 'flex-start', justifyContent: 'space-between', marginBottom: 8 }}>
        <div style={{ minWidth: 0 }}>
          <div className="sh-display" style={{ fontSize: compact ? 18 : 20, color: 'var(--ink-900)' }}>{title}</div>
          {subtitle && <div style={{ fontSize: 12, color: 'var(--ink-500)', marginTop: 2, lineHeight: 1.35 }}>{subtitle}</div>}
        </div>
      </div>
      {legend && (
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: compact ? 10 : 14, marginBottom: 6, fontSize: 11.5, color: 'var(--ink-700)' }}>
          {legend.map(l => (
            <span key={l.label} style={{ display: 'inline-flex', alignItems: 'center', gap: 5 }}>
              <span style={{ width: 9, height: 9, borderRadius: 2.5, background: l.color, display: 'inline-block' }}/> {l.label}
            </span>
          ))}
        </div>
      )}
      <div style={{ width: '100%', overflow: 'hidden' }}>{children}</div>
    </Card>
  );
}

// ── Metric card with baseline delta ──────────────────────────
function MetricCard({ title, icon, tone = 'sage', value, sub, delta, baselineMissing, compact = false }) {
  // delta: { v: '+0.5h', dir: 'up'|'down'|'flat', state: 'ok'|'warn'|'alert' }
  const dMap = {
    ok:    { bg: 'var(--sage-100)', color: 'var(--sage-800)', bd: 'var(--sage-200)' },
    warn:  { bg: 'var(--warn-soft)', color: '#7A5419', bd: '#EAD7A4' },
    alert: { bg: 'var(--alert-soft)', color: '#7E3A28', bd: '#E8C2B5' },
  };
  const d = delta && dMap[delta.state];
  const Arrow = !delta ? null : delta.dir === 'down' ? Ico.ArrowDown : delta.dir === 'up' ? Ico.ArrowUp : Ico.Minus;
  const badge = baselineMissing ? (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 3,
      padding: '3px 6px', fontSize: 10, fontWeight: 700,
      background: 'var(--card-3)', color: 'var(--ink-700)', border: '1px solid var(--line)',
      borderRadius: 999, whiteSpace: 'nowrap',
    }}>No baseline</span>
  ) : delta ? (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 3,
      padding: compact ? '3px 6px' : '4px 9px', borderRadius: 999,
      fontSize: compact ? 10.5 : 12, fontWeight: 700, whiteSpace: 'nowrap',
      background: d.bg, color: d.color, border: `1px solid ${d.bd}`,
    }}>
      <Arrow size={compact ? 10 : 12} sw={2.2}/> {delta.v}
    </span>
  ) : null;
  return (
    <Card padding={compact ? 14 : 18}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <IconWell tone={tone} size={compact ? 30 : 36}>{icon}</IconWell>
        <div style={{ flex: 1, minWidth: 0, fontSize: compact ? 10.5 : 12, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.06em', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{title}</div>
      </div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, flexWrap: 'wrap', marginTop: compact ? 8 : 12 }}>
        <div className="sh-display sh-numeric" style={{ fontSize: compact ? 22 : 28, color: 'var(--ink-900)', lineHeight: 1.05 }}>{value}</div>
        {badge}
      </div>
      {sub && <div style={{ fontSize: compact ? 11.5 : 12.5, color: 'var(--ink-600)', marginTop: 4, lineHeight: 1.4 }}>{sub}</div>}
    </Card>
  );
}

const METRICS = [
  { title: 'Sleep',     icon: <Ico.Moon size={18}/>,     tone: 'sage',  value: '6h 54m', sub: 'avg, 1.7 interruptions/night', delta: { v: '−0.4h', dir: 'down', state: 'warn' } },
  { title: 'Mobility',  icon: <Ico.ArrowRight size={18}/>,tone: 'sage', value: '21.3',   sub: 'transitions / day',           delta: { v: '+1.2',  dir: 'up',   state: 'ok'   } },
  { title: 'Nutrition', icon: <Ico.Kitchen size={18}/>,   tone: 'warm', value: '5.6',    sub: 'kitchen triggers / day',      delta: { v: '−1.1',  dir: 'down', state: 'warn' } },
  { title: 'Hygiene',   icon: <Ico.Bath size={18}/>,      tone: 'sky',  value: '14 min', sub: 'bath/toilet/prep · daily',    delta: { v: '+2 min',dir: 'up',   state: 'ok'   } },
  { title: 'Medications',icon: <Ico.Pill size={18}/>,     tone: 'plum', value: '1.9',    sub: 'sessions / day',              delta: { v: '−0.1',  dir: 'down', state: 'ok'   } },
  { title: 'Outside',   icon: <Ico.Suitcase size={18}/>,  tone: 'cream',value: '40 min', sub: 'outside time / day',          baselineMissing: false, delta: { v: '−12 min', dir: 'down', state: 'alert' } },
];

const INSIGHT_SECTIONS = [
  { title: 'Sleep',       body: 'Eleanor slept slightly less than usual this week (−0.4h), with two restless nights on Tuesday and Thursday.' },
  { title: 'Mobility',    body: 'Movement around the home stayed strong — 21 transitions/day, a touch above her baseline.' },
  { title: 'Nutrition',   body: 'Kitchen activity dropped on Thursday and Friday, which may reflect lighter meals or skipped snacks.' },
  { title: 'Cognitive',   body: 'Routines stayed consistent. Wake and bedtime varied by less than 25 minutes from her usual.' },
  { title: 'Medications', body: 'All morning doses were taken. One evening dose was skipped on Thursday.' },
  { title: 'Social',      body: 'Outside time fell by 12 minutes/day. Consider a short walk or visit this weekend.' },
];

const RECOMMENDATIONS = [
  'Plan a check-in call Thursday evening — her sleep dipped both nights this week.',
  'Encourage a short walk Saturday morning to gently bring outside time back to baseline.',
  'Ask her pharmacist about pairing the evening dose with another nightly habit (e.g. brushing teeth).',
];

function AIInsightsBlock({ compact = false }) {
  return (
    <Card padding={compact ? 18 : 22}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 12 }}>
        <IconWell tone="sage" size={32}><Ico.Sparkle size={16}/></IconWell>
        <div className="sh-display" style={{ fontSize: compact ? 20 : 22, color: 'var(--ink-900)' }}>AI Insights</div>
        <Tag tone="sage">Personalized</Tag>
      </div>
      <p style={{ fontSize: 14, color: 'var(--ink-800)', lineHeight: 1.65, margin: 0 }}>
        Overall, Eleanor had a calm but slightly less active week. Sleep was a little shorter and outside time dipped on Thursday and Friday — nothing alarming, but a gentle check-in would be kind. Mobility and morning routines were rock-solid.
      </p>
      <div style={{ marginTop: 18, display: 'grid', gridTemplateColumns: compact ? '1fr' : '1fr 1fr', gap: 12 }}>
        {INSIGHT_SECTIONS.map(s => (
          <div key={s.title} style={{
            padding: '12px 14px', background: 'var(--bg-soft)', borderRadius: 12,
            border: '1px solid var(--line)',
          }}>
            <div style={{ fontSize: 11.5, fontWeight: 700, color: 'var(--sage-800)', textTransform: 'uppercase', letterSpacing: '.08em' }}>{s.title}</div>
            <div style={{ fontSize: 13, color: 'var(--ink-700)', marginTop: 4, lineHeight: 1.55 }}>{s.body}</div>
          </div>
        ))}
      </div>
      <div style={{ marginTop: 18 }}>
        <div style={{ fontSize: 12.5, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 8 }}>Recommended actions</div>
        <ul style={{ margin: 0, padding: 0, listStyle: 'none', display: 'grid', gap: 9 }}>
          {RECOMMENDATIONS.map((r, i) => (
            <li key={i} style={{ display: 'flex', gap: 10, alignItems: 'flex-start', fontSize: 13.5, color: 'var(--ink-800)', lineHeight: 1.5 }}>
              <span style={{
                width: 22, height: 22, borderRadius: '50%',
                background: 'var(--sage-100)', color: 'var(--sage-800)',
                fontSize: 11, fontWeight: 700, display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexShrink: 0, marginTop: 1,
              }}>{i + 1}</span>
              <span>{r}</span>
            </li>
          ))}
        </ul>
      </div>
    </Card>
  );
}

// ── Loading overlay (used by Refresh) ────────────────────────
function GeneratingOverlay() {
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 50,
      background: 'rgba(242,237,223,.86)', backdropFilter: 'blur(8px)',
      WebkitBackdropFilter: 'blur(8px)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <div style={{ textAlign: 'center', padding: 24, maxWidth: 320 }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 18 }}>
          <div style={{ position: 'relative', width: 72, height: 72 }}>
            <div style={{
              position: 'absolute', inset: 0, borderRadius: '50%',
              border: '3px solid var(--sage-200)',
              borderTopColor: 'var(--sage-700)',
              animation: 'shSpin 1.1s linear infinite',
            }}/>
            <div style={{
              position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: 'var(--sage-800)',
            }}><Ico.Sparkle size={28}/></div>
          </div>
        </div>
        <div className="sh-display" style={{ fontSize: 22, color: 'var(--ink-900)' }}>Generating your report</div>
        <div style={{ marginTop: 8, fontSize: 13.5, color: 'var(--ink-600)', lineHeight: 1.5 }}>
          This may take a moment. We’re reviewing the last 7 days of activity and writing a fresh summary.
        </div>
      </div>
    </div>
  );
}

// ── Empty state ──────────────────────────────────────────────
function SummaryEmpty({ kind = 'none' }) {
  // kind: 'none' (no report ever) | 'insufficient'
  return (
    <Card padding={32}>
      <div style={{ textAlign: 'center', maxWidth: 380, marginInline: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 14 }}>
          <IconWell tone="sage" size={64}>
            {kind === 'none' ? <Ico.Chart size={28}/> : <Ico.Clock size={28}/>}
          </IconWell>
        </div>
        <div className="sh-display" style={{ fontSize: 22, color: 'var(--ink-900)' }}>
          {kind === 'none' ? 'No weekly report available yet' : 'A little more data needed'}
        </div>
        <div style={{ marginTop: 10, fontSize: 14, color: 'var(--ink-600)', lineHeight: 1.55 }}>
          {kind === 'none'
            ? 'Once Eleanor has lived with the sensors for a few days, we’ll start producing a personalized weekly summary.'
            : 'Insufficient data — at least 5 days of sensor activity are required to generate a report. We have 2 so far.'}
        </div>
      </div>
    </Card>
  );
}

// ── Mobile summary ───────────────────────────────────────────
function SummaryMobile({ loading = false }) {
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <MobileShell active="summary">
        <MobileTopBar
          subtitle="Last 7 days"
          title="Weekly Summary"
          right={
            <Button variant="primary" size="sm" leading={<Ico.Refresh size={14}/>}>Refresh</Button>
          }
        />
        <div style={{ padding: '0 16px', display: 'grid', gridTemplateColumns: 'minmax(0,1fr)', gap: 12 }}>
          {/* Snapshot — top metric cards in 2-col grid */}
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) minmax(0,1fr)', gap: 8 }}>
            {METRICS.slice(0, 4).map(m => <MetricCard key={m.title} {...m} compact/>)}
          </div>

          <ChartCard
            compact
            title="Sleep"
            subtitle="Hours slept + overnight interruptions"
            legend={[
              { color: '#4F6B53', label: 'Hours' },
              { color: '#C99544', label: 'Interruptions' },
            ]}
          >
            <SleepChart width={340} height={170} dense/>
          </ChartCard>

          <ChartCard
            compact
            title="Activity"
            subtitle="Transitions, kitchen events, outside minutes"
            legend={[
              { color: '#6B8B6E', label: 'Transitions' },
              { color: '#C99544', label: 'Kitchen' },
              { color: '#704863', label: 'Outside (min)' },
            ]}
          >
            <ActivityChart width={340} height={170}/>
          </ChartCard>

          {/* remaining metrics */}
          <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) minmax(0,1fr)', gap: 8 }}>
            {METRICS.slice(4).map(m => <MetricCard key={m.title} {...m} compact/>)}
          </div>

          <AIInsightsBlock compact/>
        </div>
      </MobileShell>
      {loading && <GeneratingOverlay/>}
    </div>
  );
}

// ── Desktop summary ──────────────────────────────────────────
function SummaryDesktop({ loading = false, emptyKind }) {
  return (
    <div style={{ position: 'relative', width: '100%', height: '100%' }}>
      <DesktopShell active="summary"
        topbar={
          <div style={{
            padding: '20px 36px', borderBottom: '1px solid var(--line)',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            background: 'var(--bg-cream)',
          }}>
            <div>
              <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>May 10 — May 16 · cached locally</div>
              <div className="sh-display" style={{ fontSize: 28, color: 'var(--ink-900)', marginTop: 2 }}>Weekly Summary</div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <Tag tone="neutral" icon={<Ico.Clock size={12}/>}>Generated Mon 8:02 AM</Tag>
              <Button variant="primary" leading={<Ico.Refresh size={16}/>}>Generate fresh report</Button>
            </div>
          </div>
        }
      >
        {emptyKind ? (
          <div style={{ padding: 36, maxWidth: 600, margin: '40px auto' }}>
            <SummaryEmpty kind={emptyKind}/>
          </div>
        ) : (
          <div style={{ padding: 32, display: 'grid', gridTemplateColumns: '2fr 1fr', gap: 24 }}>
            <div style={{ display: 'grid', gap: 20 }}>
              <ChartCard
                title="Sleep"
                subtitle="Hours slept per night with overnight interruptions"
                legend={[
                  { color: '#4F6B53', label: 'Hours slept' },
                  { color: '#C99544', label: 'Interruptions' },
                ]}
              >
                <SleepChart width={620} height={240}/>
              </ChartCard>
              <ChartCard
                title="Activity"
                subtitle="Daily room transitions, kitchen events, and time outside"
                legend={[
                  { color: '#6B8B6E', label: 'Transitions' },
                  { color: '#C99544', label: 'Kitchen triggers' },
                  { color: '#704863', label: 'Outside (min)' },
                ]}
              >
                <ActivityChart width={620} height={240}/>
              </ChartCard>
              <AIInsightsBlock/>
            </div>
            <div style={{ display: 'grid', gap: 14, alignContent: 'start' }}>
              <div className="sh-display" style={{ fontSize: 20, color: 'var(--ink-900)' }}>By the numbers</div>
              {METRICS.map(m => <MetricCard key={m.title} {...m}/>)}
            </div>
          </div>
        )}
      </DesktopShell>
      {loading && <GeneratingOverlay/>}
    </div>
  );
}

Object.assign(window, {
  SummaryMobile, SummaryDesktop, SummaryEmpty,
  SleepChart, ActivityChart, MetricCard, AIInsightsBlock, GeneratingOverlay,
});
