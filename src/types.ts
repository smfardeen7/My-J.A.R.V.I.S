export type JarvisState = 'idle' | 'listening' | 'processing' | 'speaking'

export interface JarvisOrbProps {
  state?: JarvisState
  analyser?: AnalyserNode | null
  amplitude?: number
  className?: string
  reducedMotion?: boolean
}

export interface ActivityEntry {
  id: string
  time: string
  message: string
  tone?: 'default' | 'success' | 'warning'
}
