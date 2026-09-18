import type { JarvisState } from './types'

export type JarvisEvent = {
  type: 'LISTEN' | 'PROCESS' | 'SPEAK' | 'COMPLETE' | 'RESET'
}

/** Events advance one phase; RESET can interrupt any phase. */
export function jarvisStateReducer(state: JarvisState, event: JarvisEvent): JarvisState {
  if (event.type === 'RESET') return 'idle'

  switch (state) {
    case 'idle': return event.type === 'LISTEN' ? 'listening' : state
    case 'listening': return event.type === 'PROCESS' ? 'processing' : state
    case 'processing': return event.type === 'SPEAK' ? 'speaking' : state
    case 'speaking': return event.type === 'COMPLETE' ? 'idle' : state
  }
}
