import { useCallback, useEffect, useRef, useState } from 'react'

interface AudioResources {
  context: AudioContext
  source: MediaStreamAudioSourceNode
  stream: MediaStream
  released: boolean
  onEnded: () => void
}

export interface AudioAnalyserControls {
  analyser: AnalyserNode | null
  isActive: boolean
  isStarting: boolean
  error: string | null
  start: () => Promise<boolean>
  stop: () => void
}

function release(resources: AudioResources | null) {
  if (!resources || resources.released) return
  resources.released = true
  for (const track of resources.stream.getTracks()) {
    track.removeEventListener('ended', resources.onEnded)
    track.stop()
  }
  resources.source.disconnect()
  if (resources.context.state !== 'closed') void resources.context.close().catch(() => {})
}

function describeAudioError(error: unknown): string {
  // DOMException may come from a different browser realm than Error.
  const name = typeof error === 'object' && error !== null && 'name' in error ? error.name : ''
  if (name === 'NotAllowedError' || name === 'SecurityError') {
    return 'Microphone permission was denied. Allow microphone access in your browser and try again.'
  }
  if (name === 'NotFoundError') return 'No microphone was found. Connect an input device and try again.'
  if (name === 'NotReadableError') return 'The microphone is unavailable or is being used by another application.'
  return 'Could not start the microphone. Check your audio device and try again.'
}

/**
 * Opt-in microphone analysis. Nothing is recorded, transmitted, or routed to speakers.
 * Call start() from a user interaction; stop() also cancels pending permission requests.
 */
export function useAudioAnalyser(): AudioAnalyserControls {
  const [analyser, setAnalyser] = useState<AnalyserNode | null>(null)
  const [isActive, setIsActive] = useState(false)
  const [isStarting, setIsStarting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const resourcesRef = useRef<AudioResources | null>(null)
  const pendingRef = useRef<Promise<boolean> | null>(null)
  const generationRef = useRef(0)
  const mountedRef = useRef(true)

  const stop = useCallback(() => {
    generationRef.current += 1
    pendingRef.current = null
    release(resourcesRef.current)
    resourcesRef.current = null
    if (mountedRef.current) {
      setAnalyser(null)
      setIsActive(false)
      setIsStarting(false)
      setError(null)
    }
  }, [])

  const start = useCallback((): Promise<boolean> => {
    if (!mountedRef.current) return Promise.resolve(false)
    if (resourcesRef.current && !pendingRef.current) return Promise.resolve(true)
    if (pendingRef.current) return pendingRef.current

    const AudioContextConstructor = typeof window !== 'undefined'
      ? window.AudioContext ?? (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext
      : undefined
    if (!AudioContextConstructor || !navigator.mediaDevices?.getUserMedia) {
      setError('Microphone analysis is not supported here. Use a browser on HTTPS or localhost.')
      return Promise.resolve(false)
    }

    const generation = ++generationRef.current
    const isCurrent = () => mountedRef.current && generationRef.current === generation
    setError(null)
    setIsStarting(true)

    const operation = (async (): Promise<boolean> => {
      let stream: MediaStream | null = null
      let context: AudioContext | null = null
      let resources: AudioResources | null = null
      try {
        stream = await navigator.mediaDevices.getUserMedia({ audio: true })
        if (!isCurrent()) {
          stream.getTracks().forEach((track) => track.stop())
          return false
        }

        context = new AudioContextConstructor()
        const nextAnalyser = context.createAnalyser()
        nextAnalyser.fftSize = 256
        nextAnalyser.smoothingTimeConstant = 0.78
        const source = context.createMediaStreamSource(stream)
        resources = { context, source, stream, released: false, onEnded: stop }
        resourcesRef.current = resources
        // Leaving the analyser disconnected from destination prevents microphone echo.
        source.connect(nextAnalyser)
        for (const track of stream.getTracks()) track.addEventListener('ended', stop)
        if (context.state === 'suspended') await context.resume()

        if (!isCurrent()) {
          release(resources)
          return false
        }

        setAnalyser(nextAnalyser)
        setIsActive(true)
        return true
      } catch (cause) {
        if (resources) release(resources)
        else {
          stream?.getTracks().forEach((track) => track.stop())
          if (context && context.state !== 'closed') void context.close().catch(() => {})
        }
        if (resourcesRef.current === resources) resourcesRef.current = null
        if (isCurrent()) {
          setAnalyser(null)
          setIsActive(false)
          setError(describeAudioError(cause))
        }
        return false
      }
    })()

    pendingRef.current = operation.finally(() => {
      if (isCurrent()) {
        pendingRef.current = null
        setIsStarting(false)
      }
    })
    return pendingRef.current
  }, [stop])

  useEffect(() => {
    mountedRef.current = true
    return () => {
      mountedRef.current = false
      generationRef.current += 1
      pendingRef.current = null
      release(resourcesRef.current)
      resourcesRef.current = null
    }
  }, [])

  return { analyser, isActive, isStarting, error, start, stop }
}
