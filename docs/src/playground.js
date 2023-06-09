// @ts-check

/**
 * @param {any} cond
 * @param {string=} msg
 * @returns {asserts cond}
 */
function assert(cond, msg) {
  if (!cond) {
    doAlert(Error(msg || 'assertion failed'))
  }
}

/** @param {any[]} objs */
function doAlert(...objs) {
  alert(objs
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
  const stderr = wasi.getStderrString()
  if (nativeCallResult === 0)
    return
  const err = Error(`got failure code ${nativeCallResult} in native call`)
  doAlert(err, stderr)
  debugger
  throw err;
}

const defaultProgram = `\
(display
  (transform
    ; the query selection
    ((function_definition body: (_) @body))

    ; the replacement of that selection
    (string-append (ast->string (@body)) (comment "// end of body"))

    ; the workspace in which to run the query (the file on the right)
    playground-workspace))
`

const defaultTarget = `\
#include <iostream>

template<int(*F)(void)>
int g() {
  return F();
}

extern int(*external_f)(void);

extern auto blah = [](){return 2;};

int main() {
  external_f = [](){return 5;};
  std::cout << g<blah>() << std::endl;
  return 0;
}
`

let sessionProgram = sessionStorage.getItem('program')
sessionProgram = sessionProgram && sessionProgram.trim() !== '' ? sessionProgram : defaultProgram

let sessionTarget = sessionStorage.getItem('target')
const targetInSessionStorageIsValid = sessionTarget && sessionTarget.trim() !== ''
sessionTarget = targetInSessionStorageIsValid ? sessionTarget : defaultTarget

let sessionTargetType = sessionStorage.getItem('target-type')
sessionTargetType = targetInSessionStorageIsValid ? sessionTargetType : 'cpp'

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


/** @type {{[lang: string]: Promise<any>}} */
const languages = {}

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
  const files = await fetch("./filesystem.json").then(r => r.json());

  /**
   * Like `mkdir -p`
   * @param {string} dir
   */
  function mkdirp(dir) {
    assert(dir.startsWith("/"), "dir must be absolute")
    const segments = dir.split('/')
    for (let i = 2; i < segments.length + 1; ++i) {
      // TODO: cache and avoid extra createDir?
      fs.createDir("/" + segments.slice(1, i).join('/'))
    }
  }

  const isLocalHost = window.location.hostname === "localhost";

  await Promise.all(
    Object.entries(files)
      // need to check base url since my repo redirects to a subpath of my main site
      .map(([f, dir]) => fetch(!f.startsWith("http") && !isLocalHost ? `/tree-stitcher${f}` : f)
        .then(resp => resp.arrayBuffer())
        .then(buff => {
          const basename = f.split('/').pop()
          const destination = `${dir}/${basename}`
          mkdirp(dir)
          const file = fs.open(destination, { write: true, create: true })
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

  await loadFileSystem(wasi.fs)

  handleNativeError(inst.exports.init())

  wasi.setStdinString('(load "/playground/playground-prelude.scm")')
  handleNativeError(inst.exports.eval_stdin())
  // ignore initial output (e.g. warnings lol)
  console.log("prelude stdout:", wasi.getStdoutString())
  console.log("prelude stderr:", wasi.getStderrString())

  runButton.addEventListener('click', () => {
    const program = programEditor.value
    const targetFile = wasi.fs.open('/target.txt', {read: true, write: true, create: true})
    targetFile.setLength(BigInt(0));
    targetFile.writeString(targetEditor.value);
    targetFile.seek(0);
    targetFile.free();

    wasi.setStdinString(program)
    handleNativeError(inst.exports.eval_stdin())
    output.textContent = wasi.getStdoutString() + '\n'
  })

  langSelect.addEventListener('change', async (e) => {
    const langTag = e.currentTarget.value
    if (!langTag) return
    sessionStorage.setItem('target-type', langTag)
    inst.exports[`load_${langTag}`]()
    // TODO: runtime code loading
    // this could help: https://radu-matei.com/blog/adding-wasi-syscall/
  })

  // force rerun listener to load
  const loadInitLangEvent = new Event('change')
  langSelect.dispatchEvent(loadInitLangEvent)
}

main().catch((err) => { doAlert(err, wasi && wasi.getStderrString()); throw err })

