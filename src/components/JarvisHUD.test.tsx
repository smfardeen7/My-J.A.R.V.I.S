// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { JarvisHUD } from './JarvisHUD'
vi.mock('./JarvisOrb',()=>({JarvisOrb:()=>null}))
vi.mock('./ParticleField',()=>({ParticleField:()=>null}))
afterEach(cleanup)
describe('native HUD integration',()=>{
  it('makes hidden command panels inert so their actions cannot receive focus',()=>{
    render(<JarvisHUD reducedMotion mode="desktop" sidebarContent={<button>Open Safari</button>}/> )
    fireEvent.click(screen.getByRole('button',{name:'Interface settings'}))
    fireEvent.click(screen.getByRole('checkbox',{name:/Telemetry panels/}))
    const sidebar=screen.getByText('Open Safari').closest('aside')!
    expect(sidebar.hasAttribute('inert')).toBe(true)
    expect(sidebar.getAttribute('aria-hidden')).toBe('true')
  })
  it('preserves a microphone accessible name and disables missing stop callbacks',()=>{
    render(<JarvisHUD reducedMotion microphoneActive/> )
    expect(screen.getByRole('button',{name:'Stop listening'}).hasAttribute('disabled')).toBe(true)
  })
  it('offers cancellation during microphone setup and omits synthetic state previews',()=>{
    const onCancel=vi.fn()
    render(<JarvisHUD mode="desktop" reducedMotion microphoneStarting onCancel={onCancel}/> )
    fireEvent.click(screen.getByRole('button',{name:'Stop'}))
    expect(onCancel).toHaveBeenCalledOnce()
    expect(screen.queryByRole('button',{name:'Thinking'})).toBeNull()
  })
})
