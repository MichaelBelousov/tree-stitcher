// plenty of copying from:
// https://github.com/tree-sitter/tree-sitter/blob/be79158f7ed916190524348bebef252dcfe15d44/lib/binding_web/binding.js

const LANGUAGE_FUNCTION_REGEX = /^_?tree_sitter_\w+/;

export const LanguageLoader = {
  /**
   * @param {import('@wasmer/wasi').WASI} wasmer // FIXME: remove
   * @param {WebAssembly.Instance} sizrInst
   * @param {string} url
   */
  async load(wasi, sizrInst, url) {
    // TODO: check language version for compatibility with bundled tree-sitter,
    // too lazy to do it rn and tree-sitter hasn't been updated in a while
    /*
    const langWasmModule = await (
      typeof urlOrArray === "string"
        ? WebAssembly.compileStreaming(fetch(urlOrArray))
        : WebAssembly.compile(urlOrArray)
    )
    */

    const array = new Uint8Array(await fetch(url).then(r => {
      if (!r.ok)
        throw Error(`couldn't load: ${url}`)
      return r.arrayBuffer()
    }))

    const libName = url.split('/').pop()
    wasi.fs.createDir("/langs")
    const langPath = `/langs/${libName}`
    const libFile = window._wasi.fs.open(langPath, { write: true, create: true, read: true })
    libFile.write(array);

    // TODO: make bytes and move into memory
    const encoder = new TextEncoder();
    const pathBytes = encoder.encode(langPath)
    sizrInst.exports.loadAndSetLanguage(pathBytes)

    //const wasi = new wasmer.WASI({ env: {}, args: [], preopens: {}, })
    // must be loaded using emscripten generation code...
    /*
    const langInst = await WebAssembly.instantiate(langWasmModule, {
      env: {
        "test": new WebAssembly.Table({
          "element"
        })
      }
    });

    const exports = WebAssembly.Module.exports(langInst)
    const functionName = exports.find(export_ =>
      LANGUAGE_FUNCTION_REGEX.test(export_.name) &&
      !export_.name.includes("external_scanner_")
    )
    if (!functionName)
      throw Error("Couldn't find language function in WASM file."
        + `Symbols:\n${JSON.stringify(exports, null, 2)}`)
    const languageAddress = langInst.exports[functionName]()
    */
  }
};
