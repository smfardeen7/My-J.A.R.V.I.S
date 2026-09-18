// Install a local-only, isolated voice runtime for this Apple Silicon Mac.
// Downloads are fixed release artifacts and must match their pinned SHA-256.
import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { chmodSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { basename, join, resolve } from 'node:path'

process.umask(0o077)
const root = resolve(import.meta.dirname, '..')
const runtime = join(homedir(), 'Library/Application Support/JARVIS/voice-runtime')
const cache = join(root, 'build/speaker-downloads')
const modelID = '3dspeaker_speech_campplus_sv_zh_en_16k-common_advanced'
const artifacts = [
  {
    name: 'sherpa_onnx-1.13.8-cp311-cp311-macosx_11_0_arm64.whl',
    url: 'https://files.pythonhosted.org/packages/a9/74/dafb3c1c1ff82fc00abd098ade44811e48f3af88b4e3c2f1628567d0e80b/sherpa_onnx-1.13.8-cp311-cp311-macosx_11_0_arm64.whl',
    sha256: '8bb2b86ce44b5c5bb9949977177ddc36954c51097f81284d5ac48588e821ec07',
  },
  {
    name: 'sherpa_onnx_core-1.13.8-py3-none-macosx_11_0_arm64.whl',
    url: 'https://files.pythonhosted.org/packages/8c/2a/2a47b423fe009bbbcb6d7eed7bcba755d6f9ae923b5664c7208128c32d06/sherpa_onnx_core-1.13.8-py3-none-macosx_11_0_arm64.whl',
    sha256: '9312bbd46c93e31cecd3abda9cc8e71881d86cc3da3c35c7445ab04025b9fc3e',
  },
  {
    name: 'numpy-2.2.6-cp311-cp311-macosx_11_0_arm64.whl',
    url: 'https://files.pythonhosted.org/packages/b3/2b/64e1affc7972decb74c9e29e5649fac940514910960ba25cd9af4488b66c/numpy-2.2.6-cp311-cp311-macosx_11_0_arm64.whl',
    sha256: 'c820a93b0255bc360f53eca31a0e676fd1101f673dda8da93454a12e23fc5f7a',
  },
  {
    name: `${modelID}.onnx`,
    url: `https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/${modelID}.onnx`,
    sha256: 'aa3cfc16963a10586a9393f5035d6d6b57e98d358b347f80c2a30bf4f00ceba2',
  },
  {
    name: 'silero_vad.onnx',
    url: 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/silero_vad.onnx',
    sha256: '9e2449e1087496d8d4caba907f23e0bd3f78d91fa552479bb9c23ac09cbb1fd6',
  },
]
const digest = bytes => createHash('sha256').update(bytes).digest('hex')
const checked = (path, checksum) => existsSync(path) && digest(readFileSync(path)) === checksum

async function download(artifact) {
  const target = join(cache, artifact.name)
  if (checked(target, artifact.sha256)) return target
  console.log(`Downloading ${artifact.name}…`)
  const response = await fetch(artifact.url, { signal: AbortSignal.timeout(180_000) })
  if (!response.ok) throw new Error(`Download failed: ${basename(artifact.name)} (${response.status})`)
  const bytes = Buffer.from(await response.arrayBuffer())
  if (digest(bytes) !== artifact.sha256) throw new Error(`Checksum mismatch: ${artifact.name}. Nothing was installed from this file.`)
  writeFileSync(`${target}.partial`, bytes, { mode: 0o600 })
  renameSync(`${target}.partial`, target)
  return target
}

if (process.platform !== 'darwin' || process.arch !== 'arm64') {
  throw new Error('This pinned runtime targets macOS on Apple Silicon.')
}
const candidates = [process.env.JARVIS_PYTHON, '/Library/Frameworks/Python.framework/Versions/3.11/bin/python3', '/opt/homebrew/bin/python3.11'].filter(Boolean)
const python = candidates.find(path => {
  if (!existsSync(path)) return false
  try {
    return execFileSync(path, ['-I', '-c', 'import platform,sys; print(f"{sys.version_info.major}.{sys.version_info.minor} {platform.machine()}")'], { encoding: 'utf8' }).trim() === '3.11 arm64'
  } catch { return false }
})
if (!python) throw new Error('Python 3.11 for Apple Silicon is needed. Install it from python.org or set JARVIS_PYTHON to its executable.')
mkdirSync(cache, { recursive: true, mode: 0o700 })
mkdirSync(runtime, { recursive: true, mode: 0o700 })
chmodSync(runtime, 0o700)
mkdirSync(join(runtime, 'models'), { recursive: true, mode: 0o700 })

// Download and verify everything before installing packages or replacing models.
const files = []
for (const artifact of artifacts) files.push(await download(artifact))
const venv = join(runtime, 'venv')
const runtimePython = join(venv, 'bin/python3')
if (!existsSync(runtimePython)) execFileSync(python, ['-I', '-m', 'venv', venv], { stdio: 'inherit' })
const env = { ...process.env, PYTHONNOUSERSITE: '1', PIP_CONFIG_FILE: '/dev/null', PIP_DISABLE_PIP_VERSION_CHECK: '1' }
// No package-index access or dependency resolution: every wheel is pinned above.
execFileSync(runtimePython, ['-I', '-m', 'pip', 'install', '--isolated', '--no-index', '--no-deps', ...files.filter(file => file.endsWith('.whl'))], { stdio: 'inherit', env })
for (const artifact of artifacts.filter(item => item.name.endsWith('.onnx'))) {
  const target = join(runtime, 'models', artifact.name)
  if (!checked(target, artifact.sha256)) {
    writeFileSync(`${target}.partial`, readFileSync(join(cache, artifact.name)), { mode: 0o600 })
    renameSync(`${target}.partial`, target)
  }
}
execFileSync(runtimePython, ['-I', '-c', 'import numpy,sherpa_onnx; assert numpy.__version__ == "2.2.6"; assert sherpa_onnx.__version__ == "1.13.8"; print("Local speaker runtime imports verified.")'], { stdio: 'inherit', env })
writeFileSync(join(runtime, 'manifest.json'), JSON.stringify({ model_id: modelID, python: runtimePython, artifacts }, null, 2) + '\n', { mode: 0o600 })
console.log(`Voice runtime ready: ${runtime}`)
