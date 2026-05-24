// shared.jsx — Safe House design system primitives, icons, shells
// All components attached to window so other Babel scripts can use them.

// ────────────────────────────────────────────────────────────
// ICONS — line icons, 1.6px stroke, sage palette
// ────────────────────────────────────────────────────────────
const Ico = {};
const _icoBase = (s = 22, sw = 1.6) => ({
  width: s, height: s, viewBox: '0 0 24 24', fill: 'none',
  stroke: 'currentColor', strokeWidth: sw, strokeLinecap: 'round', strokeLinejoin: 'round',
});

Ico.Home = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M3.5 11 12 4l8.5 7"/><path d="M5.5 10v9h13v-9"/><path d="M10 19v-5h4v5"/></svg>);
Ico.HomeCheck = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M3.5 11 12 4l8.5 7"/><path d="M5.5 10v9h13v-9"/><path d="M9.5 14.5l1.8 1.8 3.2-3.4"/></svg>);
Ico.Shield = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M12 3l7 2v6c0 4.5-3 8-7 10-4-2-7-5.5-7-10V5l7-2z"/><path d="M9 12l2 2 4-4"/></svg>);
Ico.Door = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M6 3h12v18H6z"/><path d="M6 21h12"/><circle cx="14.5" cy="12.5" r=".9" fill="currentColor"/></svg>);
Ico.Kitchen = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M5 4h14v6H5z"/><path d="M5 10h14v10H5z"/><path d="M9 14h6"/><circle cx="8" cy="7" r=".8" fill="currentColor"/><circle cx="12" cy="7" r=".8" fill="currentColor"/><circle cx="16" cy="7" r=".8" fill="currentColor"/></svg>);
Ico.Bath = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M4 12h16v3a4 4 0 0 1-4 4H8a4 4 0 0 1-4-4v-3z"/><path d="M6 12V6a2 2 0 0 1 2-2h1"/><path d="M9 6h3"/><path d="M6 19l-1 2"/><path d="M18 19l1 2"/></svg>);
Ico.Toilet = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M5 3h14v8H5z"/><path d="M6 11l2 7h8l2-7"/><path d="M9 18l-1 3h8l-1-3"/></svg>);
Ico.Pill = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><rect x="3" y="9" width="18" height="6" rx="3" transform="rotate(-30 12 12)"/><path d="M9.6 7.2l4 7" /></svg>);
Ico.Bed = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M3 18V8"/><path d="M3 13h18v5"/><path d="M21 18v-3"/><path d="M7 13v-3h6a3 3 0 0 1 3 3"/></svg>);
Ico.Sofa = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M3 13a2 2 0 0 1 4 0v4"/><path d="M17 17v-4a2 2 0 0 1 4 0"/><path d="M5 17h14v-4a3 3 0 0 0-3-3H8a3 3 0 0 0-3 3z"/><path d="M5 17v2"/><path d="M19 17v2"/></svg>);

