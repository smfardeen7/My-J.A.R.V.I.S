import { useEffect, useId, useRef, useState } from 'react'
import type { CSSProperties, FormEvent, ReactNode } from 'react'
import { AnimatePresence, motion, useReducedMotion } from 'framer-motion'
import { Activity, ArrowUpRight, AudioLines, Check, ChevronRight, Command, Cpu, Fingerprint, Globe2, Maximize2, Mic, MicOff, Radio, Send, Settings2, ShieldCheck, Sparkles, Volume2, VolumeX, X, Zap } from 'lucide-react'
import type { ActivityEntry, JarvisState } from '../types'
import { JarvisOrb } from './JarvisOrb'
import { ParticleField } from './ParticleField'
import './hud.css'

export interface JarvisHUDProps {
  state?: JarvisState
  analyser?: AnalyserNode | null
  amplitude?: number
  response?: string
  activity?: ActivityEntry[]
  onCommand?: (command: string) => void
  onListen?: () => void
  onStopListening?: () => void
  onStateChange?: (state: JarvisState) => void
  microphoneActive?: boolean
  microphoneStarting?: boolean
  voiceStatusLabel?: string
  securityStatusLabel?: string
  audioError?: string | null
  soundEnabled?: boolean
  onSoundChange?: (enabled: boolean) => void
  reducedMotion?: boolean
  className?: string
  mode?: 'demo' | 'desktop'
  connectionLabel?: string
  statusText?: string
  sidebarContent?: ReactNode
  controls?: ReactNode
  transcript?: string
  suggestions?: string[]
  onCancel?: () => void
  onFullscreen?: () => void
}

const stateCopy: Record<JarvisState, {title: string; subtitle: string; label: string}> = {
  idle: {title: 'Awaiting your command', subtitle: 'A thought. A question. A possibility.', label: 'SYSTEM READY'},
  listening: {title: 'I’m listening.', subtitle: 'Go ahead. You have my full attention.', label: 'AUDIO LINK ACTIVE'},
  processing: {title: 'Connecting the dots.', subtitle: 'A little computation. A lot of possibility.', label: 'PROCESSING'},
  speaking: {title: 'Here’s what I found.', subtitle: 'Intelligence, at your service.', label: 'RESPONSE ACTIVE'},
}
const previewStates: {state: JarvisState; label: string}[] = [
  {state: 'idle', label: 'Idle'}, {state: 'listening', label: 'Listening'},
  {state: 'processing', label: 'Thinking'}, {state: 'speaking', label: 'Speaking'},
]
const defaultActivity: ActivityEntry[] = [
  {id: '1', time: '09:41:08', message: 'Neural interface initialized', tone: 'success'},
  {id: '2', time: '09:41:08', message: 'Secure channel established'},
  {id: '3', time: '09:41:09', message: 'Voice modules synchronized'},
  {id: '4', time: '09:41:09', message: 'All systems ready', tone: 'success'},
]

function Panel({ title, code, children, className = '', delay = 0, reduced }: {title: string; code?: string; children: ReactNode; className?: string; delay?: number; reduced: boolean}) {
  return <motion.section className={`hud-panel ${className}`} initial={reduced ? false : {opacity: 0, y: 9}} animate={{opacity: 1, y: 0}} transition={{duration: .55, delay: reduced ? 0 : delay}}>
    <div className="panel-heading"><h2>{title}</h2><span>{code || <PlusMark />}</span></div>{children}
  </motion.section>
}
function PlusMark() { return <span className="plus-mark">+</span> }
function Meter({label, value, amount, unit}: {label: string; value: string; amount: number; unit?:string}) {
  return <div className="metric"><div className="metric-label"><span>{label}</span><span className="metric-value">{value}<small>{unit}</small></span></div><div className="meter" role="meter" aria-label={label} aria-valuenow={amount} aria-valuemin={0} aria-valuemax={100}><i style={{'--fill': `${amount}%`} as CSSProperties}/></div></div>
}
function Clock() {
  const [time, setTime] = useState(() => new Date())
  useEffect(() => { const id = window.setInterval(() => setTime(new Date()), 1000); return () => clearInterval(id) }, [])
  return <div className="clock"><time>{time.toLocaleTimeString('en-GB')}</time><span>{time.toLocaleDateString('en-US', {day:'2-digit', month:'short', year:'numeric'}).toUpperCase()} <span className="clock-zone">LOCAL TIME</span></span></div>
}
function ResponseText({text, reduced}: {text: string; reduced: boolean}) {
  const [visible, setVisible] = useState(reduced ? text.length : 0)
  useEffect(() => {
    if(reduced) { setVisible(text.length); return }
    setVisible(0)
    const timer = window.setInterval(() => setVisible(v => { if(v >= text.length) {window.clearInterval(timer); return v} return v + 2 }), 16)
    return () => window.clearInterval(timer)
  }, [text, reduced])
  return <><span className="sr-only" role="status">{text}</span><span aria-hidden="true">{text.slice(0, visible)}{visible < text.length && <span className="typing-caret"/>}</span></>
}

