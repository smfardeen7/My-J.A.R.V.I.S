export interface NativeConfig {
  model: string
  models: string[]
  connected: boolean
  soundEnabled: boolean
  device: string
  memoryGB: number
}

export type NativeEvent =
  | ({type: 'config'} & NativeConfig)
  | {type: 'state'; state: 'idle'|'listening'|'processing'|'speaking'}
  | {type: 'amplitude'; value: number}
  | {type: 'response'|'command'; text: string}
  | {type: 'transcript'; text: string; final: boolean}
  | {type: 'listening'; active: boolean; starting: boolean}
  | {type: 'speech'; active: boolean}
  | {type: 'error'; message: string}
  | {type: 'activity'; message: string; tone?: 'default'|'success'|'warning'}
  | ({type: 'owner'} & OwnerVoiceStatus)

export interface OwnerVoiceStatus {
  name: string
  enrolled: boolean
  runtimeReady: boolean
  enrolling: boolean
  samples: number
  phrase: string
  locale: string
}

declare global {
  interface Window {
    __JARVIS_DESKTOP__?: boolean
    webkit?: {messageHandlers?: {jarvis?: {postMessage: (message: unknown) => void}}}
  }
}
export const isDesktop = () => window.__JARVIS_DESKTOP__ === true && !!window.webkit?.messageHandlers?.jarvis
export function nativeCommand(action: string, payload: Record<string, unknown> = {}) {
  if(!isDesktop()) throw new Error('Native commands are available only in the J.A.R.V.I.S. Mac app.')
  window.webkit!.messageHandlers!.jarvis!.postMessage({action,payload})
}
export function onNativeEvent(handler: (event: NativeEvent) => void) {
  const listener = (event: Event) => handler((event as CustomEvent<NativeEvent>).detail)
  window.addEventListener('jarvis:native',listener)
  return () => window.removeEventListener('jarvis:native',listener)
}
