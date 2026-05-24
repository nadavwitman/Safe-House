// profile-admin.jsx — Profile, Admin Search, Admin Create House

// ── Profile section ──────────────────────────────────────────
function ProfileRow({ label, value, action }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, padding: '14px 16px',
      borderBottom: '1px solid var(--line)',
    }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>{label}</div>
        <div style={{ fontSize: 15, color: 'var(--ink-900)', marginTop: 3 }}>{value}</div>
      </div>
      {action}
    </div>
  );
}

// ── Vacation scheduling helpers ──────────────────────────────
function parseLocalDT(dateStr, timeStr) {
  if (!dateStr || !timeStr) return null;
  const [y, m, d] = dateStr.split('-').map(Number);
  const [hh, mm] = timeStr.split(':').map(Number);
  return new Date(y, m - 1, d, hh, mm);
}
function fmtDT(dateStr, timeStr) {
  const dt = parseLocalDT(dateStr, timeStr);
  if (!dt) return '—';
  const day = dt.toLocaleDateString('en-US', { weekday: 'short', month: 'short', day: 'numeric' });
  const time = dt.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  return `${day} · ${time}`;
}
function relDays(dateStr, timeStr) {
  const dt = parseLocalDT(dateStr, timeStr);
  if (!dt) return '';
  const now = new Date();
  const diff = Math.round((dt - now) / (1000 * 60 * 60 * 24));
  if (diff < 0) return `${-diff} day${-diff === 1 ? '' : 's'} ago`;
  if (diff === 0) return 'today';
  if (diff === 1) return 'tomorrow';
  return `in ${diff} days`;
}
function toISODate(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}
function parseISODate(s) {
  if (!s) return null;
  const [y, m, d] = s.split('-').map(Number);
  return new Date(y, m - 1, d);
}

