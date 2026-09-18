import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, copyFileSync, cpSync } from 'node:fs'
import { join, resolve } from 'node:path'

const root=resolve(import.meta.dirname,'..')
const developer='/Library/Developer/CommandLineTools'
const swift=join(developer,'usr/bin/swiftc')
const sdk=existsSync(join(developer,'SDKs/MacOSX15.4.sdk')) ? join(developer,'SDKs/MacOSX15.4.sdk') : join(developer,'SDKs/MacOSX.sdk')
if(process.platform!=='darwin') throw new Error('The Mac app must be built on macOS.')
if(!existsSync(swift)) throw new Error('Apple Command Line Tools are needed. Install with xcode-select --install.')
if(!existsSync(join(root,'dist/index.html'))) throw new Error('Build the React interface first: npm run build')
const app=join(root,'build/JARVIS.app')
const resources=join(app,'Contents/Resources')
mkdirSync(join(app,'Contents/MacOS'),{recursive:true})
mkdirSync(resources,{recursive:true})
copyFileSync(join(root,'native/Info.plist'),join(app,'Contents/Info.plist'))
cpSync(join(root,'dist'),join(resources,'web'),{recursive:true})
copyFileSync(join(root,'scripts/speaker-worker.py'),join(resources,'speaker-worker.py'))
const env={...process.env,DEVELOPER_DIR:developer}
const flags=['-swift-version','5','-sdk',sdk,'-target',`${process.arch==='arm64'?'arm64':'x86_64'}-apple-macosx14.0`,'-module-cache-path','/private/tmp/jarvis-swift-module-cache']
console.log('Compiling J.A.R.V.I.S. for macOS…')
execFileSync(swift,[...flags,'-O',...['main.swift','VoiceService.swift','MacCommands.swift','OllamaClient.swift','SpeakerProfile.swift','OwnerVoiceService.swift','OwnerAuthenticator.swift'].map(file=>join(root,'native',file)),'-o',join(app,'Contents/MacOS/JARVIS')],{stdio:'inherit',env})
const iconTool=join(root,'build/make-icon')
execFileSync(swift,[...flags,join(root,'native/Icon.swift'),'-o',iconTool],{stdio:'inherit',env})
const iconset=join(root,'build/JarvisIcon.iconset')
execFileSync(iconTool,[iconset],{stdio:'inherit',env})
execFileSync('/usr/bin/iconutil',['-c','icns',iconset,'-o',join(resources,'JarvisIcon.icns')],{stdio:'inherit',env})
execFileSync('/usr/bin/codesign',['--force','--sign','-','--options','runtime','--entitlements',join(root,'native/entitlements.plist'),app],{stdio:'inherit',env})
execFileSync('/usr/bin/codesign',['--verify','--strict',app],{stdio:'inherit',env})
console.log(`Built and signed ${app}`)
