import { useEffect, useRef, useState } from 'react'
import { MotionConfig } from 'framer-motion'
import { Cpu, Mic, RefreshCw, ShieldCheck, Terminal, Trash2 } from 'lucide-react'
import { JarvisHUD } from '../components/JarvisHUD'
import type { ActivityEntry, JarvisState } from '../types'
import { nativeCommand, onNativeEvent } from './bridge'
import type { NativeConfig } from './bridge'
import type { OwnerVoiceStatus } from './bridge'
import { OwnerVoicePanel } from './OwnerVoicePanel'
import './desktop.css'

const initialConfig: NativeConfig = {model:'',models:[],connected:false,soundEnabled:true,device:'This Mac',memoryGB:0}
export default function DesktopApp() {
  const activityId = useRef(0)
  const [state,setState] = useState<JarvisState>('idle')
  const [config,setConfig] = useState(initialConfig)
  const [amplitude,setAmplitude] = useState(0)
  const [response,setResponse] = useState('')
  const [transcript,setTranscript] = useState('')
  const [error,setError] = useState('')
  const [microphone,setMicrophone] = useState({active:false,starting:false})
  const [activity,setActivity] = useState<ActivityEntry[]>([])
  const [owner,setOwner] = useState<OwnerVoiceStatus>({name:'Fardeen',enrolled:false,runtimeReady:false,enrolling:false,samples:0,phrase:'',locale:''})
  useEffect(() => {
    const unsubscribe=onNativeEvent(event=> {
      switch(event.type) {
        case 'config':setConfig(event);break
        case 'owner':setOwner(event);break
        case 'state':setState(event.state);break
        case 'amplitude':setAmplitude(event.value);break
        case 'response':setResponse(event.text);break
        case 'transcript':setTranscript(event.text);break
        case 'command':setTranscript(event.text);break
        case 'listening':setMicrophone({active:event.active,starting:event.starting});break
        case 'error':setError(event.message);break
        case 'activity':setActivity(previous=>[...previous.slice(-3),{id:`native-${++activityId.current}`,time:new Date().toLocaleTimeString('en-GB'),message:event.message,tone:event.tone}]);break
      }
    })
    nativeCommand('ready')
    return unsubscribe
  },[])
  useEffect(()=>{
    function key(event:KeyboardEvent) {
      if((event.metaKey || event.ctrlKey) && event.shiftKey && event.code === 'Space') {event.preventDefault();nativeCommand(microphone.active ? 'stopListening':'listen')}
      if(event.key==='Escape' && (state !== 'idle' || microphone.starting)) nativeCommand('cancel')
    }
    window.addEventListener('keydown',key)
    return ()=>window.removeEventListener('keydown',key)
  },[microphone.active,microphone.starting,state])
  const connected=config.connected && config.models.length > 0
  function command(text:string) {setError('');nativeCommand('command',{text})}
  const sidebar=<>
    <section className="native-panel"><h2><Cpu size={15}/> LOCAL INTELLIGENCE</h2><div className="native-model-name">{config.model || 'Connecting…'}</div><p>{connected ? 'Running privately on this Mac' : config.connected ? 'A local model is needed' : 'Waiting for Ollama'}</p><div className="native-detail"><span>Connection</span><strong className={connected ? 'native-online':'native-warning'}>{connected ? 'CONNECTED':'NOT READY'}</strong></div><div className="native-detail"><span>Memory installed</span><strong>{config.memoryGB ? `${config.memoryGB} GB`:'—'}</strong></div><div className="native-detail"><span>Conversation</span><strong>SESSION ONLY</strong></div><div className="native-panel-note"><ShieldCheck size={13}/> No cloud AI requests</div></section>
    <section className="native-panel"><h2><Terminal size={15}/> MAC COMMANDS</h2><div className="native-command-list">{['Open Safari','What time is it?','System status','Set volume to 40%'].map(text=><button key={text} onClick={()=>command(text)}><span>{text}</span><span>↗</span></button>)}</div><p className="native-command-hint">App and volume actions run only when you explicitly ask.</p></section>
    <div className="native-voice-hint"><Mic size={18}/><p>Speak for at least three seconds, then click the mic to send.<small>Voice match + Touch ID for Mac actions · Robotic voice</small></p></div>
  </>
  const controls=<><OwnerVoicePanel owner={owner} busy={state!=='idle' || microphone.starting} recording={microphone.active}/><div className="native-controls"><label><span>LOCAL AI</span><select aria-label="Local AI model" value={config.models.includes(config.model)?config.model:''} disabled={!config.models.length} onChange={event=>nativeCommand('model',{name:event.target.value})}>{!config.models.length && <option value="">{config.connected?'No model installed':'Ollama offline'}</option>}{config.models.map(name=><option key={name} value={name}>{name}</option>)}</select></label><button onClick={()=>nativeCommand('refresh')}><RefreshCw size={13}/> Refresh connection</button><button onClick={()=>{nativeCommand('clear');setTranscript('');setError('')}}><Trash2 size={13}/> Clear conversation</button><span>Voice stays on this device</span></div></>
  return <MotionConfig reducedMotion="user"><JarvisHUD mode="desktop" state={state} amplitude={amplitude} voiceStatusLabel={owner.enrolling ? 'ENROLLING VOICE' : owner.enrolled ? 'VOICE MATCH READY' : 'VOICE LOCKED'} securityStatusLabel="TOUCH ID FOR ACTIONS" response={response} transcript={transcript} activity={activity} audioError={error} connectionLabel={connected ? 'LOCAL AI ONLINE':'MAC COMMANDS READY'} statusText="At your service, Fardeen. Local intelligence. Personal access." sidebarContent={sidebar} controls={controls} onCommand={command} onListen={()=>{setError('');setTranscript('');nativeCommand('listen')}} onStopListening={()=>nativeCommand('stopListening')} onCancel={()=>nativeCommand('cancel')} microphoneActive={microphone.active} microphoneStarting={microphone.starting} soundEnabled={config.soundEnabled} onSoundChange={enabled=>nativeCommand('sound',{enabled})} onFullscreen={()=>nativeCommand('fullscreen')} suggestions={['Open Safari','System status','What can you do?']}/></MotionConfig>
}
