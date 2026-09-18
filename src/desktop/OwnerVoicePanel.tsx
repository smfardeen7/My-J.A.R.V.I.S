import { Fingerprint, Mic, ShieldCheck } from 'lucide-react'
import { nativeCommand } from './bridge'
import type { OwnerVoiceStatus } from './bridge'

export function OwnerVoicePanel({owner, busy, recording}: {owner: OwnerVoiceStatus; busy: boolean; recording: boolean}) {
  return <section className="native-owner-panel" aria-label="Fardeen voice access">
    <div className="native-owner-heading"><ShieldCheck size={18}/><div><h2>FARDEEN / VOICE ACCESS</h2><p>{owner.enrolled ? 'Voice profile enrolled · Touch ID for Mac actions' : 'Voice commands locked · Enroll your voice to begin'}</p></div><span className={owner.enrolled ? 'native-online' : 'native-warning'}>{owner.enrolled ? 'ENROLLED' : 'SETUP NEEDED'}</span></div>
    {owner.enrolling ? <div className="native-enrollment">
      <div className="native-enrollment-step">SAMPLE {Math.min(owner.samples + 1, 3)} OF 3 <span>Read naturally for 8–15 seconds in a quiet room.</span></div>
      <blockquote>{owner.phrase}</blockquote>
      <div className="native-owner-actions"><button disabled={busy && !recording} onClick={()=>nativeCommand(recording ? 'stopListening' : 'enrollSample')}><Mic size={14}/>{recording ? 'Finish sample' : `Record sample ${Math.min(owner.samples + 1, 3)}`}</button><button className="native-owner-secondary" onClick={()=>nativeCommand('cancel')}>Cancel enrollment</button></div>
    </div> : <div className="native-owner-actions">
      <button disabled={busy || !owner.runtimeReady} onClick={()=>nativeCommand('enroll')}><Fingerprint size={14}/>{owner.enrolled ? 'Re-enroll my voice' : 'Set up my voice with Touch ID'}</button>
      {owner.enrolled && <button className="native-owner-secondary" disabled={busy} onClick={()=>nativeCommand('forgetVoice')}>Delete voice profile</button>}
      <label>Speech accent<select aria-label="Speech recognition accent" value={owner.locale} disabled={busy} onChange={event=>nativeCommand('recognitionLocale',{locale:event.target.value})}><option value="">System English</option><option value="en-US">English · US</option><option value="en-GB">English · UK</option><option value="en-IN">English · India</option><option value="en-AU">English · Australia</option></select></label>
    </div>}
    {!owner.runtimeReady && <p className="native-warning">Local voice model is not ready. Run the voice setup installer.</p>}
    <p className="native-owner-note">Voice matching is a fallible filter and can accept recordings. Touch ID accepts any fingerprint enrolled in this Mac account. Only Fardeen should enroll. Recordings are deleted after processing; the voice profile stays in Keychain.</p>
  </section>
}
