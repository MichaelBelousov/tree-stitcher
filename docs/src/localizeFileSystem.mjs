import fs from "fs";
import path from "path";
import assert from "assert";
import JSON5 from "json5";

const __dirname = path.dirname(import.meta.url.slice("file://".length));

/**
 * @param {string} targetDir
 */
async function writeFileSystem(targetDir) {
  const jsonPath = path.join(__dirname, "./filesystem.json");
  const filesystem = JSON5.parse(await fs.promises.readFile(jsonPath, "utf8"));

  try {
    await fs.promises.mkdir(targetDir, { recursive: true })
  } catch (err) {
    if (err.type !== "EEXISTS") throw err;
  }
  await Promise.all(Object.entries(filesystem).map(async ([src, dir]) => {
    const destinationDir = path.join(targetDir, dir)
    const filename = path.basename(src);
    try {
      await fs.promises.mkdir(destinationDir, { recursive: true })
    } catch (err) {
      if (err.type !== "EEXISTS") throw err;
    }
    const srcFile = path.join(
      __dirname,
      "../..",
      src.startsWith("http")
      ? path.join("thirdparty/chibi-scheme", src.split("/wasm-lib/")[1])
      : src
    );
    const destination = path.join(destinationDir, filename);
    await fs.promises.copyFile(srcFile, destination);
  }));
}

const targetDir = process.argv[2];
assert(targetDir);
writeFileSystem(targetDir);
