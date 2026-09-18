// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { isDesktop, nativeCommand, onNativeEvent } from './bridge'

afterEach(()=>{delete window.__JARVIS_DESKTOP__;delete window.webkit})
describe('native bridge boundary',()=>{
  it('does not allow a browser-only page to call native commands',()=>{
    expect(isDesktop()).toBe(false)
    expect(()=>nativeCommand('command',{text:'Open Safari'})).toThrow('Mac app')
  })
  it('requires both injected native flag and message handler',()=>{
    const postMessage=vi.fn()
    window.webkit={messageHandlers:{jarvis:{postMessage}}}
    expect(isDesktop()).toBe(false)
    window.__JARVIS_DESKTOP__=true
    nativeCommand('command',{text:'What time is it?'})
    expect(postMessage).toHaveBeenCalledWith({action:'command',payload:{text:'What time is it?'}})
  })
  it('stops receiving native events when the controller unmounts',()=>{
    const handler=vi.fn()
    const unsubscribe=onNativeEvent(handler)
    const detail={type:'response',text:'Hello'}
    window.dispatchEvent(new CustomEvent('jarvis:native',{detail}))
    expect(handler).toHaveBeenCalledWith(detail)
    unsubscribe()
    window.dispatchEvent(new CustomEvent('jarvis:native',{detail}))
    expect(handler).toHaveBeenCalledTimes(1)
  })
})
