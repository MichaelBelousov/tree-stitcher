// @ts-check

/**
 * @param {any} cond
 * @param {string=} msg
 * @returns {asserts cond}
 */
function assert(cond, msg) {
  if (!cond) {
    alert(Error(msg || 'assertion failed'))
  }
}

/** @param {any[]} objs */
function alert(...objs) {
  window.alert(objs
    .map(obj =>
      obj instanceof Error
      ? `${obj.constructor.name}: ${obj.message}\n${obj.stack}`
      : typeof obj === 'string'
      ? obj
      : 'object: ' + JSON.stringify(obj)
    )
    .join('\n'))
}

/** @param {number} nativeCallResult */
function handleNativeError(nativeCallResult) {
  if (nativeCallResult !== 0)
    alert(
      Error(`got failure code ${nativeCallResult} in native call`),
      wasi.getStderrString()
    )
}

const defaultProgram = `\
(transform
  ; the query
  ((function_definition body: (_) @body))

  ; the transform of that query
  (@body )

  ; the workspace in which to run the query
  (playground-workspace))
`

const defaultTarget = `\
def myfunc(a, b):
  return a + b
`

let sessionProgram = sessionStorage.getItem('program')
sessionProgram = sessionProgram && sessionProgram.trim() !== '' ? sessionProgram : defaultProgram

let sessionTarget = sessionStorage.getItem('target')
const targetInSessionStorageIsValid = sessionTarget && sessionTarget.trim() !== ''
sessionTarget = targetInSessionStorageIsValid ? sessionTarget : defaultTarget

let sessionTargetType = sessionStorage.getItem('target-type')
sessionTargetType = targetInSessionStorageIsValid ? sessionTargetType : 'python'

const programEditor = /** @type {HTMLTextAreaElement} */ (document.querySelector('#program-editor'))
programEditor.value = sessionProgram
programEditor.focus()

const targetEditor = /** @type {HTMLTextAreaElement} */ (document.querySelector('#target-editor'))
targetEditor.value = sessionTarget

const langSelect = /** @type {HTMLSelectElement} */ (document.querySelector('#lang-select'))
langSelect.value = sessionTargetType || 'python'

const output = /** @type {HTMLPreElement} */ (document.querySelector('#output'))
const runButton = /** @type {HTMLButtonElement} */ (document.querySelector('#run-btn'))
const defaultTargetButton = /** @type {HTMLButtonElement} */ (document.querySelector('#default-target-btn'))
const defaultProgramButton = /** @type {HTMLButtonElement} */ (document.querySelector('#default-program-btn'))

defaultTargetButton.addEventListener("click", () => targetEditor.value = defaultTarget)

defaultProgramButton.addEventListener("click", () => programEditor.value = defaultProgram)

targetEditor.addEventListener('change', (e) => {
  sessionTarget = e.currentTarget.value
  sessionStorage.setItem('target', sessionTarget)
})

programEditor.addEventListener('change', (e) => {
  sessionProgram = e.currentTarget.value
  sessionStorage.setItem('program', sessionProgram)
})

programEditor.addEventListener('keydown', (e) => {
  if (e.ctrlKey && e.key === 'Enter') {
    runButton.click()
  }
})


/** @type {typeof import('web-tree-sitter')} */
// @ts-ignore
const Parser = window.TreeSitter
assert(Parser, 'tree-sitter was not already loaded')

const parserInit = Parser.init({
  locateFile() {
    // NOTE: these url's are no where guaranteed to be stable, but something tells me it
    // won't break for a while, and then I can switch to a cdn
    return 'https://tree-sitter.github.io/tree-sitter.wasm'
  },
})

/** @type {{[lang: string]: Promise<any>}} */
const languages = {}

langSelect.addEventListener('change', async (e) => {
  const langTag = e.currentTarget.value
  sessionStorage.setItem('target-type', langTag)
  let langParser = languages[langTag]

  if (langParser === undefined) {
    await parserInit
    languages[langTag] = Parser.Language
      .load(`https://tree-sitter.github.io/tree-sitter-${langTag}.wasm`)
      .then((lang) => {
        // FIXME: do I need a parser? will find out
        const langParser = new Parser()
        langParser.setLanguage(lang)
        return langParser
      })
  }
})

// apparently their native esm bindings require a buffer polyfill
//import { Buffer } from 'https://cdn.jsdelivr.net/npm/buffer@6.0.3/+esm'
//window.Buffer = Buffer
import * as _wasmer from 'https://cdn.jsdelivr.net/npm/@wasmer/wasi@1.2.2/+esm'

/** @type {typeof import('@wasmer/wasi')} */
const wasmer = _wasmer

/** @type {import('@wasmer/wasi').WASI} */
let wasi

/**
 * @param {import('@wasmer/wasi').MemFS} fs
 */
async function loadFileSystem(fs) {
  const files = [
    "init-7.scm",
    "meta-7.scm",
  ]

  fs.createDir("/chibi")

  await Promise.all(
    files.map(f => fetch(`chibi-data/${f}`)
      .then(resp => resp.arrayBuffer())
      .then(buff => {
        // FIXME: support nested files by emulating mkdir -p
        const file = fs.open(`/chibi/${f}`, { write: true, create: true })
        file.write(new Uint8Array(buff))
      })
    )
  )
}

async function main() {
  const moduleBlob = fetch('webdriver.wasm')
  const [module] = await Promise.all([
    WebAssembly.compileStreaming(moduleBlob),
    wasmer.init(),
  ])

  wasi = new wasmer.WASI({
    env: {
      'CHIBI_MODULE_PATH': '/chibi'
    },
    args: [],
    preopens: {
      '/': '/',
    },
  })
  window._wasi = wasi

  const inst = wasi.instantiate(module, {})

  let targetFile = wasi.fs.open("/target.txt", {read: true, write: true, create: true})
  targetFile.writeString(targetEditor.value)
  await loadFileSystem(wasi.fs)

  handleNativeError(inst.exports.init())

  runButton.addEventListener('click', () => {
    const program = programEditor.value
    wasi.setStdinString(program)
    handleNativeError(inst.exports.eval_stdin())
    output.textContent = wasi.getStdoutString() + '\n'
  })
}

main().catch((err) => { alert(err, wasi.getStderrString()); throw err })