Ico.Bell = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M6 17h12l-1.5-2V11a4.5 4.5 0 1 0-9 0v4z"/><path d="M10.5 20a1.5 1.5 0 0 0 3 0"/></svg>);
Ico.User = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><circle cx="12" cy="9" r="3.5"/><path d="M5 20c1.5-3.5 4-5 7-5s5.5 1.5 7 5"/></svg>);
Ico.Chart = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M4 19V5"/><path d="M4 19h16"/><rect x="7" y="12" width="2.5" height="5"/><rect x="11.5" y="9" width="2.5" height="8"/><rect x="16" y="14" width="2.5" height="3"/></svg>);
Ico.Settings = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><circle cx="12" cy="12" r="2.5"/><path d="M12 4v2M12 18v2M4 12h2M18 12h2M6 6l1.4 1.4M16.6 16.6L18 18M6 18l1.4-1.4M16.6 7.4L18 6"/></svg>);
Ico.Mail = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><rect x="3" y="5" width="18" height="14" rx="2"/><path d="M4 7l8 6 8-6"/></svg>);
Ico.Lock = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><rect x="4" y="10" width="16" height="11" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>);
Ico.Eye = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>);
Ico.EyeOff = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M3 3l18 18"/><path d="M10.6 6.2A10 10 0 0 1 12 6c6.5 0 10 6 10 6a17 17 0 0 1-3 3.8"/><path d="M6.5 7.5C3.7 9.4 2 12 2 12s3.5 6 10 6c1.4 0 2.7-.3 3.8-.7"/><path d="M9.9 9.9a3 3 0 0 0 4.2 4.2"/></svg>);
Ico.Copy = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><rect x="8" y="8" width="12" height="12" rx="2"/><path d="M16 8V6a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v8a2 2 0 0 0 2 2h2"/></svg>);
Ico.Check = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M5 12.5l4 4 10-10"/></svg>);
Ico.X = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M6 6l12 12M18 6L6 18"/></svg>);
Ico.Plus = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M12 5v14M5 12h14"/></svg>);
Ico.Minus = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M5 12h14"/></svg>);
Ico.Search = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4-4"/></svg>);
Ico.Refresh = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M4 12a8 8 0 0 1 14-5.3"/><path d="M20 12a8 8 0 0 1-14 5.3"/><path d="M14 4h4v4"/><path d="M10 20H6v-4"/></svg>);
Ico.Sparkle = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M12 3l1.5 4.5L18 9l-4.5 1.5L12 15l-1.5-4.5L6 9l4.5-1.5L12 3z"/><path d="M19 16l.7 2L21.5 19l-1.8.6L19 22l-.7-2.4L16.5 19l1.8-1z"/></svg>);
Ico.ArrowUp = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M12 19V5"/><path d="M5 12l7-7 7 7"/></svg>);
Ico.ArrowDown = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M12 5v14"/><path d="M5 12l7 7 7-7"/></svg>);
Ico.ArrowRight = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M5 12h14"/><path d="M13 5l7 7-7 7"/></svg>);
Ico.ChevronDown = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M6 9l6 6 6-6"/></svg>);
Ico.ChevronRight = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M9 6l6 6-6 6"/></svg>);
Ico.Info = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><circle cx="12" cy="12" r="9"/><path d="M12 11v6"/><circle cx="12" cy="8" r=".8" fill="currentColor"/></svg>);
Ico.Alert = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M12 3l10 17H2L12 3z"/><path d="M12 10v5"/><circle cx="12" cy="18" r=".9" fill="currentColor"/></svg>);
Ico.Phone = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M5 4h4l2 5-3 2a12 12 0 0 0 5 5l2-3 5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/></svg>);
Ico.Suitcase = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M3 13h18"/></svg>);
Ico.Logout = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M10 4H6a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h4"/><path d="M16 8l4 4-4 4"/><path d="M20 12H10"/></svg>);
Ico.Sun = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><circle cx="12" cy="12" r="4"/><path d="M12 3v2M12 19v2M3 12h2M19 12h2M5.6 5.6l1.4 1.4M17 17l1.4 1.4M5.6 18.4L7 17M17 7l1.4-1.4"/></svg>);
Ico.Moon = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><path d="M21 13A9 9 0 1 1 11 3a7 7 0 0 0 10 10z"/></svg>);
Ico.Clock = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></svg>);
Ico.Calendar = (p) => (<svg {..._icoBase(p.size, p.sw)} {...p}><rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17"/><path d="M8 3.5v3"/><path d="M16 3.5v3"/></svg>);

// House logo — sage shield-house with check, matching the reference wordmark
Ico.SafeHouseLogo = ({ size = 28 }) => (
  <svg width={size} height={size} viewBox="0 0 32 32" fill="none">
    <defs>
      <linearGradient id="shGrad" x1="0" y1="0" x2="0" y2="1">
        <stop offset="0" stopColor="#A8C0A0"/>
        <stop offset="1" stopColor="#7A9B7E"/>
      </linearGradient>
    </defs>
    <path d="M16 3 L28 9 V18 C28 23.5 22.8 28 16 30 C9.2 28 4 23.5 4 18 V9 L16 3 Z" fill="url(#shGrad)"/>
    <path d="M10.5 18 V14 L16 10 L21.5 14 V18" stroke="#FBF8F0" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
    <path d="M13.5 17 L15.5 19 L19 15" stroke="#FBF8F0" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" fill="none"/>
  </svg>
);

// ────────────────────────────────────────────────────────────
// PRIMITIVES — Button, Input, Card, Toggle, Pill, IconWell
// ────────────────────────────────────────────────────────────
function Wordmark({ size = 'lg' }) {
  const fs = size === 'sm' ? 20 : size === 'md' ? 26 : 32;
  const ic = size === 'sm' ? 22 : size === 'md' ? 28 : 34;
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
      <Ico.SafeHouseLogo size={ic}/>
      <div className="sh-display" style={{
        fontSize: fs, lineHeight: 1, color: 'var(--sage-700)',
        letterSpacing: '-0.01em',
      }}>Safe House</div>
    </div>
  );
}

