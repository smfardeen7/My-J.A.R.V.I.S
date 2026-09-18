import { useEffect, useId, useRef } from 'react'
import { useReducedMotion } from 'framer-motion'
import type { JarvisOrbProps } from '../types'
import './orb.css'

const TAU = Math.PI * 2

function point(radius: number, angle: number) {
  return [300 + Math.cos(angle) * radius, 300 + Math.sin(angle) * radius]
}

function arc(radius: number, start: number, end: number) {
  const from = point(radius, (start * Math.PI) / 180)
  const to = point(radius, (end * Math.PI) / 180)
  return `M ${from[0]} ${from[1]} A ${radius} ${radius} 0 ${end - start > 180 ? 1 : 0} 1 ${to[0]} ${to[1]}`
}

function ticks(radius: number, count: number, length: number, majorEvery = 5) {
  return Array.from({ length: count }, (_, index) => {
    const angle = (index / count) * TAU
    const from = point(radius, angle)
    const to = point(radius + (index % majorEvery === 0 ? length * 1.8 : length), angle)
    return `M ${from[0]} ${from[1]} L ${to[0]} ${to[1]}`
  }).join(' ')
}

/** A presentational, audio-reactive reactor. Supply an analyser from any audio source. */
export function JarvisOrb({ state = 'idle', analyser = null, amplitude, className = '', reducedMotion = false }: JarvisOrbProps) {
  const root = useRef<HTMLDivElement>(null)
  const canvas = useRef<HTMLCanvasElement>(null)
  const amplitudeRef = useRef(amplitude)
  const systemReducedMotion = useReducedMotion()
  const limitMotion = Boolean(reducedMotion || systemReducedMotion)
  const id = useId().replace(/:/g, '')

  // High-frequency controlled audio updates must not recreate the canvas loop.
  useEffect(() => {
    amplitudeRef.current = amplitude
  }, [amplitude])

  useEffect(() => {
    const element = root.current
    const surface = canvas.current
    if (!element || !surface) return
    const context = surface.getContext('2d')
    if (!context) return

    let frame = 0
    let size = 600
    let energy = 0
    const bins = analyser ? new Uint8Array(analyser.frequencyBinCount) : null
    const samples = analyser ? new Uint8Array(analyser.fftSize) : null
    const draw = (time: number) => {
      const seconds = limitMotion ? 0 : time / 1000
      const suppliedAmplitude = amplitudeRef.current
      let level = typeof suppliedAmplitude === 'number' && Number.isFinite(suppliedAmplitude)
        ? Math.min(1, Math.max(0, suppliedAmplitude))
        : undefined
      if (analyser && bins && samples) {
        analyser.getByteFrequencyData(bins)
        analyser.getByteTimeDomainData(samples)
        let sum = 0
        for (const value of samples) sum += ((value - 128) / 128) ** 2
        level = Math.min(1, Math.sqrt(sum / samples.length) * 4)
      }
      const active = state === 'listening' || state === 'speaking'
      if (level === undefined) {
        level = active
          ? 0.25 + 0.24 * Math.sin(seconds * 4.2) ** 2 + 0.12 * Math.sin(seconds * 9.1) ** 2
          : state === 'processing' ? 0.3 : 0.07 + Math.sin(seconds * 1.25) * 0.03
      }
      energy += (level - energy) * 0.13
      element.style.setProperty('--core-activity', (0.48 + energy * 0.52).toFixed(3))
      element.style.setProperty('--core-scale', limitMotion ? '1' : (1 + energy * 0.05).toFixed(3))

      context.clearRect(0, 0, size, size)
      const scale = size / 600
      context.save()
      context.scale(scale, scale)
      context.lineCap = 'round'
      const bars = 144
      for (let index = 0; index < bars; index++) {
        const angle = (index / bars) * TAU - Math.PI / 2
        const bin = bins ? bins[Math.floor((index / bars) * Math.min(bins.length, 100))] / 255 : undefined
        const ripple = Math.sin(index * 0.49 + seconds * 2.2) * Math.sin(index * 0.17 - seconds * 1.8)
        const height = limitMotion ? 3.5 : 2.5 + (bin ?? (ripple * 0.5 + 0.5)) * (5 + energy * 23)
        const inner = 210
        const from = point(inner, angle)
        const to = point(inner + height, angle)
        context.beginPath()
        context.strokeStyle = `rgba(82, 225, 250, ${0.16 + energy * 0.35 + (index % 3 === 0 ? 0.1 : 0)})`
        context.lineWidth = index % 12 === 0 ? 1.6 : 1
        context.moveTo(from[0], from[1])
        context.lineTo(to[0], to[1])
        context.stroke()
      }
      context.restore()
      if (!limitMotion && !document.hidden) frame = requestAnimationFrame(draw)
    }

    const resize = () => {
      const width = element.getBoundingClientRect().width
      size = Math.max(1, width)
      const dpr = Math.min(window.devicePixelRatio || 1, 2)
      surface.width = Math.round(size * dpr)
      surface.height = Math.round(size * dpr)
      context.setTransform(dpr, 0, 0, dpr, 0, 0)
      if (limitMotion) draw(0)
    }
    const onVisibility = () => {
      element.dataset.paused = String(document.hidden)
      cancelAnimationFrame(frame)
      if (!document.hidden) draw(performance.now())
    }

    const observer = new ResizeObserver(resize)
    observer.observe(element)
    resize()
    onVisibility()
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      cancelAnimationFrame(frame)
      observer.disconnect()
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [state, analyser, limitMotion])

  return (
    <div ref={root} className={`jarvis-orb ${className}`} data-state={state} data-reduced-motion={limitMotion} role="img" aria-label={`Assistant reactor: ${state}`}>
      <div className="orb-ambient-halo" />
      <svg className="orb-geometry" viewBox="0 0 600 600" fill="none" aria-hidden="true">
        <defs>
          <radialGradient id={`${id}-core`}>
            <stop offset="0" stopColor="#c5fcff" stopOpacity=".88" />
            <stop offset=".11" stopColor="#33dcfa" stopOpacity=".68" />
            <stop offset=".46" stopColor="#08bde7" stopOpacity=".28" />
            <stop offset=".79" stopColor="#00ccfa" stopOpacity=".18" />
            <stop offset="1" stopColor="#23e4ff" stopOpacity=".02" />
          </radialGradient>
          <radialGradient id={`${id}-ring`}>
            <stop offset=".67" stopColor="#00b9e6" stopOpacity="0" />
            <stop offset=".92" stopColor="#00bce9" stopOpacity=".07" />
            <stop offset="1" stopColor="#62eaff" stopOpacity=".32" />
          </radialGradient>
          <linearGradient id={`${id}-blade`} x1="0" y1="0" x2="1" y2="1">
            <stop stopColor="#61edff" stopOpacity=".1" />
            <stop offset=".65" stopColor="#16badc" stopOpacity=".04" />
            <stop offset="1" stopColor="#6debff" stopOpacity=".3" />
          </linearGradient>
          <filter id={`${id}-glow`} x="-100%" y="-100%" width="300%" height="300%">
            <feGaussianBlur stdDeviation="2.2" result="blur" />
            <feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
          </filter>
        </defs>

        <g className="orb-fixed-guides" stroke="#64ddeb">
          <circle cx="300" cy="300" r="274" strokeOpacity=".045" />
          <circle cx="300" cy="300" r="253" strokeOpacity=".1" strokeDasharray="2 9" />
          <path d="M 300 14 V 29 M 300 571 V 586 M 14 300 H 29 M 571 300 H 586" strokeOpacity=".48" />
          <path d="M 294 20 H 306 M 294 580 H 306 M 20 294 V 306 M 580 294 V 306" strokeOpacity=".3" />
          {[45, 135, 225, 315].map(angle => <path key={angle} d={arc(274, angle - 4, angle + 4)} strokeOpacity=".26" />)}
        </g>

        <g className="orb-ring orb-ring-outer" stroke="#5cdeed">
          <circle cx="300" cy="300" r="262" strokeOpacity=".22" strokeWidth=".8" strokeDasharray="320 70 80 130 180 400" />
          <path d={ticks(257, 120, 4, 10)} strokeOpacity=".23" strokeWidth=".8" />
          <path d={arc(247, 180, 239)} strokeOpacity=".57" strokeWidth="2" />
          <path d={arc(247, 249, 298)} strokeOpacity=".16" strokeWidth="2" />
          <path d={arc(247, 335, 426)} strokeOpacity=".52" strokeWidth="2" />
          <circle cx="300" cy="53" r="2.5" fill="#8bedf5" stroke="none" />
        </g>

        <g className="orb-ring orb-ring-segments" stroke="#37d9f1">
          {Array.from({ length: 6 }, (_, index) => (
            <g key={index}>
              <path d={arc(236, index * 60 + 4, index * 60 + 49)} strokeWidth="7" strokeOpacity={index % 2 === 0 ? '.19' : '.07'} />
              <path d={arc(240, index * 60 + 4, index * 60 + 47)} strokeWidth=".8" strokeOpacity=".48" />
              <path d={arc(230, index * 60 + 9, index * 60 + 35)} strokeWidth="1" strokeOpacity=".31" />
            </g>
          ))}
        </g>

        <g className="orb-ring orb-ring-middle" stroke="#22cce9">
          <circle cx="300" cy="300" r="201" strokeOpacity=".27" />
          <circle cx="300" cy="300" r="195" strokeOpacity=".14" />
          <path d={ticks(187, 160, 6, 8)} strokeOpacity=".53" strokeWidth="1.2" />
          <path d={arc(181, 2, 104)} strokeOpacity=".58" strokeWidth="2" />
          <path d={arc(181, 143, 238)} strokeOpacity=".17" strokeWidth="2" />
          <path d={arc(181, 276, 341)} strokeOpacity=".65" strokeWidth="2" />
        </g>

        <g className="orb-ring orb-ring-armature" stroke="#49dff5">
          <circle cx="300" cy="300" r="171" strokeOpacity=".11" />
          {Array.from({ length: 12 }, (_, index) => (
            <g key={index} transform={`rotate(${index * 30} 300 300)`}>
              <path d={arc(162, 2, 24)} strokeWidth="14" strokeOpacity={index % 3 === 0 ? '.30' : '.15'} />
              <path d={arc(169, 2, 24)} strokeWidth=".8" strokeOpacity=".42" />
              <path d="M 310 141 L 312 154" strokeOpacity=".45" />
              <path d="M 340 146 L 337 158" strokeOpacity=".2" />
            </g>
          ))}
          <path d={ticks(144, 100, 5, 5)} strokeWidth="1.2" strokeOpacity=".66" />
          <circle cx="300" cy="300" r="139" strokeOpacity=".82" strokeWidth="1" />
          <circle cx="300" cy="300" r="135" strokeOpacity=".2" strokeWidth="3" />
        </g>

        <g className="orb-core">
          <circle cx="300" cy="300" r="129" fill={`url(#${id}-ring)`} />
          <circle cx="300" cy="300" r="116" stroke="#4be7ff" strokeOpacity=".95" strokeWidth="2" filter={`url(#${id}-glow)`} />
          <circle cx="300" cy="300" r="109" stroke="#46e0f8" strokeOpacity=".28" strokeWidth=".8" />
          <circle cx="300" cy="300" r="101" fill={`url(#${id}-core)`} />
          <g className="orb-ring orb-turbine">
            {Array.from({ length: 18 }, (_, index) => (
              <path key={index} d="M 300 203 C 326 208 331 251 309 283 L 303 293 C 316 259 316 225 300 203 Z" transform={`rotate(${index * 20} 300 300)`} fill={`url(#${id}-blade)`} stroke="#48ddf5" strokeOpacity=".15" strokeWidth=".7" />
            ))}
            <path d={ticks(100, 120, 4, 10)} stroke="#4fe3fc" strokeOpacity=".37" strokeWidth=".65" />
          </g>
          <g stroke="#4bdcf7" strokeOpacity=".12">
            <circle cx="300" cy="300" r="76" />
            <circle cx="300" cy="300" r="57" />
            <path d="M 206 300 H 394 M 300 206 V 394 M 233 233 L 367 367 M 367 233 L 233 367" />
          </g>
          <circle className="orb-central-light" cx="300" cy="300" r="30" fill={`url(#${id}-core)`} />
          <circle cx="300" cy="300" r="4" fill="#c6fbff" filter={`url(#${id}-glow)`} />
          <path d="M 285 300 H 315 M 300 285 V 315" stroke="#84ebff" strokeOpacity=".7" strokeWidth=".7" />
        </g>

        <g className="orb-ring orb-processing-particles" fill="#8ceaff">
          <circle cx="300" cy="87" r="2.6" />
          <circle cx="114" cy="407" r="1.7" />
          <circle cx="485" cy="407" r="2.1" />
          <path d={arc(212, 254, 270)} stroke="#4ae1ff" strokeWidth="1.2" />
        </g>
      </svg>
      <canvas ref={canvas} className="orb-waveform" aria-hidden="true" />
      <div className="orb-sweep-mask"><div className="orb-sweep" /></div>
    </div>
  )
}

export default JarvisOrb
