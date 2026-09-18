// @vitest-environment jsdom
import { cleanup, fireEvent, render, screen } from '@testing-library/react'
import { afterEach, expect, it, vi } from 'vitest'
import { OwnerVoicePanel } from './OwnerVoicePanel'
import type { OwnerVoiceStatus } from './bridge'
const owner: OwnerVoiceStatus={name:'Fardeen',enrolled:false,runtimeReady:true,enrolling:false,samples:0,phrase:'A sample phrase.',locale:''}
afterEach(()=>{cleanup();delete window.__JARVIS_DESKTOP__;delete window.webkit})
it('keeps setup disabled when the local speaker model is absent',()=>{
  render(<OwnerVoicePanel owner={{...owner,runtimeReady:false}} busy={false} recording={false}/> )
  expect((screen.getByRole('button',{name:'Set up my voice with Touch ID'}) as HTMLButtonElement).disabled).toBe(true)
  expect(screen.getByText(/Voice commands locked/)).toBeTruthy()
})
it('finishes a recording rather than opening an overlapping microphone session',()=>{
  const postMessage=vi.fn()
  window.__JARVIS_DESKTOP__=true;window.webkit={messageHandlers:{jarvis:{postMessage}}}
  render(<OwnerVoicePanel owner={{...owner,enrolling:true,samples:1}} busy recording/> )
  fireEvent.click(screen.getByRole('button',{name:'Finish sample'}))
  expect(postMessage).toHaveBeenCalledWith({action:'stopListening',payload:{}})
  expect(screen.getByText(/SAMPLE 2 OF 3/)).toBeTruthy()
})
it('disables recording while the preceding sample is being verified',()=>{
  render(<OwnerVoicePanel owner={{...owner,enrolling:true}} busy recording={false}/> )
  expect((screen.getByRole('button',{name:'Record sample 1'}) as HTMLButtonElement).disabled).toBe(true)
})