function Button({
  variant = 'primary', size = 'md', children, leading, trailing,
  full, disabled, onClick, style, ...rest
}) {
  const pad = size === 'sm' ? '10px 14px' : size === 'lg' ? '16px 22px' : '13px 18px';
  const fs = size === 'sm' ? 13.5 : size === 'lg' ? 16 : 15;
  const variants = {
    primary: { bg: 'var(--sage-600)', color: '#FBF8F0', border: 'none', shadow: '0 1px 0 rgba(255,255,255,.4) inset, 0 4px 14px rgba(107,139,110,.25)' },
    soft:    { bg: 'var(--sage-100)', color: 'var(--sage-800)', border: '1px solid var(--sage-200)', shadow: 'none' },
    ghost:   { bg: 'transparent', color: 'var(--ink-700)', border: 'none', shadow: 'none' },
    outline: { bg: 'var(--card)', color: 'var(--ink-800)', border: '1px solid var(--line-2)', shadow: 'var(--shadow-sm)' },
    danger:  { bg: 'var(--alert)', color: '#FBF8F0', border: 'none', shadow: '0 4px 14px rgba(185,95,74,.25)' },
    dangerSoft: { bg: 'var(--alert-soft)', color: '#7A3727', border: '1px solid #E6BFB1', shadow: 'none' },
  };
  const v = variants[variant] || variants.primary;
  return (
    <button onClick={onClick} disabled={disabled}
      style={{
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        padding: pad, fontSize: fs, fontWeight: 600, letterSpacing: '-0.005em',
        background: v.bg, color: v.color, border: v.border, borderRadius: 'var(--r-pill)',
        cursor: disabled ? 'not-allowed' : 'pointer', opacity: disabled ? 0.55 : 1,
        boxShadow: v.shadow, width: full ? '100%' : 'auto',
        transition: 'transform .08s ease, box-shadow .15s ease, background .15s',
        ...style,
      }}
      onMouseDown={e => e.currentTarget.style.transform = 'translateY(1px)'}
      onMouseUp={e => e.currentTarget.style.transform = ''}
      onMouseLeave={e => e.currentTarget.style.transform = ''}
      {...rest}
    >
      {leading}
      <span>{children}</span>
      {trailing}
    </button>
  );
}

function Input({ label, icon, error, hint, type = 'text', value, onChange, placeholder, right, autoFocus }) {
  const [focused, setFocused] = React.useState(false);
  const [showPw, setShowPw] = React.useState(false);
  const actualType = type === 'password' && showPw ? 'text' : type;
  const borderColor = error ? '#D88A78' : focused ? 'var(--sage-600)' : 'var(--line-2)';
  return (
    <label style={{ display: 'block' }}>
      {label && (
        <div style={{ fontSize: 12.5, fontWeight: 600, color: 'var(--ink-700)', marginBottom: 7, letterSpacing: '.01em' }}>{label}</div>
      )}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        background: 'var(--card-2)', border: `1.5px solid ${borderColor}`,
        borderRadius: 14, padding: '12px 14px',
        boxShadow: focused ? '0 0 0 4px rgba(143,170,140,.18)' : 'none',
        transition: 'box-shadow .15s, border-color .15s',
      }}>
        {icon && <span style={{ color: error ? '#B95F4A' : 'var(--ink-500)', display: 'flex' }}>{icon}</span>}
        <input
          type={actualType}
          value={value ?? ''}
          autoFocus={autoFocus}
          onChange={e => onChange && onChange(e.target.value)}
          onFocus={() => setFocused(true)}
          onBlur={() => setFocused(false)}
          placeholder={placeholder}
          style={{
            flex: 1, border: 'none', outline: 'none', background: 'transparent',
            fontSize: 15, color: 'var(--ink-900)', minWidth: 0,
          }}
        />
        {type === 'password' && (
          <button type="button" onClick={() => setShowPw(s => !s)}
            style={{ border: 'none', background: 'transparent', color: 'var(--ink-500)', cursor: 'pointer', padding: 2, display: 'flex' }}>
            {showPw ? <Ico.EyeOff size={18}/> : <Ico.Eye size={18}/>}
          </button>
        )}
        {right}
      </div>
      {error ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 7, fontSize: 12.5, color: '#9C4A38' }}>
          <Ico.Alert size={14}/> <span>{error}</span>
        </div>
      ) : hint ? (
        <div style={{ marginTop: 7, fontSize: 12.5, color: 'var(--ink-500)' }}>{hint}</div>
      ) : null}
    </label>
  );
}

