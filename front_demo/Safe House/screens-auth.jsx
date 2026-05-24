// auth.jsx — Sign Up, Sign In, Join House screens

// ── Shared auth card layout ─────────────────────────────────
function AuthShell({ children, desktop = false }) {
  if (desktop) {
    return (
      <div style={{
        display: 'flex', width: '100%', height: '100%',
        background: 'var(--bg-cream)',
      }}>
        {/* Left: brand panel */}
        <div style={{
          width: '46%', padding: '52px 56px', display: 'flex', flexDirection: 'column',
          background:
            'radial-gradient(120% 80% at -10% 110%, rgba(168,192,160,.45), transparent 60%),' +
            'radial-gradient(80% 60% at 110% 0%, rgba(168,192,160,.3), transparent 55%),' +
            'var(--sage-50)',
          borderRight: '1px solid var(--line)',
        }}>
          <Wordmark size="lg"/>
          <div style={{ marginTop: 'auto' }}>
            <div className="sh-display" style={{ fontSize: 44, lineHeight: 1.08, color: 'var(--ink-900)', maxWidth: 460, letterSpacing: '-0.015em' }}>
              Peace of mind, woven gently into the rhythms of home.
            </div>
            <div style={{ marginTop: 16, fontSize: 15, color: 'var(--ink-600)', maxWidth: 420, lineHeight: 1.55 }}>
              Quiet sensors learn the daily patterns of your loved one. Safe House lets you know everything is okay — without watching.
            </div>
            <div style={{ marginTop: 28, display: 'flex', gap: 18, color: 'var(--ink-600)', fontSize: 13 }}>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}><StatusDot tone="ok"/>No cameras</span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}><StatusDot tone="ok"/>HIPAA-aligned</span>
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7 }}><StatusDot tone="ok"/>Family-first</span>
            </div>
          </div>
        </div>
        {/* Right: form */}
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 40, overflow: 'auto' }}>
          <div style={{ width: '100%', maxWidth: 420 }}>{children}</div>
        </div>
      </div>
    );
  }
  // mobile
  return (
    <div className="sh-app" style={{
      background:
        'radial-gradient(120% 60% at 0% 0%, rgba(168,192,160,.35), transparent 55%),' +
        'radial-gradient(80% 50% at 100% 100%, rgba(168,192,160,.25), transparent 55%),' +
        'var(--bg-cream)',
    }}>
      <div className="sh-scroll" style={{ paddingTop: 56, padding: '56px 24px 60px' }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: 12, marginBottom: 28 }}>
          <Wordmark size="md"/>
        </div>
        {children}
      </div>
    </div>
  );
}

// ── Sign Up ──────────────────────────────────────────────────
function SignUpScreen({ desktop = false, withErrors = false, onSwitch }) {
  const [username, setUsername] = React.useState(withErrors ? 'mara' : '');
  const [email, setEmail] = React.useState(withErrors ? 'mara@family.com' : '');
  const [pw, setPw] = React.useState(withErrors ? '1234' : '');
  const errors = withErrors ? {
    email: 'This email is already in use.',
    pw: 'Password must be at least 6 characters.',
  } : {};
  return (
    <AuthShell desktop={desktop}>
      <div>
        <div className="sh-display" style={{ fontSize: 30, color: 'var(--ink-900)', lineHeight: 1.1 }}>Create an account</div>
        <div style={{ marginTop: 8, fontSize: 14.5, color: 'var(--ink-600)', lineHeight: 1.5 }}>
          Join the people watching over <span style={{ color: 'var(--sage-800)', fontWeight: 600 }}>‘home’</span> together.
        </div>
        <div style={{ display: 'grid', gap: 14, marginTop: 24 }}>
          <Input label="Username" icon={<Ico.User size={18}/>} value={username} onChange={setUsername} placeholder="mara_b" />
          <Input label="Email" icon={<Ico.Mail size={18}/>} value={email} onChange={setEmail} placeholder="you@email.com" error={errors.email}/>
          <Input label="Password" icon={<Ico.Lock size={18}/>} type="password" value={pw} onChange={setPw} placeholder="At least 6 characters" error={errors.pw} hint={!errors.pw && "Use 6+ characters with a mix of letters and numbers."}/>
        </div>
        <div style={{ marginTop: 20 }}>
          <Button variant="primary" size="lg" full trailing={<Ico.ArrowRight size={18}/>}>Create account</Button>
        </div>
        <div style={{ marginTop: 18, fontSize: 13.5, color: 'var(--ink-600)', textAlign: 'center' }}>
          Already have an account?{' '}
          <a onClick={onSwitch} style={{ color: 'var(--sage-800)', fontWeight: 700, cursor: 'pointer', textDecoration: 'underline', textUnderlineOffset: 3 }}>Sign in</a>
        </div>
        <div style={{ marginTop: 28, padding: '14px 16px', borderRadius: 14, background: 'var(--sage-50)', border: '1px solid var(--sage-200)', display: 'flex', gap: 10, alignItems: 'flex-start' }}>
          <Ico.Shield size={18} style={{ color: 'var(--sage-700)', flexShrink: 0, marginTop: 1 }}/>
          <div style={{ fontSize: 12.5, color: 'var(--ink-700)', lineHeight: 1.5 }}>
            We never record video or audio. Only ambient signals — when a door opens, a bed is occupied — are processed.
          </div>
        </div>
      </div>
    </AuthShell>
  );
}

