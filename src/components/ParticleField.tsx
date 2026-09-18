import { useEffect, useRef } from 'react'
import { useReducedMotion } from 'framer-motion'
import './orb.css'

export interface ParticleFieldProps {
  reducedMotion?: boolean
}

/** A lightweight ambient field. Animation pauses when the document is hidden. */
export function ParticleField({ reducedMotion = false }: ParticleFieldProps) {
  const canvas = useRef<HTMLCanvasElement>(null)
  const systemReducedMotion = useReducedMotion()
  const limitMotion = Boolean(reducedMotion || systemReducedMotion)

  useEffect(() => {
    const surface = canvas.current
    if (!surface) return
    const context = surface.getContext('2d')
    if (!context) return
    let width = 1
    let height = 1
    let frame = 0
    let previousTime = 0
    // Deterministic positions avoid a visual jump when reduced-motion changes.
    const particles = Array.from({ length: 46 }, (_, index) => ({
      x: ((index * 137.508 + 31) % 997) / 997,
      y: ((index * 79.731 + 71) % 661) / 661,
      vx: Math.sin(index * 4.3) * 0.000003,
      vy: -0.000002 - (index % 4) * 0.0000007,
    }))

    const draw = (time: number) => {
      const delta = previousTime ? Math.min(time - previousTime, 40) : 0
      previousTime = time
      context.clearRect(0, 0, width, height)
      for (let index = 0; index < particles.length; index++) {
        const particle = particles[index]
        if (!limitMotion) {
          particle.x = (particle.x + particle.vx * delta + 1) % 1
          particle.y = (particle.y + particle.vy * delta + 1) % 1
        }
        const x = particle.x * width
        const y = particle.y * height
        context.fillStyle = index % 4 === 0 ? 'rgba(85, 207, 235, .32)' : 'rgba(85, 207, 235, .14)'
        context.fillRect(x, y, index % 4 === 0 ? 1.5 : 1, index % 4 === 0 ? 1.5 : 1)
        for (let next = index + 1; next < particles.length; next++) {
          const other = particles[next]
          const distance = Math.hypot((particle.x - other.x) * width, (particle.y - other.y) * height)
          if (distance > 120) continue
          context.beginPath()
          context.strokeStyle = `rgba(64, 175, 208, ${(1 - distance / 120) * 0.09})`
          context.lineWidth = .6
          context.moveTo(x, y)
          context.lineTo(other.x * width, other.y * height)
          context.stroke()
        }
      }
      if (!limitMotion && !document.hidden) frame = requestAnimationFrame(draw)
    }
    const resize = () => {
      const rect = surface.getBoundingClientRect()
      width = Math.max(1, rect.width)
      height = Math.max(1, rect.height)
      const dpr = Math.min(window.devicePixelRatio || 1, 2)
      surface.width = Math.round(width * dpr)
      surface.height = Math.round(height * dpr)
      context.setTransform(dpr, 0, 0, dpr, 0, 0)
      if (limitMotion) draw(0)
    }
    const onVisibility = () => {
      cancelAnimationFrame(frame)
      previousTime = 0
      if (!document.hidden) draw(performance.now())
    }
    const observer = new ResizeObserver(resize)
    observer.observe(surface)
    resize()
    onVisibility()
    document.addEventListener('visibilitychange', onVisibility)
    return () => {
      cancelAnimationFrame(frame)
      observer.disconnect()
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [limitMotion])

  return <canvas ref={canvas} className="background-particles" aria-hidden="true" />
}

export default ParticleField