function Card({ children, style, padding = 20, elev = 1 }) {
  const shadow = elev === 0 ? 'none' : elev === 2 ? 'var(--shadow-md)' : 'var(--shadow-sm)';
  return (
    <div style={{
      background: 'var(--card)', borderRadius: 'var(--r-lg)', padding,
      border: '1px solid var(--line)', boxShadow: shadow, ...style,
    }}>{children}</div>
  );
}

function Toggle({ checked, onChange, size = 'md', disabled }) {
  const w = size === 'lg' ? 56 : size === 'sm' ? 36 : 44;
  const h = size === 'lg' ? 32 : size === 'sm' ? 22 : 26;
  const d = h - 6;
  return (
    <button type="button" onClick={() => !disabled && onChange && onChange(!checked)}
      style={{
        width: w, height: h, borderRadius: h, border: 'none',
        background: checked ? 'var(--sage-600)' : '#D8D2BF',
        position: 'relative', cursor: disabled ? 'not-allowed' : 'pointer',
        transition: 'background .2s ease', padding: 0,
        boxShadow: checked ? 'inset 0 1px 0 rgba(255,255,255,.3)' : 'inset 0 1px 2px rgba(0,0,0,.08)',
      }}>
      <span style={{
        position: 'absolute', top: 3, left: checked ? w - d - 3 : 3,
        width: d, height: d, borderRadius: '50%', background: '#FBF8F0',
        transition: 'left .2s ease',
        boxShadow: '0 1px 3px rgba(0,0,0,.2)',
      }}/>
    </button>
  );
}

function StatusDot({ tone = 'ok', size = 8, pulse = false }) {
  const map = { ok: 'var(--sage-600)', warn: 'var(--warn)', alert: 'var(--alert)', off: '#C2BCA8' };
  return (
    <span style={{ position: 'relative', display: 'inline-block', width: size, height: size }}>
      {pulse && (
        <span style={{
          position: 'absolute', inset: -3, borderRadius: '50%',
          background: map[tone], opacity: .25, animation: 'shPulse 1.6s ease-out infinite',
        }}/>
      )}
      <span style={{ position: 'absolute', inset: 0, borderRadius: '50%', background: map[tone] }}/>
    </span>
  );
}

function IconWell({ children, tone = 'sage', size = 40 }) {
  const map = {
    sage: { bg: 'var(--sage-100)', fg: 'var(--sage-800)' },
    warm: { bg: '#F1E7CB', fg: '#8C6D2A' },
    coral: { bg: 'var(--alert-soft)', fg: '#7E3A28' },
    cream: { bg: 'var(--card-3)', fg: 'var(--ink-700)' },
    sky:   { bg: '#E1ECEC', fg: '#3F6868' },
    plum:  { bg: '#ECE2E8', fg: '#704863' },
  };
  const t = map[tone] || map.sage;
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      background: t.bg, color: t.fg,
      display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
    }}>{children}</div>
  );
}

function Tag({ children, tone = 'sage', icon }) {
  const map = {
    sage: { bg: 'var(--sage-100)', fg: 'var(--sage-800)', bd: 'var(--sage-200)' },
    warn: { bg: 'var(--warn-soft)', fg: '#7A5419', bd: '#EAD7A4' },
    alert: { bg: 'var(--alert-soft)', fg: '#7E3A28', bd: '#E8C2B5' },
    neutral: { bg: 'var(--card-3)', fg: 'var(--ink-700)', bd: 'var(--line)' },
  };
  const t = map[tone] || map.sage;
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      padding: '4px 9px', fontSize: 12, fontWeight: 600,
      background: t.bg, color: t.fg, border: `1px solid ${t.bd}`,
      borderRadius: 'var(--r-pill)',
    }}>{icon}{children}</span>
  );
}