// ── Sign In ──────────────────────────────────────────────────
function SignInScreen({ desktop = false, withError = false, onSwitch }) {
  const [email, setEmail] = React.useState(withError ? 'mara@family.com' : '');
  const [pw, setPw] = React.useState(withError ? '••••••••' : '');
  const formError = withError ? 'Invalid email or password.' : null;
  return (
    <AuthShell desktop={desktop}>
      <div>
        <div className="sh-display" style={{ fontSize: 30, color: 'var(--ink-900)', lineHeight: 1.1 }}>Welcome back</div>
        <div style={{ marginTop: 8, fontSize: 14.5, color: 'var(--ink-600)', lineHeight: 1.5 }}>
          Sign in to check on your loved one.
        </div>
        {formError && (
          <div style={{
            marginTop: 18, padding: '12px 14px', borderRadius: 14,
            background: 'var(--alert-soft)', border: '1px solid #E6BFB1',
            display: 'flex', gap: 10, alignItems: 'flex-start',
            color: '#7A3727', fontSize: 13.5,
          }}>
            <Ico.Alert size={18} style={{ flexShrink: 0, marginTop: 1 }}/>
            <div>
              <div style={{ fontWeight: 700 }}>We couldn’t sign you in</div>
              <div style={{ marginTop: 2, opacity: .85 }}>{formError}</div>
            </div>
          </div>
        )}
        <div style={{ display: 'grid', gap: 14, marginTop: 22 }}>
          <Input label="Email" icon={<Ico.Mail size={18}/>} value={email} onChange={setEmail} placeholder="you@email.com" error={formError ? ' ' : null}/>
          <Input label="Password" icon={<Ico.Lock size={18}/>} type="password" value={pw} onChange={setPw} placeholder="Your password" error={formError ? ' ' : null}/>
        </div>
        <div style={{ marginTop: 6, textAlign: 'right' }}>
          <a style={{ fontSize: 13, color: 'var(--ink-600)', cursor: 'pointer', textDecoration: 'underline', textUnderlineOffset: 3 }}>Forgot password?</a>
        </div>
        <div style={{ marginTop: 18 }}>
          <Button variant="primary" size="lg" full trailing={<Ico.ArrowRight size={18}/>}>Sign in</Button>
        </div>
        <div style={{ marginTop: 18, fontSize: 13.5, color: 'var(--ink-600)', textAlign: 'center' }}>
          New here?{' '}
          <a onClick={onSwitch} style={{ color: 'var(--sage-800)', fontWeight: 700, cursor: 'pointer', textDecoration: 'underline', textUnderlineOffset: 3 }}>Create an account</a>
        </div>
      </div>
    </AuthShell>
  );
}

// ── Join House ───────────────────────────────────────────────
function JoinHouseIllustration() {
  // a calm, decorative scene of a house + sensor halos
  return (
    <div style={{
      width: 220, height: 180, position: 'relative',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      margin: '0 auto',
    }}>
      {/* halo */}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: '50%',
        background: 'radial-gradient(circle, rgba(168,192,160,.35), transparent 65%)',
      }}/>
      {/* concentric rings */}
      {[140, 100, 70].map((d, i) => (
        <div key={i} style={{
          position: 'absolute', width: d, height: d, borderRadius: '50%',
          border: '1px dashed var(--sage-300)', opacity: .7 - i * .15,
        }}/>
      ))}
      {/* tiny sensor dots on outer ring */}
      {[0, 60, 120, 180, 240, 300].map(deg => (
        <div key={deg} style={{
          position: 'absolute', width: 10, height: 10, borderRadius: '50%',
          background: 'var(--sage-400)',
          transform: `rotate(${deg}deg) translate(70px) rotate(-${deg}deg)`,
          boxShadow: '0 0 0 3px var(--sage-100)',
        }}/>
      ))}
      <div style={{
        width: 86, height: 86, borderRadius: '50%',
        background: 'var(--sage-100)', border: '1px solid var(--sage-200)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--sage-800)',
      }}>
        <Ico.HomeCheck size={42} sw={1.5}/>
      </div>
    </div>
  );
}

