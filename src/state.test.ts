import { describe, expect, it } from 'vitest'
import { jarvisStateReducer } from './state'
import type { JarvisState } from './types'

describe('jarvisStateReducer', () => {
  it('drives the complete interaction from idle back to idle', () => {
    let state: JarvisState = 'idle'
    state = jarvisStateReducer(state, { type: 'LISTEN' })
    expect(state).toBe('listening')
    state = jarvisStateReducer(state, { type: 'PROCESS' })
    expect(state).toBe('processing')
    state = jarvisStateReducer(state, { type: 'SPEAK' })
    expect(state).toBe('speaking')
    state = jarvisStateReducer(state, { type: 'COMPLETE' })
    expect(state).toBe('idle')
  })

  it.each<JarvisState>(['idle', 'listening', 'processing', 'speaking'])(
    'allows a reset from %s',
    (state) => expect(jarvisStateReducer(state, { type: 'RESET' })).toBe('idle'),
  )

  it('ignores events that skip a phase or repeat an earlier phase', () => {
    expect(jarvisStateReducer('idle', { type: 'SPEAK' })).toBe('idle')
    expect(jarvisStateReducer('idle', { type: 'PROCESS' })).toBe('idle')
    expect(jarvisStateReducer('listening', { type: 'COMPLETE' })).toBe('listening')
    expect(jarvisStateReducer('processing', { type: 'LISTEN' })).toBe('processing')
    expect(jarvisStateReducer('speaking', { type: 'PROCESS' })).toBe('speaking')
  })
})
