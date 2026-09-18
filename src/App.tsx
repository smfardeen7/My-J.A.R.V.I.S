import { useCallback, useEffect, useReducer, useRef, useState } from 'react'
import { MotionConfig } from 'framer-motion'
import { JarvisHUD } from './components/JarvisHUD'
import { useAudioAnalyser } from './hooks/useAudioAnalyser'
import { jarvisStateReducer } from './state'
import type { ActivityEntry, JarvisState } from './types'

const timeNow = () => new Date().toLocaleTimeString('en-GB')
const initialActivity: ActivityEntry[] = [
  {id:'boot',time:timeNow(),message:'Neural interface initialized',tone:'success'},
  {id:'local',time:timeNow(),message:'Local session established'},
  {id:'sync',time:timeNow(),message:'Visual modules synchronized'},
  {id:'ready',time:timeNow(),message:'All systems ready',tone:'success'},
]

// This demo controller is intentionally separate from the reusable UI shell.
// Replace these sample responses and transitions with your assistant's events.
export default function App() {
  const [state, dispatch] = useReducer(jarvisStateReducer, 'idle')
  const [response, setResponse] = useState('')
  const [activity, setActivity] = useState(initialActivity)
  const [soundEnabled, setSoundEnabled] = useState(false)
  const timers = useRef<ReturnType<typeof setTimeout>[]>([])
  const soundContext = useRef<AudioContext | null>(null)
  const audio = useAudioAnalyser()
  const requestId = useRef(0)
  const wasMicActive = useRef(false)
  const clearTimers = useCallback(() => {
    timers.current.forEach(clearTimeout)
    timers.current = []
  }, [])
  const log = useCallback((message: string, tone: ActivityEntry['tone'] = 'default') => {
    setActivity(items => [...items.slice(-3), {id:crypto.randomUUID(),time:timeNow(),message,tone}])
  }, [])
  useEffect(() => () => {clearTimers(); void soundContext.current?.close()}, [clearTimers])
  useEffect(() => {
    if (wasMicActive.current && !audio.isActive) {
      dispatch({type:'RESET'})
      log('Microphone link closed')
    }
    wasMicActive.current = audio.isActive
  }, [audio.isActive, log])
  function playTone(enabled = soundEnabled) {
    if(!enabled) return
    try {
      const context = soundContext.current ||= new AudioContext()
      void context.resume().catch(() => {})
      const oscillator = context.createOscillator()
      const gain = context.createGain()
      oscillator.connect(gain);gain.connect(context.destination)
      oscillator.frequency.setValueAtTime(620, context.currentTime)
      oscillator.frequency.exponentialRampToValueAtTime(880, context.currentTime + .1)
      gain.gain.setValueAtTime(.025, context.currentTime)
      gain.gain.exponentialRampToValueAtTime(.0001, context.currentTime + .15)
      oscillator.start(); oscillator.stop(context.currentTime + .16)
      oscillator.onended = () => {oscillator.disconnect(); gain.disconnect()}
    } catch { /* Interface audio is optional. */ }
  }
  function reset() {
    requestId.current++
    wasMicActive.current = false
    clearTimers();audio.stop();dispatch({type:'RESET'})
  }
  function preview(next: JarvisState) {
    reset();setResponse('');playTone()
    if(next !== 'idle') dispatch({type:'LISTEN'})
    if(next === 'processing' || next === 'speaking') dispatch({type:'PROCESS'})
    if(next === 'speaking') dispatch({type:'SPEAK'})
    log(`${next.charAt(0).toUpperCase()+next.slice(1)} visual preview`)
  }
  function runCommand(command: string) {
    reset();setResponse('');playTone();log('Command received')
    dispatch({type:'LISTEN'})
    timers.current.push(setTimeout(()=> {dispatch({type:'PROCESS'});log('Running interface simulation')}, 350))
    let answer: string
    if(/diagnostic/i.test(command)) answer = 'Diagnostic simulation complete. Neural core synchronized. Memory, processing, and power signatures are all within nominal parameters. The interface is ready.'
    else if(/status/i.test(command)) answer = 'All systems nominal. Neural capacity at 98.6%, power output at 99.8%. These are simulated telemetry readings; your device’s performance is not being monitored.'
    else if(/what|help|can you/i.test(command)) answer = 'I can visualize listening, thinking, and speaking; react to your microphone; and display your assistant’s responses. Try the state controls, or start listening to see the reactor respond to your voice.'
    else answer = `Received: “${command}”. This is an interface demonstration. Connect your assistant through the onCommand callback to display real responses here.`
    timers.current.push(setTimeout(()=> {dispatch({type:'SPEAK'});setResponse(answer);log('Sample response ready', 'success')}, 1900))
    timers.current.push(setTimeout(()=> {dispatch({type:'COMPLETE'});log('Standing by for your next command')}, 8500))
  }
  async function startListening() {
    reset();setResponse('')
    const id = requestId.current
    const started = await audio.start()
    if(id !== requestId.current) return
    if(started) {dispatch({type:'LISTEN'});log('Microphone connected', 'success');playTone()}
    else {log('Microphone unavailable', 'warning')}
  }
  function stopListening() { reset();setResponse('Microphone disconnected. Audio was visualized locally; nothing was recorded or sent.');log('Microphone disconnected');playTone() }
  return <MotionConfig reducedMotion="user"><JarvisHUD state={state} analyser={audio.analyser} response={response} activity={activity} onCommand={runCommand} onStateChange={preview} onListen={startListening} onStopListening={stopListening} microphoneActive={audio.isActive} microphoneStarting={audio.isStarting} audioError={audio.error} soundEnabled={soundEnabled} onSoundChange={enabled => {setSoundEnabled(enabled);playTone(enabled)}}/></MotionConfig>
}
