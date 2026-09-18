import { execFileSync } from 'node:child_process'
import { existsSync, mkdirSync, renameSync } from 'node:fs'
import { homedir } from 'node:os'
import { resolve,join } from 'node:path'
const source=resolve(import.meta.dirname,'../build/JARVIS.app')
const parent=join(homedir(),'Applications')
const destination=join(parent,'JARVIS.app')
if(!existsSync(source)) throw new Error('Build first with npm run mac:build.')
mkdirSync(parent,{recursive:true})
if(existsSync(destination)) {
 const backup=join(parent,`JARVIS.backup-${Date.now()}.app`)
 renameSync(destination,backup)
 console.log(`Previous app preserved at ${backup}`)
}
execFileSync('/usr/bin/ditto',[source,destination],{stdio:'inherit'})
execFileSync('/usr/bin/codesign',['--verify','--strict',destination],{stdio:'inherit'})
console.log(`Installed ${destination}`)