// ── Custom Calendar popover ──────────────────────────────────
function CalendarPopover({ value, minDate, onPick, onClose }) {
  const initial = parseISODate(value) || new Date();
  const [view, setView] = React.useState(new Date(initial.getFullYear(), initial.getMonth(), 1));
  const today = new Date(); today.setHours(0,0,0,0);
  const min = parseISODate(minDate);
  if (min) min.setHours(0,0,0,0);

  const y = view.getFullYear(), m = view.getMonth();
  const firstDay = new Date(y, m, 1);
  const daysInMonth = new Date(y, m + 1, 0).getDate();
  const startWeekday = firstDay.getDay(); // 0=Sun
  const cells = [];
  for (let i = 0; i < startWeekday; i++) cells.push(null);
  for (let d = 1; d <= daysInMonth; d++) cells.push(new Date(y, m, d));
  while (cells.length % 7 !== 0) cells.push(null);

  const selected = parseISODate(value);
  const monthLabel = view.toLocaleDateString('en-US', { month: 'long', year: 'numeric' });
  const sameDay = (a, b) => a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
  const isDisabled = (d) => min && d < min;
  const stepMonth = (delta) => setView(new Date(y, m + delta, 1));

  return (
    <div onMouseDown={e => e.stopPropagation()} style={{
      width: 280, padding: 14, background: 'var(--card-2)',
      border: '1px solid var(--line)', borderRadius: 16,
      boxShadow: 'var(--shadow-lg)',
      animation: 'shFade .15s ease',
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
        <button type="button" onClick={() => stepMonth(-1)} style={navBtnStyle()}>
          <Ico.ChevronRight size={16} style={{ transform: 'rotate(180deg)' }}/>
        </button>
        <div className="sh-display" style={{ fontSize: 15, color: 'var(--ink-900)' }}>{monthLabel}</div>
        <button type="button" onClick={() => stepMonth(1)} style={navBtnStyle()}>
          <Ico.ChevronRight size={16}/>
        </button>
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2, marginBottom: 4 }}>
        {['S','M','T','W','T','F','S'].map((w, i) => (
          <div key={i} style={{ textAlign: 'center', fontSize: 10.5, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.05em', padding: '4px 0' }}>{w}</div>
        ))}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', gap: 2 }}>
        {cells.map((d, i) => {
          if (!d) return <div key={i}/>;
          const isToday = sameDay(d, today);
          const isSelected = sameDay(d, selected);
          const dis = isDisabled(d);
          return (
            <button type="button" key={i}
              disabled={dis}
              onClick={() => { onPick(toISODate(d)); onClose && onClose(); }}
              style={{
                aspectRatio: '1', padding: 0, border: 'none',
                borderRadius: 10, cursor: dis ? 'not-allowed' : 'pointer',
                background: isSelected ? 'var(--sage-700)' : isToday ? 'var(--sage-100)' : 'transparent',
                color: isSelected ? '#FBF8F0' : dis ? 'var(--ink-300)' : 'var(--ink-800)',
                fontSize: 13, fontWeight: isSelected ? 700 : 500,
                fontVariantNumeric: 'tabular-nums',
                transition: 'background .12s',
              }}
              onMouseEnter={e => { if (!isSelected && !dis) e.currentTarget.style.background = 'var(--bg-soft)'; }}
              onMouseLeave={e => { if (!isSelected && !dis) e.currentTarget.style.background = isToday ? 'var(--sage-100)' : 'transparent'; }}
            >{d.getDate()}</button>
          );
        })}
      </div>
      <div style={{ marginTop: 12, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        <button type="button" onClick={() => { onPick(toISODate(today)); onClose && onClose(); }}
          style={{
            padding: '5px 10px', borderRadius: 999, border: '1px solid var(--line-2)',
            background: 'var(--card)', color: 'var(--ink-700)', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
          }}>Today</button>
        <button type="button" onClick={onClose}
          style={{ padding: '5px 10px', border: 'none', background: 'transparent', color: 'var(--ink-600)', fontSize: 12, cursor: 'pointer' }}>Close</button>
      </div>
    </div>
  );
}
function navBtnStyle() {
  return {
    width: 28, height: 28, borderRadius: 8, border: '1px solid var(--line)',
    background: 'var(--card)', color: 'var(--ink-700)', cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0,
  };
}

// ── Custom Time popover (hour wheel · minute wheel · AM/PM) ──
function TimePopover({ value, onPick, onClose }) {
  const parse = (v) => {
    if (!v) return { h: 9, m: 0, ap: 'AM' };
    const [hh, mm] = v.split(':').map(Number);
    const ap = hh >= 12 ? 'PM' : 'AM';
    const h12 = hh % 12 === 0 ? 12 : hh % 12;
    return { h: h12, m: mm, ap };
  };
  const [{ h, m, ap }, set] = React.useState(parse(value));

  const commit = (nh, nm, nap) => {
    let h24 = nh % 12;
    if (nap === 'PM') h24 += 12;
    const v = `${String(h24).padStart(2, '0')}:${String(nm).padStart(2, '0')}`;
    onPick(v);
  };

  const wheel = (items, cur, onClick) => (
    <div style={{
      flex: 1, height: 168, overflow: 'auto', borderRadius: 10,
      background: 'var(--bg-soft)', border: '1px solid var(--line)',
      scrollbarWidth: 'none', padding: '4px 0',
    }}>
      {items.map(v => {
        const active = v === cur;
        return (
          <button type="button" key={v} onClick={() => onClick(v)}
            style={{
              display: 'block', width: '100%', border: 'none',
              padding: '8px 0', textAlign: 'center', cursor: 'pointer',
              background: active ? 'var(--sage-700)' : 'transparent',
              color: active ? '#FBF8F0' : 'var(--ink-800)',
              fontSize: 14, fontWeight: active ? 700 : 500,
              fontVariantNumeric: 'tabular-nums',
              borderRadius: 8,
            }}>
            {String(v).padStart(2, '0')}
          </button>
        );
      })}
    </div>
  );

  const hours = Array.from({ length: 12 }, (_, i) => i + 1);
  const mins = Array.from({ length: 12 }, (_, i) => i * 5);

  return (
    <div onMouseDown={e => e.stopPropagation()} style={{
      width: 250, padding: 14, background: 'var(--card-2)',
      border: '1px solid var(--line)', borderRadius: 16,
      boxShadow: 'var(--shadow-lg)',
      animation: 'shFade .15s ease',
    }}>
      <div style={{
        marginBottom: 10, padding: '8px 10px', borderRadius: 10,
        background: 'var(--sage-50)', border: '1px solid var(--sage-200)',
        textAlign: 'center',
      }}>
        <div className="sh-display sh-numeric" style={{ fontSize: 22, color: 'var(--sage-800)', letterSpacing: '.01em' }}>
          {h}:{String(m).padStart(2, '0')} <span style={{ fontSize: 14, marginLeft: 4 }}>{ap}</span>
        </div>
      </div>
      <div style={{ display: 'flex', gap: 6, alignItems: 'stretch' }}>
        {wheel(hours, h, (nh) => { set(s => ({ ...s, h: nh })); commit(nh, m, ap); })}
        <div style={{ display: 'flex', alignItems: 'center', fontSize: 14, color: 'var(--ink-500)' }}>:</div>
        {wheel(mins, m, (nm) => { set(s => ({ ...s, m: nm })); commit(h, nm, ap); })}
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, width: 56 }}>
          {['AM','PM'].map(p => (
            <button type="button" key={p}
              onClick={() => { set(s => ({ ...s, ap: p })); commit(h, m, p); }}
              style={{
                flex: 1, borderRadius: 10, border: '1px solid var(--line)',
                background: ap === p ? 'var(--sage-700)' : 'var(--card)',
                color: ap === p ? '#FBF8F0' : 'var(--ink-800)',
                fontSize: 13, fontWeight: 700, cursor: 'pointer',
              }}>{p}</button>
          ))}
        </div>
      </div>
      <div style={{ marginTop: 12, display: 'flex', justifyContent: 'flex-end' }}>
        <button type="button" onClick={onClose}
          style={{ padding: '5px 10px', border: 'none', background: 'transparent', color: 'var(--ink-600)', fontSize: 12, cursor: 'pointer' }}>Done</button>
      </div>
    </div>
  );
}

// ── DateTimeField — pretty trigger that opens custom popovers ─
function DateTimeField({ label, date, time, onDateChange, onTimeChange, minDate, error }) {
  const [open, setOpen] = React.useState(null); // 'date' | 'time' | null
  const [placement, setPlacement] = React.useState({ date: 'bottom', time: 'bottom' });
  const dateLabel = date
    ? parseISODate(date).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
    : 'Pick a date';
  const timeLabel = (() => {
    if (!time) return 'Pick a time';
    const [hh, mm] = time.split(':').map(Number);
    const ap = hh >= 12 ? 'PM' : 'AM';
    const h12 = hh % 12 === 0 ? 12 : hh % 12;
    return `${h12}:${String(mm).padStart(2, '0')} ${ap}`;
  })();

  const wrapRef = React.useRef(null);
  const dateBtnRef = React.useRef(null);
  const timeBtnRef = React.useRef(null);

  // Close on outside click
  React.useEffect(() => {
    if (!open) return;
    const handler = (e) => {
      if (wrapRef.current && !wrapRef.current.contains(e.target)) setOpen(null);
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [open]);

  // Find nearest scrollable ancestor to measure available room
  const findScrollParent = (el) => {
    let p = el?.parentElement;
    while (p) {
      const cs = getComputedStyle(p);
      if (/(auto|scroll|overlay)/.test(cs.overflowY) || /(auto|scroll|overlay|hidden)/.test(cs.overflow)) return p;
      p = p.parentElement;
    }
    return document.scrollingElement || document.documentElement;
  };

  // Decide placement when opening
  React.useLayoutEffect(() => {
    if (!open) return;
    const btn = open === 'date' ? dateBtnRef.current : timeBtnRef.current;
    if (!btn) return;
    const sp = findScrollParent(btn);
    const spRect = sp.getBoundingClientRect ? sp.getBoundingClientRect() : { top: 0, bottom: window.innerHeight };
    const btnRect = btn.getBoundingClientRect();
    const popHeight = open === 'date' ? 330 : 280;
    const roomBelow = spRect.bottom - btnRect.bottom;
    const roomAbove = btnRect.top - spRect.top;
    const next = (roomBelow < popHeight && roomAbove > roomBelow) ? 'top' : 'bottom';
    setPlacement(p => ({ ...p, [open]: next }));
  }, [open]);

  const trigger = (which, isPlaceholder, content, icon, btnRef) => (
    <button type="button" ref={btnRef}
      onClick={() => setOpen(o => o === which ? null : which)}
      style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '11px 12px', borderRadius: 12,
        background: 'var(--card-2)',
        border: `1.5px solid ${error && which === 'date' ? '#D88A78' : open === which ? 'var(--sage-600)' : 'var(--line-2)'}`,
        boxShadow: open === which ? '0 0 0 4px rgba(143,170,140,.18)' : 'none',
        width: '100%', minWidth: 0,
        cursor: 'pointer', textAlign: 'left',
        color: isPlaceholder ? 'var(--ink-500)' : 'var(--ink-900)',
        fontSize: 14, fontFamily: 'var(--ui)', fontVariantNumeric: 'tabular-nums',
        transition: 'box-shadow .15s, border-color .15s',
      }}>
      <span style={{ color: 'var(--ink-500)', display: 'flex', flexShrink: 0 }}>{icon}</span>
      <span style={{ flex: 1, minWidth: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{content}</span>
      <Ico.ChevronDown size={14} style={{ color: 'var(--ink-500)', flexShrink: 0 }}/>
    </button>
  );

  const popStyle = (which, side) => {
    const offset = 'calc(100% + 6px)';
    return side === 'top'
      ? { position: 'absolute', bottom: offset, zIndex: 30, [which === 'date' ? 'left' : 'right']: 0 }
      : { position: 'absolute', top: offset, zIndex: 30, [which === 'date' ? 'left' : 'right']: 0 };
  };

  return (
    <div ref={wrapRef} style={{ position: 'relative' }}>
      <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-700)', marginBottom: 7, letterSpacing: '.02em' }}>{label}</div>
      <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0, 1.4fr) minmax(0, 1fr)', gap: 8 }}>
        {trigger('date', !date, dateLabel, <Ico.Calendar size={15}/>, dateBtnRef)}
        {trigger('time', !time, timeLabel, <Ico.Clock size={15}/>, timeBtnRef)}
      </div>
      {open === 'date' && (
        <div style={popStyle('date', placement.date)}>
          <CalendarPopover
            value={date} minDate={minDate}
            onPick={(v) => onDateChange && onDateChange(v)}
            onClose={() => setOpen(null)}
          />
        </div>
      )}
      {open === 'time' && (
        <div style={popStyle('time', placement.time)}>
          <TimePopover
            value={time}
            onPick={(v) => onTimeChange && onTimeChange(v)}
            onClose={() => setOpen(null)}
          />
        </div>
      )}
    </div>
  );
}

function ScheduleEditor({ initial, onCancel, onSave }) {
  const today = new Date().toISOString().slice(0, 10);
  const [startDate, setStartDate] = React.useState(initial?.startDate || '');
  const [startTime, setStartTime] = React.useState(initial?.startTime || '09:00');
  const [endDate, setEndDate]     = React.useState(initial?.endDate || '');
  const [endTime, setEndTime]     = React.useState(initial?.endTime || '18:00');
  const start = parseLocalDT(startDate, startTime);
  const end   = parseLocalDT(endDate, endTime);
  const incomplete   = !startDate || !endDate;
  const invalidRange = start && end && end <= start;
  const error = invalidRange ? 'End must be after start.' : null;

  const presetWeekend = () => {
    const now = new Date();
    const sat = new Date(now); sat.setDate(now.getDate() + ((6 - now.getDay() + 7) % 7 || 7));
    const sun = new Date(sat); sun.setDate(sat.getDate() + 1);
    setStartDate(toISODate(sat)); setStartTime('09:00');
    setEndDate(toISODate(sun));   setEndTime('18:00');
  };

  return (
    <div style={{
      marginTop: 12, padding: 14, background: 'var(--card-2)',
      border: '1px solid var(--line)', borderRadius: 14,
      animation: 'shFade .25s ease',
      position: 'relative',
    }}>
      <div style={{ fontSize: 13, color: 'var(--ink-700)', marginBottom: 12, lineHeight: 1.5 }}>
        Monitoring will pause automatically at the start time and resume at the end time.
      </div>
      <div style={{ display: 'grid', gap: 12 }}>
        <DateTimeField label="Starts" date={startDate} time={startTime}
          minDate={today} onDateChange={setStartDate} onTimeChange={setStartTime}/>
        <DateTimeField label="Ends" date={endDate} time={endTime}
          minDate={startDate || today} onDateChange={setEndDate} onTimeChange={setEndTime}
          error={error}/>
      </div>
      {error && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8, fontSize: 12.5, color: '#9C4A38' }}>
          <Ico.Alert size={14}/><span>{error}</span>
        </div>
      )}
      <div style={{ marginTop: 12, fontSize: 11.5, color: 'var(--ink-500)', display: 'flex', alignItems: 'center', gap: 7, flexWrap: 'wrap' }}>
        <span>Quick fill:</span>
        <button type="button" onClick={presetWeekend} style={{
          padding: '4px 9px', borderRadius: 999, border: '1px solid var(--line-2)',
          background: 'var(--card)', color: 'var(--ink-700)', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
        }}>This weekend</button>
      </div>
      <div style={{
        marginTop: 14, paddingTop: 12,
        borderTop: '1px solid var(--line)',
        display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center',
      }}>
        <Button size="sm" variant="primary"
          disabled={incomplete || !!error}
          onClick={() => onSave && onSave({ startDate, startTime, endDate, endTime })}>
          Save schedule
        </Button>
        <Button size="sm" variant="ghost" onClick={onCancel}>Cancel</Button>
      </div>
    </div>
  );
}