// Decorative placeholder block (for illustration slots)
function PhPlate({ width = '100%', height = 120, label = 'illustration' }) {
  return (
    <div className="sh-placeholder-stripes" style={{
      width, height, borderRadius: 18, border: '1px dashed var(--sage-300)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: 'var(--sage-700)', fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
      fontSize: 11, letterSpacing: '.06em', textTransform: 'uppercase',
    }}>{label}</div>
  );
}

// ────────────────────────────────────────────────────────────
// SHELLS — Mobile (bottom nav) and Desktop (sidebar)
// ────────────────────────────────────────────────────────────
const CUSTOMER_NAV = [
  { id: 'home',    label: 'Home',    icon: Ico.Home  },
  { id: 'summary', label: 'Summary', icon: Ico.Chart },
  { id: 'alerts',  label: 'Alerts',  icon: Ico.Bell  },
  { id: 'profile', label: 'Profile', icon: Ico.User  },
];

const ADMIN_NAV = [
  { id: 'search', label: 'House Search', icon: Ico.Search },
  { id: 'create', label: 'Create House', icon: Ico.Plus   },
];

function MobileNav({ active = 'home', alertCount = 0, badgeOn = 'alerts', onNav, tabs }) {
  const items = tabs || CUSTOMER_NAV;
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 28,
      padding: '10px 10px 12px', background:
        'linear-gradient(to top, var(--bg-cream) 70%, rgba(242,237,223,0))',
      display: 'flex', justifyContent: 'space-around', gap: 2,
      zIndex: 5,
    }}>
      {items.map(item => {
        const Icon = item.icon;
        const isActive = item.id === active;
        const showBadge = item.id === badgeOn && alertCount > 0;
        return (
          <button key={item.id} onClick={() => onNav && onNav(item.id)}
            style={{
              flex: 1, border: 'none', background: 'transparent',
              display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
              padding: '8px 2px', cursor: 'pointer',
              color: isActive ? 'var(--sage-800)' : 'var(--ink-500)',
            }}>
            <div style={{ position: 'relative' }}>
              <Icon size={22}/>
              {showBadge && (
                <span style={{
                  position: 'absolute', top: -3, right: -6, minWidth: 16, height: 16,
                  padding: '0 4px', borderRadius: 999, background: 'var(--alert)',
                  color: '#FBF8F0', fontSize: 10, fontWeight: 700,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  border: '2px solid var(--bg-cream)',
                }}>{alertCount}</span>
              )}
            </div>
            <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: '.01em' }}>{item.label}</span>
            {isActive && <span style={{ width: 18, height: 2, background: 'var(--sage-700)', borderRadius: 2, marginTop: 1 }}/>}
          </button>
        );
      })}
    </div>
  );
}

function MobileShell({ children, active = 'home', alertCount = 0, badgeOn = 'alerts', hideNav = false, tabs }) {
  return (
    <div className="sh-app">
      <div className="sh-scroll" style={{
        paddingTop: 52,
        paddingBottom: hideNav ? 44 : 120,
      }}>
        {children}
      </div>
      {!hideNav && <MobileNav active={active} alertCount={alertCount} badgeOn={badgeOn} tabs={tabs}/>}
    </div>
  );
}

// ── Desktop shell with vertical sidebar ───────────────────────
const DESK_NAV_CUSTOMER = [
  { id: 'home',    label: 'Home',    icon: Ico.Home  },
  { id: 'summary', label: 'Summary', icon: Ico.Chart },
  { id: 'alerts',  label: 'Alerts',  icon: Ico.Bell  },
  { id: 'profile', label: 'Profile', icon: Ico.User  },
];

const DESK_NAV_ADMIN = [
  { id: 'search', label: 'House Search', icon: Ico.Search },
  { id: 'create', label: 'Create House', icon: Ico.Plus   },
];

