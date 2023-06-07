// plenty of copying from:
// https://github.com/tree-sitter/tree-sitter/blob/be79158f7ed916190524348bebef252dcfe15d44/lib/binding_web/binding.js

const LANGUAGE_FUNCTION_REGEX = /^_?tree_sitter_\w+/;

export const LanguageLoader = {
  /**
   * @param {import('@wasmer/wasi').WASI} sizrModule
   * @param {string | Uint8Array} urlOrArray
   */
  async load(sizrModule, urlOrArray) {
    // TODO: check language version for compatibility with bundled tree-sitter,
    // too lazy to do it rn and tree-sitter hasn't been updated in a while
    const langWasmInst = await (
      typeof urlOrArray === "string"
        ? WebAssembly.compileStreaming(fetch(urlOrArray))
        : WebAssembly.compile(urlOrArray)
    )

    const symbolNames = Object.keys(langWasmInst)
    const functionName = symbolNames.find(key =>
      LANGUAGE_FUNCTION_REGEX.test(key) &&
      !key.includes("external_scanner_")
    )
    if (!functionName)
      throw Error("Couldn't find language function in WASM file."
        + `Symbols:\n${JSON.stringify(symbolNames, null, 2)}`)
    const languageAddress = langWasmInst[functionName]()
    sizrModule.exports.set_language(languageAddress);
  }
};