function VacationToggle({ on, onChange, schedule, onScheduleChange, dense = false, demoEditing = false, demoActiveBySchedule = false }) {
  const [editing, setEditing] = React.useState(demoEditing);
  React.useEffect(() => { if (demoEditing) setEditing(true); }, [demoEditing]);
  const activeBySchedule = demoActiveBySchedule;
  const paused = on || activeBySchedule;

  const status = paused ? 'paused' : (schedule ? 'scheduled' : 'active');
  const meta = ({
    active:    { tone: 'sage', dot: 'ok',   tag: 'Active',
                 body: 'Pauses anomaly detection while Eleanor is away. Schedule a trip ahead, or toggle on instantly.',
                 strong: 'Monitoring active', icon: Ico.Shield },
    scheduled: { tone: 'sage', dot: 'ok',   tag: 'Scheduled',
                 body: 'Monitoring will pause automatically when the trip starts.',
                 strong: 'Monitoring active · scheduled trip ahead', icon: Ico.Clock },
    paused:    { tone: 'warn', dot: 'warn', tag: activeBySchedule ? 'Paused · scheduled' : 'Paused',
                 body: activeBySchedule ? 'Vacation mode is paused as part of a scheduled trip. It will resume automatically.' : 'No alerts will fire until you turn this back off.',
                 strong: activeBySchedule && schedule ? `Monitoring paused — trip ends ${fmtDT(schedule.endDate, schedule.endTime)}` : 'Monitoring paused — vacation mode is on',
                 icon: Ico.Moon },
  })[status];
  const StrongIcon = meta.icon;

  return (
    <div style={{
      borderRadius: 22,
      padding: dense ? 18 : 22,
      background: paused
        ? 'linear-gradient(160deg, #F3DDB8 0%, #ECCB8E 100%)'
        : 'var(--card)',
      border: paused ? '1px solid #E2B664' : '1px solid var(--line)',
      transition: 'background .25s, border-color .25s',
      position: 'relative', overflow: 'hidden',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 14 }}>
        <div style={{
          width: 48, height: 48, borderRadius: '50%',
          background: paused ? '#F8E9C9' : 'var(--sage-100)',
          color: paused ? '#8C6420' : 'var(--sage-800)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          border: paused ? '1px solid #E2B664' : '1px solid var(--sage-200)',
        }}>
          <Ico.Suitcase size={22}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
            <div className="sh-display" style={{ fontSize: 22, color: paused ? '#5C3F12' : 'var(--ink-900)' }}>Vacation Mode</div>
            <Tag tone={meta.tone === 'warn' ? 'warn' : 'sage'} icon={<StatusDot tone={meta.dot}/>}>{meta.tag}</Tag>
          </div>
          <div style={{ marginTop: 6, fontSize: 13.5, color: paused ? '#6E5119' : 'var(--ink-700)', lineHeight: 1.5 }}>
            {meta.body}
          </div>
        </div>
        <Toggle size="lg" checked={paused} onChange={onChange} disabled={activeBySchedule}/>
      </div>

      <div style={{
        marginTop: 16, padding: '12px 14px', borderRadius: 14,
        background: paused ? 'rgba(255,255,255,.5)' : 'var(--bg-soft)',
        border: '1px solid ' + (paused ? 'rgba(226,182,100,.6)' : 'var(--line)'),
        display: 'flex', alignItems: 'center', gap: 10,
        fontSize: 13.5, color: paused ? '#6E5119' : 'var(--ink-700)',
        fontWeight: 600,
      }}>
        <StrongIcon size={16}/>
        <span style={{ flex: 1, minWidth: 0 }}>{meta.strong}</span>
      </div>

      {/* Schedule sub-section */}
      <div style={{
        marginTop: 14, paddingTop: 14,
        borderTop: '1px dashed ' + (paused ? 'rgba(226,182,100,.55)' : 'var(--line-2)'),
      }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10, flexWrap: 'wrap' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, minWidth: 0 }}>
            <Ico.Clock size={16} style={{ color: paused ? '#6E5119' : 'var(--ink-700)', flexShrink: 0 }}/>
            <div style={{ fontSize: 13.5, fontWeight: 700, color: paused ? '#5C3F12' : 'var(--ink-900)' }}>
              {schedule ? (activeBySchedule ? 'Trip in progress' : 'Trip scheduled') : 'Schedule a trip ahead'}
            </div>
          </div>
          {!editing && (
            schedule ? (
              <div style={{ display: 'inline-flex', gap: 4, flexWrap: 'wrap' }}>
                <Button size="sm" variant="ghost" onClick={() => setEditing(true)}>Edit</Button>
                {!activeBySchedule && (
                  <Button size="sm" variant="ghost" onClick={() => onScheduleChange && onScheduleChange(null)}
                    style={{ color: 'var(--alert)' }}>
                    Cancel trip
                  </Button>
                )}
              </div>
            ) : (
              <Button size="sm" variant="soft" leading={<Ico.Plus size={14}/>} onClick={() => setEditing(true)}>
                Plan a trip
              </Button>
            )
          )}
        </div>

        {schedule && !editing && (
          <div style={{
            marginTop: 10, padding: 12, borderRadius: 12,
            background: paused ? 'rgba(255,255,255,.55)' : 'var(--bg-soft)',
            border: '1px solid ' + (paused ? 'rgba(226,182,100,.6)' : 'var(--line)'),
          }}>
            <div style={{ display: 'grid', gridTemplateColumns: 'minmax(0,1fr) 22px minmax(0,1fr)', alignItems: 'center', gap: 8 }}>
              <div>
                <div style={{ fontSize: 10.5, fontWeight: 700, color: paused ? '#7A5419' : 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.06em' }}>Starts</div>
                <div className="sh-numeric" style={{ fontSize: 13.5, fontWeight: 600, color: paused ? '#5C3F12' : 'var(--ink-900)', marginTop: 2 }}>{fmtDT(schedule.startDate, schedule.startTime)}</div>
                <div style={{ fontSize: 11, color: paused ? '#7A5419' : 'var(--ink-500)', marginTop: 1 }}>{relDays(schedule.startDate, schedule.startTime)}</div>
              </div>
              <div style={{ textAlign: 'center', color: paused ? '#A07A2C' : 'var(--ink-400)' }}>
                <Ico.ArrowRight size={16}/>
              </div>
              <div>
                <div style={{ fontSize: 10.5, fontWeight: 700, color: paused ? '#7A5419' : 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.06em' }}>Ends</div>
                <div className="sh-numeric" style={{ fontSize: 13.5, fontWeight: 600, color: paused ? '#5C3F12' : 'var(--ink-900)', marginTop: 2 }}>{fmtDT(schedule.endDate, schedule.endTime)}</div>
                <div style={{ fontSize: 11, color: paused ? '#7A5419' : 'var(--ink-500)', marginTop: 1 }}>{relDays(schedule.endDate, schedule.endTime)}</div>
              </div>
            </div>
          </div>
        )}

        {editing && (
          <ScheduleEditor
            initial={schedule}
            onCancel={() => setEditing(false)}
            onSave={(next) => { onScheduleChange && onScheduleChange(next); setEditing(false); }}
          />
        )}

        {!schedule && !editing && (
          <div style={{ marginTop: 8, fontSize: 12, color: paused ? '#7A5419' : 'var(--ink-500)', lineHeight: 1.5 }}>
            Set start and end times — we{'\u2019'}ll pause and resume monitoring automatically.
          </div>
        )}
      </div>

      {paused && !activeBySchedule && (
        <div style={{ marginTop: 10, fontSize: 12, color: '#7A5419', display: 'flex', alignItems: 'center', gap: 6 }}>
          <Ico.Info size={13}/> Toggle off as soon as Eleanor returns home, or schedule a trip to handle this automatically.
        </div>
      )}
    </div>
  );
}

const HOUSES = [
  { id: 'h1', resident: 'Eleanor Reyes',    address: '24 Linden St · Apt 3B', active: true },
  { id: 'h2', resident: 'Walter Hayashi',   address: '178 Larch Ave',         active: false },
  { id: 'h3', resident: 'Margarita Conti',  address: 'Via Lucina 9 · Roma',   active: false },
];

function HouseSwitcher({ value, onChange, dense = false }) {
  const [open, setOpen] = React.useState(false);
  const cur = HOUSES.find(h => h.id === value) || HOUSES[0];
  return (
    <div style={{ position: 'relative' }}>
      <button onClick={() => setOpen(o => !o)}
        style={{
          width: '100%', padding: dense ? '12px 14px' : '14px 16px',
          background: 'var(--card)', border: '1px solid var(--line)', borderRadius: 14,
          display: 'flex', alignItems: 'center', gap: 12, cursor: 'pointer', textAlign: 'left',
        }}>
        <IconWell tone="sage" size={36}><Ico.Home size={18}/></IconWell>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 12, color: 'var(--ink-500)', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '.08em' }}>Active house</div>
          <div style={{ fontSize: 15, fontWeight: 600, color: 'var(--ink-900)', marginTop: 2 }}>{cur.resident}’s House</div>
        </div>
        <Ico.ChevronDown size={18}/>
      </button>
      {open && (
        <div style={{
          position: 'absolute', top: 'calc(100% + 6px)', left: 0, right: 0,
          background: 'var(--card)', border: '1px solid var(--line)',
          borderRadius: 14, boxShadow: 'var(--shadow-lg)', zIndex: 5, padding: 6,
        }}>
          {HOUSES.map(h => (
            <button key={h.id} onClick={() => { onChange && onChange(h.id); setOpen(false); }}
              style={{
                display: 'flex', alignItems: 'center', gap: 11, width: '100%',
                padding: '10px 10px', border: 'none', background: h.id === value ? 'var(--sage-50)' : 'transparent',
                borderRadius: 10, cursor: 'pointer', textAlign: 'left',
              }}>
              <IconWell tone="sage" size={30}><Ico.Home size={15}/></IconWell>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--ink-900)' }}>{h.resident}</div>
                <div style={{ fontSize: 12, color: 'var(--ink-500)' }}>{h.address}</div>
              </div>
              {h.id === value && <Ico.Check size={16} style={{ color: 'var(--sage-700)' }}/>}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function ProfileMobile({ demoState = 'scheduled' }) {
  // demoState: 'idle' | 'scheduled' | 'editing' | 'live'
  const [activeHouse, setActiveHouse] = React.useState('h1');
  const [vacation, setVacation] = React.useState(false);
  const [schedule, setSchedule] = React.useState(
    demoState === 'idle' || demoState === 'editing'
      ? null
      : demoState === 'live'
        ? { startDate: '2026-05-15', startTime: '08:30', endDate: '2026-05-19', endTime: '20:00' }
        : { startDate: '2026-05-22', startTime: '08:30', endDate: '2026-05-26', endTime: '20:00' }
  );
  return (
    <MobileShell active="profile">
      <MobileTopBar
        subtitle="Account"
        title="Profile"
      />
      <div style={{ padding: '0 20px', display: 'grid', gap: 16 }}>
        <Card padding={0} style={{ overflow: 'hidden' }}>
          <div style={{ padding: '20px 16px', display: 'flex', alignItems: 'center', gap: 14, background: 'var(--card-3)', borderBottom: '1px solid var(--line)' }}>
            <div style={{
              width: 56, height: 56, borderRadius: '50%',
              background: 'var(--sage-200)', color: 'var(--sage-800)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: 'var(--display)', fontSize: 24, fontWeight: 600,
            }}>MR</div>
            <div style={{ minWidth: 0, flex: 1 }}>
              <div className="sh-display" style={{ fontSize: 20, color: 'var(--ink-900)' }}>Mara Reyes</div>
              <div style={{ fontSize: 13, color: 'var(--ink-600)' }}>mara@family.com</div>
            </div>
          </div>
          <ProfileRow label="Username" value="mara_r" action={<Button variant="ghost" size="sm">Edit</Button>}/>
          <ProfileRow label="Password" value="••••••••••" action={<Button variant="ghost" size="sm">Change</Button>}/>
          <ProfileRow label="Notifications" value="Push & SMS enabled" action={<Button variant="ghost" size="sm">Manage</Button>}/>
        </Card>

        <div>
          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 8, paddingInline: 4 }}>Houses</div>
          <HouseSwitcher value={activeHouse} onChange={setActiveHouse} dense/>
          <div style={{ marginTop: 6, fontSize: 12, color: 'var(--ink-500)', paddingInline: 4 }}>You belong to {HOUSES.length} houses.</div>
        </div>

        <VacationToggle
          on={vacation} onChange={setVacation}
          schedule={schedule} onScheduleChange={setSchedule}
          demoEditing={demoState === 'editing'}
          demoActiveBySchedule={demoState === 'live'}
          dense
        />

        <div style={{ marginTop: 4 }}>
          <Button variant="ghost" leading={<Ico.Logout size={18}/>} full
            style={{ justifyContent: 'flex-start', color: 'var(--alert)' }}>
            Sign out
          </Button>
        </div>
      </div>
    </MobileShell>
  );
}

function ProfileDesktop({ demoState = 'live' }) {
  const [activeHouse, setActiveHouse] = React.useState('h1');
  const [vacation, setVacation] = React.useState(false);
  const [schedule, setSchedule] = React.useState(
    demoState === 'idle' || demoState === 'editing'
      ? null
      : demoState === 'scheduled'
        ? { startDate: '2026-05-22', startTime: '09:00', endDate: '2026-05-26', endTime: '17:00' }
        : { startDate: '2026-05-15', startTime: '09:00', endDate: '2026-05-19', endTime: '17:00' }
  );
  return (
    <DesktopShell active="profile" topbar={
      <div style={{
        padding: '20px 36px', borderBottom: '1px solid var(--line)',
        background: 'var(--bg-cream)',
      }}>
        <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>Account</div>
        <div className="sh-display" style={{ fontSize: 28, color: 'var(--ink-900)', marginTop: 2 }}>Profile</div>
      </div>
    }>
      <div style={{ padding: 36, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 24, maxWidth: 1100 }}>
        <div style={{ display: 'grid', gap: 20 }}>
          <Card padding={0} style={{ overflow: 'hidden' }}>
            <div style={{ padding: '24px 22px', display: 'flex', alignItems: 'center', gap: 16, background: 'var(--card-3)' }}>
              <div style={{
                width: 64, height: 64, borderRadius: '50%',
                background: 'var(--sage-200)', color: 'var(--sage-800)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                fontFamily: 'var(--display)', fontSize: 28, fontWeight: 600,
              }}>MR</div>
              <div style={{ flex: 1 }}>
                <div className="sh-display" style={{ fontSize: 24, color: 'var(--ink-900)' }}>Mara Reyes</div>
                <div style={{ fontSize: 13.5, color: 'var(--ink-600)' }}>mara@family.com · Family member</div>
              </div>
              <Button variant="outline" size="sm">Edit profile</Button>
            </div>
            <ProfileRow label="Username" value="mara_r" action={<Button variant="ghost" size="sm">Edit</Button>}/>
            <ProfileRow label="Password" value="Last changed 2 months ago" action={<Button variant="ghost" size="sm">Change password</Button>}/>
            <ProfileRow label="Email" value="mara@family.com" action={<Button variant="ghost" size="sm">Edit</Button>}/>
            <ProfileRow label="Notifications" value="Push, Email, SMS for emergencies" action={<Button variant="ghost" size="sm">Manage</Button>}/>
          </Card>

          <Card padding={20}>
            <div className="sh-display" style={{ fontSize: 20, color: 'var(--ink-900)' }}>House switcher</div>
            <div style={{ fontSize: 13, color: 'var(--ink-600)', marginTop: 4, marginBottom: 14 }}>
              You belong to {HOUSES.length} houses. Selecting one sets it as active across the app.
            </div>
            <HouseSwitcher value={activeHouse} onChange={setActiveHouse}/>
          </Card>
        </div>

        <div style={{ display: 'grid', gap: 20, alignContent: 'start' }}>
          <VacationToggle
            on={vacation} onChange={setVacation}
            schedule={schedule} onScheduleChange={setSchedule}
            demoEditing={demoState === 'editing'}
            demoActiveBySchedule={demoState === 'live'}
          />

          <Card padding={20}>
            <div className="sh-display" style={{ fontSize: 20, color: 'var(--ink-900)' }}>Privacy at a glance</div>
            <div style={{ fontSize: 13, color: 'var(--ink-600)', marginTop: 4, marginBottom: 14 }}>
              What Safe House sees and doesn’t.
            </div>
            <div style={{ display: 'grid', gap: 10 }}>
              {[
                { ok: true,  label: 'Door, motion, occupancy signals'  },
                { ok: true,  label: 'Medication cabinet open/close events'},
                { ok: false, label: 'Audio or video — never recorded'  },
                { ok: false, label: 'Location outside the home — never tracked' },
              ].map(r => (
                <div key={r.label} style={{
                  display: 'flex', alignItems: 'center', gap: 10,
                  padding: '10px 12px', borderRadius: 12,
                  background: r.ok ? 'var(--sage-50)' : 'var(--bg-soft)',
                  border: '1px solid ' + (r.ok ? 'var(--sage-200)' : 'var(--line)'),
                }}>
                  <span style={{
                    width: 22, height: 22, borderRadius: '50%',
                    background: r.ok ? 'var(--sage-600)' : '#C2BCA8',
                    color: '#FBF8F0', display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}>{r.ok ? <Ico.Check size={13} sw={2.2}/> : <Ico.X size={13} sw={2.2}/>}</span>
                  <span style={{ fontSize: 13.5, color: 'var(--ink-800)' }}>{r.label}</span>
                </div>
              ))}
            </div>
          </Card>

          <Button variant="ghost" leading={<Ico.Logout size={18}/>} style={{ justifyContent: 'flex-start', color: 'var(--alert)' }}>
            Sign out of Safe House
          </Button>
        </div>
      </div>
    </DesktopShell>
  );
}

// ── Admin: Copy chip ─────────────────────────────────────────
function CopyChip({ label, value, mono = true }) {
  const [copied, setCopied] = React.useState(false);
  return (
    <div>
      {label && <div style={{ fontSize: 11.5, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em', marginBottom: 6 }}>{label}</div>}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '10px 12px', background: 'var(--bg-soft)',
        border: '1px solid var(--line)', borderRadius: 12,
      }}>
        <code style={{
          flex: 1, fontFamily: mono ? 'ui-monospace, "SF Mono", Menlo, monospace' : 'inherit',
          fontSize: 13.5, color: 'var(--ink-900)', wordBreak: 'break-all',
        }}>{value}</code>
        <button onClick={() => { setCopied(true); setTimeout(() => setCopied(false), 1400); }}
          style={{
            display: 'inline-flex', alignItems: 'center', gap: 5,
            padding: '6px 10px', borderRadius: 8, border: '1px solid var(--line)',
            background: copied ? 'var(--sage-100)' : 'var(--card)',
            color: copied ? 'var(--sage-800)' : 'var(--ink-700)',
            fontSize: 12, fontWeight: 600, cursor: 'pointer',
          }}>
          {copied ? <><Ico.Check size={13} sw={2.2}/> Copied</> : <><Ico.Copy size={13}/> Copy</>}
        </button>
      </div>
    </div>
  );
}

// ── Admin: Confirm-step button (two-tap to fire) ─────────────
function ConfirmButton({ label, confirm = 'Confirm', icon, danger = false }) {
  const [step, setStep] = React.useState(0); // 0 idle | 1 confirming
  return step === 0 ? (
    <Button variant={danger ? 'dangerSoft' : 'soft'} size="sm" leading={icon} onClick={() => setStep(1)}>
      {label}
    </Button>
  ) : (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
      <span style={{ fontSize: 12, color: 'var(--ink-600)', fontWeight: 600 }}>Are you sure?</span>
      <Button variant={danger ? 'danger' : 'primary'} size="sm">{confirm}</Button>
      <Button variant="ghost" size="sm" onClick={() => setStep(0)}>Cancel</Button>
    </div>
  );
}

// ── Sensor mask grid ─────────────────────────────────────────
function SensorMaskGrid({ compact = false }) {
  const [enabled, setEnabled] = React.useState({
    door: true, kitchen: true, bath: true, toilet: true,
    meds: true, bed: true, living: false,
  });
  return (
    <div style={{ display: 'grid', gridTemplateColumns: compact ? '1fr' : '1fr 1fr', gap: 8 }}>
      {SENSOR_LIST.map(s => {
        const Icon = s.icon;
        const on = enabled[s.id];
        return (
          <div key={s.id} style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 14px', borderRadius: 14,
            background: 'var(--bg-soft)', border: '1px solid var(--line)',
            opacity: on ? 1 : 0.7,
          }}>
            <IconWell tone={on ? s.tone : 'cream'} size={36}><Icon size={18}/></IconWell>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--ink-900)' }}>{s.name}</div>
              <div style={{ fontSize: 11.5, color: on ? 'var(--sage-700)' : 'var(--ink-500)', fontWeight: 600 }}>
                {on ? 'Enabled' : 'Disabled'}
              </div>
            </div>
            <Toggle checked={on} onChange={v => setEnabled(e => ({...e, [s.id]: v}))}/>
          </div>
        );
      })}
    </div>
  );
}

// ── Admin Search screen ──────────────────────────────────────
function AdminSearchScreen({ state = 'found', desktop = false }) {
  // state: 'empty' | 'noresult' | 'found'
  const [query, setQuery] = React.useState(
    state === 'noresult' ? 'HX-902-77' :
    state === 'found'    ? 'AHE-4421-EL' : ''
  );

  const foundCard = (
    <Card padding={0} style={{ overflow: 'hidden' }}>
      <div style={{ padding: '20px 22px', display: 'flex', alignItems: 'center', gap: 14, background: 'var(--card-3)', borderBottom: '1px solid var(--line)' }}>
        <IconWell tone="sage" size={48}><Ico.HomeCheck size={22}/></IconWell>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 12, fontWeight: 700, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>House · AHE-4421-EL</div>
          <div className="sh-display" style={{ fontSize: 22, color: 'var(--ink-900)' }}>Eleanor Reyes</div>
          <div style={{ fontSize: 13, color: 'var(--ink-600)', marginTop: 2 }}>24 Linden St · Apt 3B · Brooklyn, NY</div>
        </div>
        <Tag tone="sage" icon={<StatusDot tone="ok"/>}>Active</Tag>
      </div>

      <div style={{ padding: 22, display: 'grid', gap: 18 }}>
        <div style={{ display: 'grid', gridTemplateColumns: desktop ? '1fr 1fr' : '1fr', gap: 14 }}>
          <CopyChip label="Invite code" value="AHE-7842-FAM"/>
          <CopyChip label="Device token" value="esp32_5dc9f1a4-3b88-4f2e-91ce-7a01c2b9ee70"/>
        </div>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
          <ConfirmButton label="Regenerate invite code" icon={<Ico.Refresh size={14}/>}/>
          <ConfirmButton label="Rotate device token" icon={<Ico.Refresh size={14}/>} danger/>
        </div>

        <div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 10 }}>
            <div className="sh-display" style={{ fontSize: 17, color: 'var(--ink-900)' }}>Active users · 3</div>
            <Button variant="ghost" size="sm" leading={<Ico.Plus size={14}/>}>Invite</Button>
          </div>
          <div style={{ display: 'grid', gap: 8 }}>
            {[
              { name: 'Mara Reyes', email: 'mara@family.com', role: 'Family' },
              { name: 'David Reyes', email: 'david.r@family.com', role: 'Family' },
              { name: 'Care Aide · Ines', email: 'ines@careco.io', role: 'Caregiver' },
            ].map(u => (
              <div key={u.email} style={{
                display: 'flex', alignItems: 'center', gap: 12,
                padding: '12px 14px', borderRadius: 14,
                background: 'var(--bg-soft)', border: '1px solid var(--line)',
              }}>
                <div style={{
                  width: 36, height: 36, borderRadius: '50%',
                  background: 'var(--sage-100)', color: 'var(--sage-800)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontWeight: 700, fontSize: 13,
                }}>{u.name.split(' ').map(p => p[0]).slice(0,2).join('')}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--ink-900)' }}>{u.name}</div>
                  <div style={{ fontSize: 12, color: 'var(--ink-500)' }}>{u.email} · {u.role}</div>
                </div>
                <Button variant="ghost" size="sm" style={{ color: 'var(--alert)' }}>Remove</Button>
              </div>
            ))}
          </div>
        </div>

        <div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 4 }}>
            <div className="sh-display" style={{ fontSize: 17, color: 'var(--ink-900)' }}>Sensor mask</div>
            <span style={{ fontSize: 12, color: 'var(--ink-500)' }}>Toggle physical sensors on or off</span>
          </div>
          <div style={{ marginTop: 10 }}>
            <SensorMaskGrid compact={!desktop}/>
          </div>
        </div>
      </div>
    </Card>
  );

  const noresultCard = (
    <Card padding={32}>
      <div style={{ textAlign: 'center', maxWidth: 360, marginInline: 'auto' }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 14 }}>
          <div style={{
            width: 72, height: 72, borderRadius: '50%',
            background: 'var(--bg-soft)', border: '1px dashed var(--line-2)',
            display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink-500)',
          }}>
            <Ico.Search size={28}/>
          </div>
        </div>
        <div className="sh-display" style={{ fontSize: 22, color: 'var(--ink-900)' }}>No house found with this ID</div>
        <div style={{ marginTop: 8, fontSize: 14, color: 'var(--ink-600)', lineHeight: 1.55 }}>
          Double-check the ID for typos, or create a new house if one hasn’t been set up yet.
        </div>
        <div style={{ marginTop: 18, display: 'flex', gap: 10, justifyContent: 'center' }}>
          <Button variant="outline" size="sm">Try again</Button>
          <Button variant="primary" size="sm" leading={<Ico.Plus size={14}/>}>Create new house</Button>
        </div>
      </div>
    </Card>
  );

  const searchBlock = (
    <div style={{ display: 'flex', gap: 10 }}>
      <div style={{ flex: 1 }}>
        <Input
          icon={<Ico.Search size={18}/>}
          value={query} onChange={setQuery}
          placeholder="Search by House ID (e.g. AHE-4421-EL)"
        />
      </div>
      <Button variant="primary" leading={<Ico.Search size={16}/>}>Search</Button>
    </div>
  );

  if (desktop) {
    return (
      <DesktopShell active="search" kind="admin" residentName="Admin Console" topbar={
        <div style={{
          padding: '20px 36px', borderBottom: '1px solid var(--line)',
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          background: 'var(--bg-cream)',
        }}>
          <div>
            <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>Admin</div>
            <div className="sh-display" style={{ fontSize: 28, color: 'var(--ink-900)', marginTop: 2 }}>House Search</div>
          </div>
          <Button variant="primary" leading={<Ico.Plus size={16}/>}>Create new house</Button>
        </div>
      }>
        <div style={{ padding: 36, display: 'grid', gap: 18, maxWidth: 980 }}>
          {searchBlock}
          {state === 'noresult' && noresultCard}
          {state === 'found' && foundCard}
        </div>
      </DesktopShell>
    );
  }
  return (
    <MobileShell active="search" tabs={ADMIN_NAV}>
      <MobileTopBar subtitle="Admin" title="House Search"/>
      <div style={{ padding: '0 20px', display: 'grid', gap: 14 }}>
        {searchBlock}
        {state === 'noresult' && noresultCard}
        {state === 'found' && foundCard}
      </div>
    </MobileShell>
  );
}