function DesktopSidebar({
  active = 'home', alertCount = 0, residentName = 'Eleanor Reyes',
  tabs, kind = 'customer',
}) {
  const navItems = tabs || (kind === 'admin' ? DESK_NAV_ADMIN : DESK_NAV_CUSTOMER);
  const isAdmin = kind === 'admin';
  return (
    <aside style={{
      width: 248, background: 'var(--card)', borderRight: '1px solid var(--line)',
      display: 'flex', flexDirection: 'column', padding: '24px 16px',
      flexShrink: 0,
    }}>
      <div style={{ padding: '4px 8px 22px' }}>
        <Wordmark size="md"/>
      </div>
      <nav style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
        {navItems.map(item => {
          const Icon = item.icon;
          const isActive = item.id === active;
          return (
            <a key={item.id} style={{
              display: 'flex', alignItems: 'center', gap: 12,
              padding: '10px 12px', borderRadius: 12,
              background: isActive ? 'var(--sage-100)' : 'transparent',
              color: isActive ? 'var(--sage-800)' : 'var(--ink-700)',
              fontWeight: isActive ? 700 : 500, fontSize: 14.5,
              cursor: 'pointer', textDecoration: 'none',
              position: 'relative',
            }}>
              <Icon size={20}/>
              <span>{item.label}</span>
              {item.id === 'alerts' && alertCount > 0 && (
                <span style={{
                  marginLeft: 'auto', minWidth: 22, height: 22, padding: '0 6px',
                  borderRadius: 999, background: 'var(--alert)', color: '#FBF8F0',
                  fontSize: 11, fontWeight: 700,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>{alertCount}</span>
              )}
            </a>
          );
        })}
      </nav>
      <div style={{ marginTop: 'auto' }}>
        <div style={{
          padding: 14, background: 'var(--bg-soft)', borderRadius: 16,
          display: 'flex', alignItems: 'center', gap: 11,
        }}>
          <IconWell tone={isAdmin ? 'plum' : 'sage'} size={36}>
            {isAdmin ? <Ico.Settings size={18}/> : <Ico.User size={18}/>}
          </IconWell>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{ fontSize: 11, color: 'var(--ink-500)', fontWeight: 600, textTransform: 'uppercase', letterSpacing: '.06em' }}>
              {isAdmin ? 'Operator' : 'Active House'}
            </div>
            <div style={{ fontSize: 13.5, fontWeight: 600, color: 'var(--ink-900)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{residentName}</div>
          </div>
        </div>
      </div>
    </aside>
  );
}

function DesktopShell({
  children, active = 'home', alertCount = 0, residentName = 'Eleanor Reyes',
  topbar, tabs, kind = 'customer',
}) {
  return (
    <div style={{
      display: 'flex', width: '100%', height: '100%',
      background: 'var(--bg-cream)', overflow: 'hidden',
    }}>
      <DesktopSidebar active={active} alertCount={alertCount} residentName={residentName} tabs={tabs} kind={kind}/>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', minWidth: 0 }}>
        {topbar}
        <div style={{ flex: 1, overflow: 'auto' }}>
          {children}
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────────────
// Mobile top bar — gentle, used on most internal screens
// ────────────────────────────────────────────────────────────
function MobileTopBar({ title, subtitle, right, sticky = true, compact = false }) {
  return (
    <div style={{
      position: sticky ? 'sticky' : 'static', top: 0, zIndex: 4,
      background: 'var(--bg-cream)',
      padding: compact ? '18px 22px 12px' : '24px 22px 14px',
      display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: 14,
    }}>
      <div style={{ minWidth: 0 }}>
        {subtitle && <div style={{ fontSize: 12, fontWeight: 600, color: 'var(--ink-500)', textTransform: 'uppercase', letterSpacing: '.08em' }}>{subtitle}</div>}
        <div className="sh-display" style={{ fontSize: compact ? 24 : 28, color: 'var(--ink-900)', marginTop: 2 }}>{title}</div>
      </div>
      {right}
    </div>
  );
}

// keyframe injection (once)
if (typeof document !== 'undefined' && !document.getElementById('sh-keyframes')) {
  const s = document.createElement('style');
  s.id = 'sh-keyframes';
  s.textContent = `
    @keyframes shPulse {
      0%   { transform: scale(1); opacity: .35; }
      80%  { transform: scale(2.4); opacity: 0; }
      100% { transform: scale(2.4); opacity: 0; }
    }
    @keyframes shSpin { to { transform: rotate(360deg); } }
    @keyframes shFade { from { opacity: 0; transform: translateY(4px);} to { opacity: 1; transform: none;} }
  `;
  document.head.appendChild(s);
}

Object.assign(window, {
  Ico, Wordmark, Button, Input, Card, Toggle, StatusDot, IconWell, Tag, PhPlate,
  MobileShell, MobileNav, MobileTopBar, DesktopShell, DesktopSidebar,
  CUSTOMER_NAV, ADMIN_NAV, DESK_NAV_CUSTOMER, DESK_NAV_ADMIN,
});