export function JarvisHUD({state = 'idle', analyser, amplitude, response = '', activity = defaultActivity, onCommand, onListen, onStopListening, onStateChange, microphoneActive = false, microphoneStarting = false, voiceStatusLabel, securityStatusLabel, audioError, soundEnabled = false, onSoundChange, reducedMotion = false, className = '', mode = 'demo', connectionLabel = 'SYSTEM ONLINE', statusText = 'All systems operational. Ready when you are.', sidebarContent, controls, transcript, suggestions = ['Run diagnostics', 'System status', 'What can you do?'], onCancel, onFullscreen}: JarvisHUDProps) {
  const instanceId = useId().replace(/:/g, '')
  const commandId = `${instanceId}-command`
  const mainId = `${instanceId}-main`
  const gradientId = `${instanceId}-power`
  const prefersReduced = useReducedMotion()
  const [stillMode, setStillMode] = useState(false)
  const [settingsOpen, setSettingsOpen] = useState(false)
  const [command, setCommand] = useState('')
  const [telemetry, setTelemetry] = useState(true)
  const [fullscreenError, setFullscreenError] = useState('')
  const reduced = Boolean(prefersReduced || reducedMotion || stillMode)
  const commandRef = useRef<HTMLInputElement>(null)
  const settingsRef = useRef<HTMLButtonElement>(null)
  const settingsCloseRef = useRef<HTMLButtonElement>(null)
  const copy = stateCopy[state]
  useEffect(() => {
    const handler = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key === 'k') {event.preventDefault(); commandRef.current?.focus()}
      if(event.key === 'Escape' && settingsOpen) {setSettingsOpen(false); settingsRef.current?.focus()}
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [settingsOpen])
  useEffect(() => { if(settingsOpen) settingsCloseRef.current?.focus() }, [settingsOpen])
  function submit(event: FormEvent) {
    event.preventDefault()
    if (!command.trim() || !onCommand) return
    onCommand(command.trim()); setCommand('')
  }
  async function toggleFullscreen() {
    if(onFullscreen) { onFullscreen(); return }
    try {
      if(document.fullscreenElement) await document.exitFullscreen()
      else if(document.documentElement.requestFullscreen) await document.documentElement.requestFullscreen()
      else setFullscreenError('Full screen is unavailable in this browser.')
    } catch { setFullscreenError('Full screen is unavailable in this view.') }
  }
  return <div className={`jarvis-hud ${reduced ? 'reduce-motion' : ''} ${className} ${mode === 'desktop' ? 'desktop-hud' : ''}`} data-state={state}>
    <ParticleField reducedMotion={reduced}/><div className="hud-grid"/><div className="scan-texture"/><div className="screen-scan" aria-hidden="true"/>
    <div className="interface-shell">
      <header className="topbar">
        <a href={`#${mainId}`} className="brand" aria-label="J.A.R.V.I.S. home"><span className="brand-symbol"><span/><i/></span><span><strong>J.A.R.V.I.S.</strong><span className="brand-caption">JUST A RATHER VERY INTELLIGENT SYSTEM</span></span></a>
        <div className="topbar-right"><span className="connection-badge"><i/> {connectionLabel}</span><span className="topbar-divider"/><button className="icon-button" aria-label={soundEnabled ? (mode === 'desktop' ? 'Mute spoken replies' : 'Mute interface sounds') : (mode === 'desktop' ? 'Enable spoken replies' : 'Enable interface sounds')} aria-pressed={soundEnabled} onClick={() => onSoundChange?.(!soundEnabled)} disabled={!onSoundChange}>{soundEnabled ? <Volume2 size={18}/> : <VolumeX size={18}/>}</button><button className="icon-button fullscreen-button" aria-label="Toggle full screen" onClick={toggleFullscreen}><Maximize2 size={17}/></button><button ref={settingsRef} className={`icon-button ${settingsOpen ? 'selected' : ''}`} aria-label="Interface settings" aria-expanded={settingsOpen} onClick={() => setSettingsOpen(!settingsOpen)}><Settings2 size={18}/></button></div>
      </header>
      <main id={mainId}>
        <section className="welcome-row"><div><div className="eyebrow"><span className="tiny-line"/> PERSONAL INTELLIGENCE INTERFACE <span className="version">V.4.0</span></div><h1>At your service.</h1><p>{statusText}</p></div><Clock/></section>
        <div className="workspace-grid">
          <aside inert={!telemetry} aria-hidden={!telemetry} className={`left-instruments ${!telemetry ? 'telemetry-hidden' : ''}`}>
            {sidebarContent ?? <><Panel title="SYSTEM DIAGNOSTICS" code="01" reduced={reduced} delay={.1}>
              <div className="panel-status"><span><Cpu size={14}/> CORE PERFORMANCE</span><b>OPTIMAL</b></div>
              <Meter label="CPU load" value="24" unit="%" amount={24}/><Meter label="Memory" value="6.4" unit="/ 16 GB" amount={40}/><Meter label="Neural capacity" value="98.6" unit="%" amount={98.6}/>
              <div className="diagnostics-bottom"><span><i/> ALL SYSTEMS NOMINAL</span><ShieldCheck size={16}/></div>
            </Panel>
            <Panel title="POWER SIGNATURE" code="02" reduced={reduced} delay={.2} className="power-panel">
              <div className="power-reading"><strong>99.8<small>%</small></strong><span><Zap size={12}/> STABLE OUTPUT</span></div>
              <div className="power-chart" aria-label="Simulated stable power output"><div className="chart-grid"/><svg viewBox="0 0 240 60" preserveAspectRatio="none"><defs><linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stopColor="#00d9ff" stopOpacity=".2"/><stop offset="100%" stopColor="#00d9ff" stopOpacity="0"/></linearGradient></defs><path d="M0,39 L13,39 21,34 30,38 42,33 50,35 58,24 63,30 71,28 79,36 89,32 97,33 107,18 113,27 124,24 135,29 146,26 156,31 164,21 175,25 186,23 197,27 208,19 218,22 228,18 240,22 V60 H0Z" fill={`url(#${gradientId})`}/><path d="M0,39 L13,39 21,34 30,38 42,33 50,35 58,24 63,30 71,28 79,36 89,32 97,33 107,18 113,27 124,24 135,29 146,26 156,31 164,21 175,25 186,23 197,27 208,19 218,22 228,18 240,22" fill="none" stroke="#36bdd1" strokeWidth="1.4"/></svg></div>
              <div className="chart-labels"><span>60 SECONDS AGO</span><span>NOW</span></div>
            </Panel>
            <div className="engine-readout"><span className="engine-icon"><Fingerprint size={24}/></span><div><span>NEURAL ENGINE</span><strong>Mark VII <small>CONNECTED</small></strong></div><ArrowUpRight size={15}/></div></>}
          </aside>
          <section className="core-stage" aria-label="Assistant neural core">
            <div className="stage-heading"><span><span className="crosshair">⌖</span> NEURAL CORE</span><span>{mode === 'desktop' ? 'MAC DESKTOP · LOCAL AI' : 'ARC REACTOR · MK VII'}</span></div>
            <div className="core-viewport"><i className="corner corner-tl"/><i className="corner corner-tr"/><i className="corner corner-bl"/><i className="corner corner-br"/><span className="coordinate coordinate-left">SYS. 07 / 084</span><span className="coordinate coordinate-right">NEURAL LINK ESTABLISHED</span>
              <div className="core-status"><i/>{copy.label}</div>
              <JarvisOrb state={state} analyser={analyser} amplitude={amplitude} reducedMotion={reduced}/>
              <div className="core-floor"/><div className="orb-caption">{mode === 'desktop' ? <><span>ON-DEVICE</span><strong>LOCAL<span>AI</span></strong><span className="caption-line"/><span>PRIVATE SESSION</span></> : <><span>CORE SYNC</span><strong>100<span>%</span></strong><span className="caption-line"/><span>LATENCY</span><strong>12<span>ms</span></strong></>}</div>
            </div>
            <div className="core-message" aria-live="polite"><h2>{copy.title}</h2><p>{copy.subtitle}</p></div>
            {mode === 'desktop' ? <div className="desktop-state-row"><span className="desktop-state-pill"><i/>{microphoneStarting ? 'Connecting microphone' : state === 'idle' ? 'Ready for your next request' : state === 'listening' ? 'Listening on this Mac' : state === 'processing' ? 'Working on your request' : 'Speaking'}</span>{(state !== 'idle' || microphoneStarting) && <button className="desktop-stop" onClick={onCancel}>Stop</button>}</div> : <div className="state-selector" aria-label="Preview assistant state">{previewStates.map(item => <button key={item.state} aria-pressed={state === item.state} disabled={!onStateChange} className={state === item.state ? 'active' : ''} onClick={() => onStateChange?.(item.state)}>{state === item.state && <motion.span className="active-state-bg" layoutId={`${instanceId}-active-state`} transition={{duration: reduced ? 0 : .25}}/>}<span className={`state-dot state-dot-${item.state}`}/><span>{item.label}</span></button>)}</div>}
          </section>
          <aside className="right-instruments">
            <Panel title="ACTIVE PROTOCOLS" code="03" reduced={reduced} delay={.15}>
              <div className="protocol"><span className="protocol-icon"><AudioLines size={18}/></span><div><strong>Voice recognition</strong><span>{microphoneActive ? 'LIVE MICROPHONE' : (voiceStatusLabel ?? 'AWAITING INPUT')}</span></div><i className={microphoneActive ? 'live' : ''}/></div>
              <div className="protocol"><span className="protocol-icon"><ShieldCheck size={18}/></span><div><strong>Security protocol</strong><span>{securityStatusLabel ?? 'LOCAL SESSION ONLY'}</span></div><i className="live"/></div>
              <div className="protocol"><span className="protocol-icon"><Globe2 size={18}/></span><div><strong>{mode === 'desktop' ? 'Local AI' : 'Network uplink'}</strong><span>{mode === 'desktop' ? connectionLabel : 'CONNECTION STABLE'}</span></div><i className="live"/></div>
              <div className="protocol-note"><span className="signal-bars"><i/><i/><i/><i/></span><span>LOCAL INTERFACE</span><span>{mode === 'desktop' ? 'ON DEVICE' : '24 ms'}</span></div>
            </Panel>
            <Panel title="ACTIVITY LOG" reduced={reduced} delay={.25} className="activity-panel">
              <div className="activity-list" aria-live="polite">{activity.slice(-4).map(entry => <div className={`activity-entry ${entry.tone || ''}`} key={entry.id}><span className="activity-node"/><time>{entry.time}</time><p>{entry.message}</p></div>)}</div><div className="activity-footer"><span className="blinking-cursor"/>MONITORING SYSTEM ACTIVITY</div>
            </Panel>
          </aside>
        </div>
        <section className="command-area" aria-label="Command console">
          {transcript && <div className="live-transcript"><span>{microphoneActive ? 'HEARING' : 'YOU'}</span><p>{transcript}</p></div>}
          <AnimatePresence mode="wait">{(response || audioError || fullscreenError) && <motion.div key={audioError || fullscreenError || response} initial={{opacity:0, y: reduced ? 0 : 5}} animate={{opacity:1, y:0}} exit={{opacity:0}} className={`assistant-response ${audioError || fullscreenError ? 'response-error' : ''}`}><span className="response-icon">{audioError || fullscreenError ? <Radio size={18}/> : <Sparkles size={18}/>}</span><div><span className="response-label">{audioError || fullscreenError ? 'INTERFACE NOTICE' : 'J.A.R.V.I.S.'}</span><p><ResponseText text={audioError || fullscreenError || response} reduced={reduced}/></p></div>{fullscreenError && <button className="icon-button" aria-label="Dismiss notice" onClick={() => setFullscreenError('')}><X size={16}/></button>}</motion.div>}</AnimatePresence>
          <div className="console-topline"><span><span className="console-status"/> COMMAND CONSOLE</span><span><span className="key-symbol">⌘</span> K TO FOCUS</span></div>
          <div className="command-console"><div className="input-visual"><AudioLines size={24}/><span>{microphoneActive ? 'MIC LIVE' : (voiceStatusLabel ?? 'VOICE READY')}</span></div><form onSubmit={submit}><label className="sr-only" htmlFor={commandId}>Command</label><input id={commandId} ref={commandRef} value={command} onChange={e => setCommand(e.target.value)} placeholder="Ask J.A.R.V.I.S. anything…" autoComplete="off" disabled={!onCommand}/><button className="send-button" type="submit" aria-label="Send command" disabled={!command.trim() || !onCommand}><Send size={18}/></button></form><span className="console-divider"/><button className={`listen-button ${microphoneActive ? 'is-listening' : ''}`} aria-label={microphoneStarting ? 'Connecting microphone' : microphoneActive ? 'Stop listening' : 'Start listening'} disabled={microphoneStarting || (microphoneActive ? !onStopListening : !onListen)} onClick={() => microphoneActive ? onStopListening?.() : onListen?.()}>{microphoneActive ? <MicOff size={17}/> : <Mic size={17}/>}<span>{microphoneStarting ? 'CONNECTING' : microphoneActive ? 'STOP LISTENING' : 'START LISTENING'}</span></button></div>
          <div className="suggestions"><span>TRY A COMMAND</span>{suggestions.map((suggestion, i) => <button key={suggestion} onClick={() => onCommand?.(suggestion)} disabled={!onCommand}>{i === 0 ? <Activity size={12}/> : i === 1 ? <Cpu size={12}/> : <Command size={12}/>} {suggestion}<ChevronRight size={12}/></button>)}<span className="demo-label">{mode === 'desktop' ? 'PRIVATE · ON-DEVICE ASSISTANT' : 'SIMULATED ENVIRONMENT'}</span></div>
          {controls}
        </section>
      </main>
      <footer className="footer"><span className="stark-mark"><span>◩</span> STARK INDUSTRIES <span className="footer-divider">/</span><small>ADVANCED INTELLIGENCE DIVISION</small></span><span className="footer-center">J.A.R.V.I.S. PROTOCOL <span>4.0.2</span></span><span className="footer-secure"><ShieldCheck size={12}/> LOCAL SESSION <span className="tiny-dot"/></span></footer>
    </div>
    <AnimatePresence>{settingsOpen && <motion.aside className="settings-popover" aria-label="Interface settings" initial={{opacity:0, y:reduced ? 0 : -8}} animate={{opacity:1, y:0}} exit={{opacity:0}}><div className="settings-heading"><h2>Interface settings</h2><button ref={settingsCloseRef} className="icon-button" aria-label="Close settings" onClick={() => {setSettingsOpen(false); settingsRef.current?.focus()}}><X size={16}/></button></div><p>Make the interface your own.</p><label className="setting-row"><span>Ambient motion<small>{prefersReduced || reducedMotion ? 'Reduced by your system preference' : 'Reactor, particles and scan lines'}</small></span><input type="checkbox" checked={!reduced} disabled={Boolean(prefersReduced || reducedMotion)} onChange={e=>setStillMode(!e.target.checked)}/><span className="switch"/></label><label className="setting-row"><span>Telemetry panels<small>{mode === 'desktop' ? 'Connection and command information' : 'Simulated system readouts'}</small></span><input type="checkbox" checked={telemetry} onChange={e=>setTelemetry(e.target.checked)}/><span className="switch"/></label><div className="settings-foot"><Check size={12}/> Preferences apply to this session</div></motion.aside>}</AnimatePresence>
  </div>
}