// ── Admin Create House screen ────────────────────────────────
function AdminCreateScreen({ state = 'form', desktop = false }) {
  // state: 'form' | 'error' | 'success'
  const [resident, setResident] = React.useState(
    state === 'error' ? '' : state === 'success' ? 'Walter Hayashi' : 'Walter Hayashi'
  );
  const [address, setAddress] = React.useState(state !== 'error' ? '178 Larch Ave, Portland OR' : '');
  const [phone, setPhone] = React.useState(state !== 'error' ? '+1 (503) 555-2104' : '');
  const residentError = state === 'error' ? 'Resident name is required.' : null;

  const formCard = (
    <Card padding={desktop ? 28 : 22}>
      <div className="sh-display" style={{ fontSize: 22, color: 'var(--ink-900)' }}>House details</div>
      <div style={{ fontSize: 13.5, color: 'var(--ink-600)', marginTop: 6, marginBottom: 18 }}>
        We’ll generate the credentials you need to hand off to the family and the hardware unit.
      </div>
      <div style={{ display: 'grid', gap: 14 }}>
        <Input label="Resident name *" icon={<Ico.User size={18}/>} value={resident} onChange={setResident} placeholder="e.g. Walter Hayashi" error={residentError}/>
        <Input label="Address" icon={<Ico.Home size={18}/>} value={address} onChange={setAddress} placeholder="Street, city, state"/>
        <Input label="Emergency contact phone" icon={<Ico.Phone size={18}/>} value={phone} onChange={setPhone} placeholder="+1 (___) ___-____"/>
      </div>
      <div style={{ marginTop: 22, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
        <Button variant="primary" trailing={<Ico.ArrowRight size={16}/>}>Create house</Button>
        <Button variant="ghost">Cancel</Button>
      </div>
    </Card>
  );

  const successCard = (
    <Card padding={desktop ? 28 : 22} style={{ background: 'linear-gradient(160deg, var(--sage-50) 0%, var(--card) 60%)' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{
          width: 48, height: 48, borderRadius: '50%',
          background: 'var(--sage-600)', color: '#FBF8F0',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}><Ico.Check size={24} sw={2.4}/></div>
        <div>
          <div className="sh-display" style={{ fontSize: 24, color: 'var(--ink-900)' }}>House created</div>
          <div style={{ fontSize: 13.5, color: 'var(--ink-600)', marginTop: 2 }}>Save these credentials — you’ll need them now.</div>
        </div>
      </div>

      <div style={{ marginTop: 18, padding: 16, background: 'var(--card)', border: '1px solid var(--line)', borderRadius: 16 }}>
        <div style={{ display: 'grid', gap: 12 }}>
          <CopyChip label="House ID — admin reference" value="AHE-5520-WH"/>
          <CopyChip label="Invite code — share with family" value="WH-INV-3098"/>
          <CopyChip label="Device token — program into the ESP32 unit" value="esp32_2b07c4f9-8c41-4ad6-9f1d-cce41079f230"/>
        </div>
      </div>
      <div style={{ marginTop: 14, padding: '12px 14px', borderRadius: 12, background: 'var(--warn-soft)', border: '1px solid #EAD7A4', display: 'flex', gap: 10, alignItems: 'flex-start', color: '#7A5419', fontSize: 12.5, lineHeight: 1.5 }}>
        <Ico.Info size={16} style={{ flexShrink: 0, marginTop: 1 }}/>
        <div>The device token is shown only once. Copy it to a safe place before closing this screen.</div>
      </div>
      <div style={{ marginTop: 18, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
        <Button variant="primary">Done</Button>
        <Button variant="outline" leading={<Ico.Plus size={16}/>}>Create another</Button>
      </div>
    </Card>
  );

  if (desktop) {
    return (
      <DesktopShell active="create" kind="admin" residentName="Admin Console" topbar={
        <div style={{ padding: '20px 36px', borderBottom: '1px solid var(--line)', background: 'var(--bg-cream)' }}>
          <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>Admin</div>
          <div className="sh-display" style={{ fontSize: 28, color: 'var(--ink-900)', marginTop: 2 }}>Create new house</div>
        </div>
      }>
        <div style={{ padding: 36, maxWidth: 720, display: 'grid', gap: 18 }}>
          {state === 'success' ? successCard : formCard}
        </div>
      </DesktopShell>
    );
  }
  return (
    <MobileShell active="create" tabs={ADMIN_NAV}>
      <MobileTopBar subtitle="Admin" title="Create House"/>
      <div style={{ padding: '0 20px' }}>
        {state === 'success' ? successCard : formCard}
      </div>
    </MobileShell>
  );
}

Object.assign(window, {
  ProfileMobile, ProfileDesktop, AdminSearchScreen, AdminCreateScreen,
  HouseSwitcher, VacationToggle, CopyChip, ConfirmButton, SensorMaskGrid,
});
