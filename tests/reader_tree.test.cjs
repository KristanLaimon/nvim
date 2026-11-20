const assert = require("node:assert/strict");
const fs = require("node:fs");
const vm = require("node:vm");

class Element {
  constructor(tag) { this.tag = tag; this.children = []; this.dataset = {}; this.listeners = {}; this.open = false; }
  append(child) { this.children.push(child); }
  replaceChildren() { this.children = []; }
  addEventListener(event, handler) { this.listeners[event] = handler; }
}
const files = new Element("nav");
const filter = { value: "" };
const source = fs.readFileSync("tools/fox-reader/reader.js", "utf8");
const treeFunction = source.slice(source.indexOf("function renderFiles()"), source.indexOf("async function openDocument"));
const context = {
  files, current: "", allFiles: ["zeta.md", "README.md", "docs/z.txt", "docs/Guía uno.md", "docs/nested/test.txt", "A folder/start.md", "docs/alpha/one.md"],
  expandedFolders: new Set(), URL, encodeURIComponent,
  document: { querySelector: () => filter, createElement: tag => new Element(tag) },
  openDocument: () => {},
};
vm.runInNewContext(treeFunction + "\nrenderFiles();", context);
assert.deepEqual(files.children.map(child => child.tag === "details" ? child.children[0].textContent : child.textContent), ["A folder", "docs", "README.md", "zeta.md"]);
const docs = files.children.find(child => child.tag === "details" && child.children[0].textContent === "docs");
assert.deepEqual(docs.children.map(child => child.tag === "details" ? child.children[0].textContent : child.textContent), ["docs", "alpha", "nested", "Guía uno.md", "z.txt"]);
docs.open = true;
docs.listeners.toggle();
vm.runInNewContext("renderFiles()", context);
assert.equal(files.children.find(child => child.tag === "details" && child.children[0].textContent === "docs").open, true);
filter.value = "test";
vm.runInNewContext("renderFiles()", context);
assert.equal(files.children.length, 1);
assert.equal(files.children[0].children[1].children[1].textContent, "test.txt");
console.log("Reader tree checks passed");