function JoinHouseScreen({ desktop = false, state = 'empty' }) {
  // state: 'empty' | 'error' | 'success'
  const [code, setCode] = React.useState(
    state === 'error' ? 'X9P-2210' :
    state === 'success' ? 'AHE-7842' : ''
  );
  const errorMsg = state === 'error' ? 'Invalid invite code. Double-check with the family member who shared it.' : null;
  const success = state === 'success';

  const formBlock = (
    <div>
      {!success && (
        <>
          <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 22 }}>
            <JoinHouseIllustration/>
          </div>
          <div className="sh-display" style={{ fontSize: 26, color: 'var(--ink-900)', textAlign: 'center', lineHeight: 1.15 }}>
            You’re not part of any house yet
          </div>
          <div style={{ marginTop: 10, fontSize: 14.5, color: 'var(--ink-600)', textAlign: 'center', lineHeight: 1.5, maxWidth: 360, marginInline: 'auto' }}>
            Ask a family member or caregiver for the invite code from their Safe House admin.
          </div>
          <div style={{ marginTop: 24 }}>
            <Input
              label="Invite code"
              value={code}
              onChange={(v) => setCode(v.toUpperCase())}
              placeholder="e.g. AHE-7842"
              error={errorMsg}
              icon={<Ico.HomeCheck size={18}/>}
            />
          </div>
          <div style={{ marginTop: 16 }}>
            <Button variant="primary" size="lg" full trailing={<Ico.ArrowRight size={18}/>}>Join house</Button>
          </div>
        </>
      )}
      {success && (
        <div style={{ animation: 'shFade .4s ease' }}>
          <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 18 }}>
            <div style={{
              width: 110, height: 110, borderRadius: '50%',
              background: 'var(--sage-100)', border: '2px solid var(--sage-300)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: 'var(--sage-800)', position: 'relative',
            }}>
              <Ico.Check size={56} sw={2}/>
              <div style={{ position: 'absolute', inset: -10, borderRadius: '50%', border: '1px dashed var(--sage-300)'}}/>
            </div>
          </div>
          <div className="sh-display" style={{ fontSize: 26, color: 'var(--ink-900)', textAlign: 'center' }}>You’re in.</div>
          <div style={{ marginTop: 14, padding: 18, borderRadius: 18, background: 'var(--card)', border: '1px solid var(--line)', textAlign: 'center' }}>
            <div style={{ fontSize: 12, color: 'var(--ink-500)', fontWeight: 600, letterSpacing: '.08em', textTransform: 'uppercase' }}>Now watching over</div>
            <div className="sh-display" style={{ fontSize: 24, color: 'var(--sage-800)', marginTop: 6 }}>Eleanor’s House</div>
            <div style={{ marginTop: 4, fontSize: 14, color: 'var(--ink-700)' }}>Eleanor Reyes · joined as <strong>Family</strong></div>
          </div>
          <div style={{ marginTop: 20 }}>
            <Button variant="primary" size="lg" full trailing={<Ico.ArrowRight size={18}/>}>Take me to the dashboard</Button>
          </div>
        </div>
      )}
    </div>
  );

  if (desktop) {
    return (
      <div style={{ display: 'flex', width: '100%', height: '100%', background: 'var(--bg-cream)' }}>
        <div style={{ width: 248, background: 'var(--card)', borderRight: '1px solid var(--line)', padding: '24px 16px' }}>
          <Wordmark size="md"/>
          <div style={{ marginTop: 36, padding: 12, background: 'var(--sage-50)', borderRadius: 12, fontSize: 13, color: 'var(--ink-600)', lineHeight: 1.5 }}>
            Finish setting up to see your dashboard.
          </div>
        </div>
        <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 40, overflow: 'auto' }}>
          <div style={{ width: '100%', maxWidth: 440 }}>{formBlock}</div>
        </div>
      </div>
    );
  }
  return (
    <div className="sh-app" style={{ background: 'var(--bg-cream)' }}>
      <div className="sh-scroll" style={{ padding: '64px 24px 60px' }}>
        <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 24 }}>
          <Wordmark size="sm"/>
        </div>
        {formBlock}
      </div>
    </div>
  );
}

Object.assign(window, { SignUpScreen, SignInScreen, JoinHouseScreen, AuthShell });
