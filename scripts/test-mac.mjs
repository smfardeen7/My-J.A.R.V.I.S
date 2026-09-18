import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync } from 'node:fs'
import { join, resolve } from 'node:path'
const root=resolve(import.meta.dirname,'..')
const developer='/Library/Developer/CommandLineTools'
const sdk=existsSync(join(developer,'SDKs/MacOSX15.4.sdk'))?join(developer,'SDKs/MacOSX15.4.sdk'):join(developer,'SDKs/MacOSX.sdk')
const output=join(root,'.native-test-build')
mkdirSync(output,{recursive:true})
const executable=join(output,'command-tests')
const env={...process.env,DEVELOPER_DIR:developer}
execFileSync(join(developer,'usr/bin/swiftc'),['-swift-version','5','-sdk',sdk,'-target',`${process.arch==='arm64'?'arm64':'x86_64'}-apple-macosx14.0`,'-module-cache-path','/private/tmp/jarvis-swift-module-cache',...['MacCommands.swift','OllamaClient.swift','tests/CommandTests.swift'].map(file=>join(root,'native',file)),'-o',executable],{stdio:'inherit',env})
execFileSync(executable,[],{stdio:'inherit',env})
const ownerTests=join(output,'owner-tests')
execFileSync(join(developer,'usr/bin/swiftc'),['-swift-version','5','-sdk',sdk,'-module-cache-path','/private/tmp/jarvis-swift-module-cache',...['SpeakerProfile.swift','tests/OwnerVoiceTests.swift'].map(file=>join(root,'native',file)),'-o',ownerTests],{stdio:'inherit',env})
execFileSync(ownerTests,[],{stdio:'inherit',env})
const voiceTests=join(output,'voice-tests')
execFileSync(join(developer,'usr/bin/swiftc'),['-swift-version','5','-sdk',sdk,'-module-cache-path','/private/tmp/jarvis-swift-module-cache',...['VoiceService.swift','tests/VoiceTests.swift'].map(file=>join(root,'native',file)),'-o',voiceTests],{stdio:'inherit',env})
execFileSync(voiceTests,[],{stdio:'inherit',env})
const authTests=join(output,'owner-auth-tests')
execFileSync(join(developer,'usr/bin/swiftc'),['-swift-version','5','-sdk',sdk,'-module-cache-path','/private/tmp/jarvis-swift-module-cache',...['OwnerAuthenticator.swift','tests/OwnerAuthTests.swift'].map(file=>join(root,'native',file)),'-o',authTests],{stdio:'inherit',env})
execFileSync(authTests,[],{stdio:'inherit',env})
