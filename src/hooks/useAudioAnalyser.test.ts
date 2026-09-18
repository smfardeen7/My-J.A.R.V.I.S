// @vitest-environment jsdom
import { act, cleanup, renderHook } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useAudioAnalyser } from './useAudioAnalyser'

function makeStream() {
  const track = { stop: vi.fn(), addEventListener: vi.fn(), removeEventListener: vi.fn() }
  return { stream: { getTracks: () => [track] } as unknown as MediaStream, track }
}

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (reason: unknown) => void
  const promise = new Promise<T>((accept, decline) => { resolve = accept; reject = decline })
  return { promise, resolve, reject }
}

describe('useAudioAnalyser', () => {
  const getUserMedia = vi.fn<() => Promise<MediaStream>>()
  const nodes: FakeAudioContext[] = []

  class FakeAudioContext {
    state = 'running'
    analyser = { fftSize: 0, smoothingTimeConstant: 0 }
    source = { connect: vi.fn(), disconnect: vi.fn() }
    destination = { name: 'speakers' }
    close = vi.fn(async () => { this.state = 'closed' })
    resume = vi.fn(async () => { this.state = 'running' })
    createAnalyser = () => this.analyser
    createMediaStreamSource = () => this.source
    constructor() { nodes.push(this) }
  }

  beforeEach(() => {
    nodes.length = 0
    getUserMedia.mockReset()
    vi.stubGlobal('AudioContext', FakeAudioContext)
    vi.stubGlobal('navigator', { mediaDevices: { getUserMedia } })
  })

  afterEach(() => {
    cleanup()
    vi.unstubAllGlobals()
  })

  it('requests the microphone only on start and connects input only to an analyser', async () => {
    const { stream, track } = makeStream()
    getUserMedia.mockResolvedValue(stream)
    const { result } = renderHook(() => useAudioAnalyser())
    expect(getUserMedia).not.toHaveBeenCalled()
    expect(result.current.isActive).toBe(false)

    await act(async () => expect(await result.current.start()).toBe(true))

    expect(result.current.isActive).toBe(true)
    expect(result.current.analyser).toBe(nodes[0].analyser)
    expect(nodes[0].source.connect).toHaveBeenCalledExactlyOnceWith(nodes[0].analyser)
    act(() => result.current.stop())
    expect(track.stop).toHaveBeenCalledOnce()
    expect(nodes[0].close).toHaveBeenCalledOnce()
    expect(result.current.analyser).toBeNull()
    expect(result.current.isActive).toBe(false)
  })

  it('immediately releases a permission result that arrives after stop', async () => {
    const request = deferred<MediaStream>()
    const { stream, track } = makeStream()
    getUserMedia.mockReturnValue(request.promise)
    const { result } = renderHook(() => useAudioAnalyser())
    let started!: Promise<boolean>
    act(() => { started = result.current.start() })
    expect(result.current.isStarting).toBe(true)
    act(() => result.current.stop())
    await act(async () => { request.resolve(stream); expect(await started).toBe(false) })
    expect(track.stop).toHaveBeenCalledOnce()
    expect(result.current.isActive).toBe(false)
    expect(result.current.isStarting).toBe(false)
    expect(nodes).toHaveLength(0)
  })

  it('deduplicates start calls while browser permission is pending', async () => {
    const request = deferred<MediaStream>()
    getUserMedia.mockReturnValue(request.promise)
    const { result } = renderHook(() => useAudioAnalyser())
    let first!: Promise<boolean>
    let second!: Promise<boolean>
    act(() => { first = result.current.start(); second = result.current.start() })
    expect(getUserMedia).toHaveBeenCalledOnce()
    await act(async () => {
      request.resolve(makeStream().stream)
      expect(await first).toBe(true)
      expect(await second).toBe(true)
    })
    expect(nodes).toHaveLength(1)
  })

  it('releases the microphone and audio context when unmounted', async () => {
    const { stream, track } = makeStream()
    getUserMedia.mockResolvedValue(stream)
    const { result, unmount } = renderHook(() => useAudioAnalyser())
    await act(async () => { await result.current.start() })
    unmount()
    expect(track.stop).toHaveBeenCalledOnce()
    expect(nodes[0].close).toHaveBeenCalledOnce()
  })

  it('disposes a stream if permission arrives after unmount', async () => {
    const request = deferred<MediaStream>()
    const { stream, track } = makeStream()
    getUserMedia.mockReturnValue(request.promise)
    const { result, unmount } = renderHook(() => useAudioAnalyser())
    let started!: Promise<boolean>
    act(() => { started = result.current.start() })
    unmount()
    request.resolve(stream)
    expect(await started).toBe(false)
    expect(track.stop).toHaveBeenCalledOnce()
    expect(nodes).toHaveLength(0)
  })

  it('reports denied permission and allows a later retry', async () => {
    getUserMedia.mockRejectedValueOnce(new DOMException('Denied', 'NotAllowedError'))
    const { result } = renderHook(() => useAudioAnalyser())
    await act(async () => expect(await result.current.start()).toBe(false))
    expect(result.current.error).toMatch(/permission/i)
    expect(result.current.isStarting).toBe(false)
    expect(result.current.isActive).toBe(false)
    getUserMedia.mockResolvedValue(makeStream().stream)
    await act(async () => expect(await result.current.start()).toBe(true))
    expect(result.current.error).toBeNull()
  })

  it('clears a permission error when stopped while the microphone is inactive', async () => {
    getUserMedia.mockRejectedValueOnce(new DOMException('Denied', 'NotAllowedError'))
    const { result } = renderHook(() => useAudioAnalyser())
    await act(async () => { await result.current.start() })
    expect(result.current.error).toMatch(/permission/i)
    expect(result.current.isActive).toBe(false)

    act(() => result.current.stop())

    expect(result.current.error).toBeNull()
    expect(result.current.isActive).toBe(false)
    expect(result.current.isStarting).toBe(false)
  })

  it('reports unsupported browsers without opening the microphone', async () => {
    vi.stubGlobal('AudioContext', undefined)
    const { result } = renderHook(() => useAudioAnalyser())
    await act(async () => expect(await result.current.start()).toBe(false))
    expect(result.current.error).toMatch(/support/i)
    expect(getUserMedia).not.toHaveBeenCalled()
  })

  it('keeps the new session active when an older permission request resolves late', async () => {
    const oldRequest = deferred<MediaStream>()
    const oldStream = makeStream()
    const newStream = makeStream()
    getUserMedia.mockReturnValueOnce(oldRequest.promise).mockResolvedValueOnce(newStream.stream)
    const { result } = renderHook(() => useAudioAnalyser())
    let first!: Promise<boolean>
    act(() => { first = result.current.start() })
    act(() => result.current.stop())
    await act(async () => expect(await result.current.start()).toBe(true))
    const currentAnalyser = result.current.analyser
    await act(async () => {
      oldRequest.resolve(oldStream.stream)
      expect(await first).toBe(false)
    })
    expect(oldStream.track.stop).toHaveBeenCalledOnce()
    expect(newStream.track.stop).not.toHaveBeenCalled()
    expect(result.current.analyser).toBe(currentAnalyser)
    expect(result.current.isActive).toBe(true)
  })
})
