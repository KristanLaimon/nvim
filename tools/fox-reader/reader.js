"use strict";
const files = document.querySelector("#files");
const article = document.querySelector("#content");
const status = document.querySelector("#status");
let current = new URL(location.href).searchParams.get("path") || "";
let lastHtml = "";
let lastMetadata = "";
let navigation = 0;
let allFiles = [];
const expandedFolders = new Set();
const preferences = { theme: document.documentElement.dataset.theme || "editor", font: "Trebuchet MS", alignment: "justify", size: 18, lineSpacing: 1.8, width: 760, focus: false, vim: false };
const stateStatus = document.querySelector("#state-status");
let stateWrites = Promise.resolve();
let restoring = false;
let scrollTimer;
/** @returns {void} */
function applyReadingStyle() {
  document.documentElement.dataset.theme = preferences.theme;
  for (const name of ["font", "alignment", "size", "lineSpacing", "width"]) document.querySelector(`#${name}`).value = preferences[name];
  const font = document.querySelector("#font").value || "Trebuchet MS";
  const generic = ["system-ui", "serif", "sans-serif", "monospace"].includes(font);
  document.documentElement.style.setProperty("--reading-font", generic ? font : `"${font}"`);
  document.documentElement.style.setProperty("--reading-alignment", document.querySelector("#alignment").value || "justify");
  document.documentElement.style.setProperty("--reading-size", `${preferences.size}px`);
  document.documentElement.style.setProperty("--reading-spacing", preferences.lineSpacing);
  document.documentElement.style.setProperty("--reading-width", `${preferences.width}px`);
  document.body.classList.toggle("focus", preferences.focus);
  document.querySelector("#focus").setAttribute("aria-pressed", String(preferences.focus));
  document.querySelector("#vim-motion").setAttribute("aria-pressed", String(preferences.vim));
}
/** @param {object} value @returns {void} */
function saveState(value) {
  stateWrites = stateWrites.then(async () => {
    try {
      const response = await fetch("state", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(value), keepalive: true });
      if (!response.ok) throw new Error(await response.text());
      stateStatus.textContent = "";
    } catch (error) { stateStatus.textContent = "Reader state could not be saved: " + error; }
  });
}
/** @returns {HTMLElement | Window} */
function readingScroller() {
  const panes = document.querySelector("#panes");
  return panes.classList.contains("split-top") || panes.classList.contains("split-bottom") ? document.querySelector("#panes > main") : window;
}
/** @returns {number} */
function readingScrollTop() { const scroller = readingScroller(); return scroller === window ? window.scrollY : scroller.scrollTop; }
/** @returns {number} */
function readingViewportTop() { const scroller = readingScroller(); return scroller === window ? 0 : scroller.getBoundingClientRect().top; }
/** @param {number} top @returns {void} */
function scrollReadingTo(top) { readingScroller().scrollTo(0, top); }
/** @returns {void} */
function savePosition() {
  if (!current || restoring || !lastHtml) return;
  const headings = [...article.querySelectorAll("h1,h2,h3,h4,h5,h6")];
  const heading = headings.filter(item => item.getBoundingClientRect().top <= readingViewportTop()).pop();
  saveState({ kind: "position", path: current, value: { heading: heading?.id || "", offset: heading ? heading.getBoundingClientRect().top - readingViewportTop() : 0, scroll: readingScrollTop() } });
}
/** @param {string} path @returns {Promise<object>} */
async function loadState(path = "") {
  try {
    const response = await fetch("state" + (path ? "?path=" + encodeURIComponent(path) : ""), { cache: "no-store" });
    if (!response.ok) throw new Error("State is unavailable");
    const data = await response.json();
    if (data.warning) stateStatus.textContent = data.warning;
    return data;
  } catch (error) { stateStatus.textContent = "Reader state could not be loaded: " + error; return {}; }
}
applyReadingStyle();
/** @returns {Promise<void>} */
async function refreshTheme() {
  try {
    const response = await fetch("theme", { cache: "no-store" });
    if (!response.ok) return;
    const theme = await response.json();
    for (const name of ["background", "foreground", "muted"]) {
      document.documentElement.style.setProperty(`--editor-${name}`, theme[name]);
    }
    document.documentElement.style.setProperty("--editor-scheme", theme.dark ? "dark" : "light");
  } catch { /* The document refresh reports connection failures. */ }
}
mermaid.initialize({ startOnLoad: false, securityLevel: "strict" });
/** @returns {void} */
function renderFiles() {
  const query = document.querySelector("#filter").value.toLowerCase();
  files.replaceChildren();
  const folders = new Map([["", files]]);
  const matchingFiles = allFiles.filter(name => name.toLowerCase().includes(query))
    .sort((a, b) => a.localeCompare(b, undefined, { sensitivity: "base", numeric: true }));
  for (const path of matchingFiles) {
    const parts = path.split("/");
    parts.pop();
    let parent = "";
    for (const part of parts) {
      const folderPath = parent ? `${parent}/${part}` : part;
      if (!folders.has(folderPath)) {
        const folder = document.createElement("details");
        folder.dataset.path = folderPath;
        folder.open = query !== "" || expandedFolders.has(folderPath);
        folder.addEventListener("toggle", () => {
          if (document.querySelector("#filter").value !== "") return;
          if (folder.open) expandedFolders.add(folderPath);
          else expandedFolders.delete(folderPath);
        });
        const summary = document.createElement("summary");
        summary.textContent = part;
        folder.append(summary);
        folders.get(parent).append(folder);
        folders.set(folderPath, folder);
      }
      parent = folderPath;
    }
  }
  for (const path of matchingFiles) {
    const parts = path.split("/");
    const filename = parts.pop();
    const parent = parts.join("/");
    const link = document.createElement("a");
    link.href = "?path=" + encodeURIComponent(path);
    link.textContent = filename;
    link.dataset.extension = (filename.split(".").pop() || "").toLowerCase();
    if (path === current) link.setAttribute("aria-current", "page");
    link.onclick = event => {
      if (event.button !== 0 || event.metaKey || event.altKey) return;
      if (event.ctrlKey && event.shiftKey) {
        event.preventDefault();
        window.top.openReaderSplit(path, "right");
      } else if (!event.ctrlKey && !event.shiftKey) {
        event.preventDefault();
        openDocument(path);
      }
    };
    folders.get(parent).append(link);
  }
}
/**
 * @param {string} path
 * @param {boolean} push
 * @param {string} anchor
 * @returns {Promise<void>}
 */
async function openDocument(path, push = true, anchor = "") {
  clearTimeout(scrollTimer);
  savePosition();
  current = path;
  document.querySelector("#code-panel").hidden = true;
  document.querySelector("#reading-area").hidden = false;
  renderFiles();
  navigation++;
  const revision = navigation;
  restoring = true;
  lastHtml = "";
  lastMetadata = "";
  if (push) history.pushState({ path }, "", path ? "?path=" + encodeURIComponent(path) + anchor : location.pathname);
  if (!path) {
    article.replaceChildren();
    document.querySelector("#title").textContent = "Fox Reader";
    document.querySelector("#outline nav").replaceChildren();
    status.textContent = "Choose a document from the library.";
    restoring = false;
    return;
  }
  await stateWrites;
  const saved = await loadState(path);
  if (revision !== navigation) return;
  await refresh();
  if (revision !== navigation) return;
  if (anchor) {
    try { document.getElementById(decodeURIComponent(anchor.slice(1)))?.scrollIntoView(); }
    catch { status.textContent = "Invalid heading anchor"; }
  } else if (saved.position && typeof saved.position.scroll === "number") {
    const heading = saved.position.heading && document.getElementById(saved.position.heading);
    scrollReadingTo(heading && typeof saved.position.offset === "number"
      ? readingScrollTop() + heading.getBoundingClientRect().top - readingViewportTop() - saved.position.offset : saved.position.scroll);
  } else scrollReadingTo(0);
  restoring = false;
}
/** @returns {Promise<void>} */
async function refresh() {
  if (!current) return;
  const path = current;
  const revision = navigation;
  try {
    const result = await fetch("document?path=" + encodeURIComponent(path), { cache: "no-store" });
    if (!result.ok) throw new Error("Document is unavailable: " + path);
    const documentData = await result.json();
    if (revision !== navigation || documentData.path !== current) return;
    if (typeof documentData.code === "string") {
      await showScript(documentData, revision);
      return;
    }
    document.querySelector("#code-panel").hidden = true;
    document.querySelector("#reading-area").hidden = false;
    if (documentData.html !== lastHtml || (documentData.frontmatter || "") !== lastMetadata) {
      const headings = [...article.querySelectorAll("h1,h2,h3,h4,h5,h6")];
      const visible = headings.filter(heading => heading.getBoundingClientRect().top <= readingViewportTop()).pop();
      const anchorId = visible?.id;
      const offset = visible ? visible.getBoundingClientRect().top - readingViewportTop() : 0;
      const top = readingScrollTop();
      article.innerHTML = documentData.html;
      lastHtml = documentData.html;
      lastMetadata = documentData.frontmatter || "";
      if (lastMetadata) {
        const metadata = document.createElement("details");
        metadata.className = "metadata";
        metadata.open = true;
        const title = document.createElement("summary");
        title.textContent = "Properties";
        metadata.append(title);
        const fields = document.createElement("dl");
        let value;
        for (const line of lastMetadata.split("\n")) {
          const field = line.match(/^([^\s:#][^:]*):(?:\s+(.*)|\s*)$/);
          if (field) {
            const key = document.createElement("dt");
            key.textContent = field[1].trim();
            value = document.createElement("dd");
            value.textContent = field[2] || "";
            fields.append(key, value);
          } else {
            if (!value) {
              const key = document.createElement("dt");
              key.textContent = "YAML";
              value = document.createElement("dd");
              fields.append(key, value);
            }
            value.textContent += (value.textContent ? "\n" : "") + line;
          }
        }
        for (const field of fields.querySelectorAll("dd")) {
          const lines = field.textContent.split("\n");
          const blockItems = lines.map(line => line.match(/^\s+-\s+([^\n]+)$/));
          const inlineItems = field.textContent.match(/^\[([^\[\]"']*)\]$/);
          const items = blockItems.every(Boolean) ? blockItems.map(item => item[1])
            : inlineItems ? inlineItems[1].split(",").map(item => item.trim()).filter(Boolean) : [];
          if (items.length) {
            field.replaceChildren();
            for (const item of items) {
              const tag = document.createElement("span");
              tag.className = "metadata-item";
              tag.textContent = item;
              field.append(tag);
            }
          }
        }
        metadata.append(fields);
        article.prepend(metadata);
      }
      document.querySelector("#title").textContent = current;
      const base = new URL(current.split("/").map(encodeURIComponent).join("/"), "https://workspace.invalid/");
      for (const image of article.querySelectorAll("img[src]")) {
        try {
          const target = new URL(image.getAttribute("src"), base);
          if (target.origin === base.origin) image.src = "image?path=" + encodeURIComponent(decodeURIComponent(target.pathname.slice(1)));
          else if (target.protocol === "https:" || target.protocol === "http:") image.src = target.href;
          else image.removeAttribute("src");
        } catch { image.removeAttribute("src"); }
      }
      for (const link of article.querySelectorAll("a[href]")) {
        try {
          const target = new URL(link.getAttribute("href"), base);
          const local = target.origin === base.origin;
          const targetPath = local ? decodeURIComponent(target.pathname.slice(1)) : target.href;
          if (!local && !["http:", "https:"].includes(target.protocol)) continue;
          link.dataset.previewPath = targetPath;
          link.dataset.previewLocal = String(local);
          if (local) link.href = "?path=" + encodeURIComponent(targetPath) + target.hash;
          link.onclick = event => {
            if (event.button !== 0 || event.metaKey || event.altKey) return;
            if (event.ctrlKey && event.shiftKey) {
              event.preventDefault();
              window.top.openReaderSplit(targetPath, "right", local ? target.hash : "", !local);
            } else if (local && !event.ctrlKey && !event.shiftKey) {
              event.preventDefault();
              openDocument(targetPath, true, target.hash);
            }
          };
        } catch { link.removeAttribute("href"); }
      }
      const outline = document.querySelector("#outline nav");
      outline.replaceChildren();
      const headingIds = new Map();
      for (const heading of article.querySelectorAll("h1,h2,h3,h4,h5,h6")) {
        const slug = heading.textContent.trim().toLowerCase().replace(/[^\p{L}\p{N}_\- ]/gu, "").replace(/ /g, "-");
        const count = headingIds.get(slug) || 0;
        headingIds.set(slug, count + 1);
        heading.id = count ? `${slug}-${count}` : slug;
        const link = document.createElement("a");
        link.href = "#" + heading.id;
        link.textContent = heading.textContent;
        link.style.paddingLeft = `${0.5 + (Number(heading.tagName.slice(1)) - 1) * 0.85}rem`;
        outline.append(link);
      }
      await mermaid.run({ nodes: article.querySelectorAll(".mermaid") });
      if (revision !== navigation) return;
      const restored = anchorId && document.getElementById(anchorId);
      scrollReadingTo(restored ? readingScrollTop() + restored.getBoundingClientRect().top - readingViewportTop() - offset : top);
    }
    status.textContent = "";
  } catch (error) {
    if (revision !== navigation) return;
    lastHtml = "";
    lastMetadata = "";
    article.replaceChildren();
    document.querySelector("#outline nav").replaceChildren();
    document.querySelector("#title").textContent = path;
    status.textContent = String(error);
  }
}
/** @returns {Promise<void>} */
async function refreshLibrary() {
  try { allFiles = (await (await fetch("library", { cache: "no-store" })).json()).files; renderFiles(); }
  catch (error) { status.textContent = String(error); }
}
document.querySelector("#filter").oninput = renderFiles;
document.querySelector("#vim-motion").onclick = () => {
  if (window !== window.top) { window.top.document.querySelector("#vim-motion").click(); return; }
  preferences.vim = !preferences.vim;
  applyReadingStyle();
  if (preferences.vim) article.focus({ preventScroll: true });
  saveState({ kind: "preferences", value: { ...preferences } });
};
document.addEventListener("keydown", event => {
  if (window.top.document.querySelector("#vim-motion").getAttribute("aria-pressed") !== "true" || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || event.defaultPrevented) return;
  if (event.target instanceof Element && event.target.closest("input,textarea,select,button,[contenteditable=true],.monaco-editor,dialog")) return;
  if (["j", "k"].includes(event.key)) {
    event.preventDefault();
    readingScroller().scrollBy({ top: event.key === "j" ? 80 : -80 });
  } else if (["h", "l"].includes(event.key)) {
    const root = window.top.document;
    const split = root.querySelector("#split-pane");
    if (split.hidden) return;
    const splitLeft = root.querySelector("#panes").classList.contains("split-left");
    const chooseSplit = (event.key === "h") === splitLeft;
    event.preventDefault();
    if (chooseSplit) root.querySelector("#split-frame").contentWindow.focus();
    else root.querySelector("#content").focus();
  }
});
document.querySelector("#focus").onclick = () => {
  preferences.focus = !preferences.focus;
  applyReadingStyle();
  saveState({ kind: "preferences", value: { ...preferences } });
};
document.querySelector("#library-toggle").onclick = () => {
  const hidden = getComputedStyle(document.querySelector("#library")).display === "none";
  document.body.classList.toggle("library-hidden", !hidden);
  document.body.classList.toggle("show-library", hidden);
};
document.addEventListener("keydown", event => {
  if (event.ctrlKey && !event.shiftKey && !event.altKey && !event.metaKey && event.key.toLowerCase() === "w") {
    event.preventDefault();
    event.stopPropagation();
    if (activeRun) postScript("stop-run", { id: activeRun }).catch(error => { status.textContent = String(error); });
    if (window !== window.top) window.top.document.querySelector("#split-close").click();
    else openDocument("");
  } else if (event.ctrlKey && event.shiftKey && !event.altKey && !event.metaKey && event.code === "Space") {
    event.preventDefault();
    window.top.document.querySelector("#library-toggle").click();
  }
}, true);
document.querySelector("#theme").onclick = () => {
  const themes = ["editor", "paper", "light", "dark"];
  preferences.theme = themes[(themes.indexOf(document.documentElement.dataset.theme) + 1) % themes.length];
  document.documentElement.dataset.theme = preferences.theme;
  saveState({ kind: "preferences", value: { ...preferences } });
};
for (const control of document.querySelectorAll(".control")) {
  const button = control.querySelector("button");
  const panel = control.querySelector(".control-panel");
  button.onclick = () => {
    const opening = panel.hidden;
    for (const other of document.querySelectorAll(".control")) {
      other.querySelector(".control-panel").hidden = true;
      other.querySelector("button").setAttribute("aria-expanded", "false");
    }
    panel.hidden = !opening;
    button.setAttribute("aria-expanded", String(opening));
  };
}
document.addEventListener("click", event => {
  if (event.target.closest(".control")) return;
  for (const control of document.querySelectorAll(".control")) {
    control.querySelector(".control-panel").hidden = true;
    control.querySelector("button").setAttribute("aria-expanded", "false");
  }
});
document.addEventListener("keydown", event => {
  if (event.key !== "Escape") return;
  for (const control of document.querySelectorAll(".control")) {
    control.querySelector(".control-panel").hidden = true;
    control.querySelector("button").setAttribute("aria-expanded", "false");
  }
});
for (const setting of ["font", "alignment", "size", "lineSpacing", "width"]) {
  const input = document.querySelector(`#${setting}`);
  const update = event => {
    preferences[setting] = ["size", "lineSpacing", "width"].includes(setting) ? Number(event.target.value) : event.target.value;
    applyReadingStyle();
  };
  input.addEventListener("input", update);
  input.addEventListener("change", event => {
    update(event);
    saveState({ kind: "preferences", value: { ...preferences } });
  });
}
for (const [id, direction] of [["width-left", -1], ["width-right", 1]]) {
  const handle = document.querySelector(`#${id}`);
  handle.addEventListener("pointerdown", event => {
    if (event.button !== 0) return;
    event.preventDefault();
    const startX = event.clientX;
    const startWidth = document.querySelector("#reading-area").getBoundingClientRect().width;
    handle.setPointerCapture(event.pointerId);
    const move = movement => {
      preferences.width = Math.round(Math.min(1200, Math.max(400, startWidth + direction * (movement.clientX - startX) * 2)) / 20) * 20;
      applyReadingStyle();
    };
    const finish = () => {
      handle.removeEventListener("pointermove", move);
      handle.removeEventListener("pointerup", finish);
      handle.removeEventListener("pointercancel", finish);
      saveState({ kind: "preferences", value: { ...preferences } });
    };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", finish);
    handle.addEventListener("pointercancel", finish);
  });
}
/** @returns {void} */
function schedulePositionSave() {
  if (restoring) return;
  clearTimeout(scrollTimer);
  scrollTimer = setTimeout(savePosition, 500);
}
window.addEventListener("scroll", schedulePositionSave, { passive: true });
document.querySelector("#panes > main").addEventListener("scroll", schedulePositionSave, { passive: true });
window.addEventListener("pagehide", () => { clearTimeout(scrollTimer); savePosition(); });
window.onpopstate = () => openDocument(new URL(location.href).searchParams.get("path") || "", false, location.hash);
refreshLibrary();
refreshTheme();
loadState().then(data => {
  const saved = data.preferences;
  if (saved && typeof saved === "object") {
    for (const name of ["theme", "font", "alignment"]) {
      const options = name === "theme" ? ["editor", "paper", "light", "dark"] : [...document.querySelector(`#${name}`).options].map(option => option.value);
      if (options.includes(saved[name])) preferences[name] = saved[name];
    }
    for (const [name, min, max] of [["size", 14, 28], ["lineSpacing", 1, 2.5], ["width", 400, 1200]]) {
      if (typeof saved[name] === "number" && saved[name] >= min && saved[name] <= max) preferences[name] = saved[name];
    }
    if (typeof saved.focus === "boolean") preferences.focus = saved.focus;
    if (typeof saved.vim === "boolean") preferences.vim = saved.vim;
  }
  applyReadingStyle();
  if (current) openDocument(current, false, location.hash);
});
setInterval(refresh, 1000);
setInterval(refreshLibrary, 5000);
setInterval(refreshTheme, 1000);

/** @param {string} path @param {string} side @param {string} [anchor] @param {boolean} [external] @returns {void} */
window.openReaderSplit = (path, side, anchor = "", external = false) => {
  const previousScroll = readingScrollTop();
  const panes = document.querySelector("#panes");
  panes.classList.remove("split-left", "split-right", "split-top", "split-bottom");
  panes.classList.add(`split-${side}`);
  document.querySelector("#split-title").textContent = path;
  const frame = document.querySelector("#split-frame");
  if (external) frame.setAttribute("sandbox", ""); else frame.removeAttribute("sandbox");
  frame.src = external ? path : "?pane=1&path=" + encodeURIComponent(path) + anchor;
  document.querySelector("#split-pane").hidden = false;
  scrollReadingTo(previousScroll);
};
// A split is a separate reader so each document retains its own scroll position.
if (new URLSearchParams(location.search).has("pane")) document.body.classList.add("pane");
const searchDialog = document.querySelector("#file-search");
const searchInput = document.querySelector("#file-search-input");
const searchResults = document.querySelector("#file-search-results");
let searchSide = "";
/** @returns {void} */
function updateSearch() {
  const query = searchInput.value.toLowerCase().trim();
  searchResults.replaceChildren();
  for (const path of allFiles.filter(name => name.toLowerCase().includes(query)).slice(0, 100)) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = path;
    button.onclick = () => {
      searchDialog.close();
      if (!searchSide) { openDocument(path); return; }
      window.top.openReaderSplit(path, searchSide);
    };
    searchResults.append(button);
  }
}
searchInput.addEventListener("input", updateSearch);
searchInput.addEventListener("keydown", event => {
  if (event.key === "ArrowDown") { event.preventDefault(); searchResults.querySelector("button")?.focus(); }
  if (event.key === "Enter") { event.preventDefault(); searchResults.querySelector("button")?.click(); }
});
searchResults.addEventListener("keydown", event => {
  if (!["ArrowDown", "ArrowUp"].includes(event.key)) return;
  event.preventDefault();
  const buttons = [...searchResults.querySelectorAll("button")];
  const index = buttons.indexOf(document.activeElement) + (event.key === "ArrowDown" ? 1 : -1);
  if (index < 0) searchInput.focus(); else buttons[Math.min(index, buttons.length - 1)]?.focus();
});
document.addEventListener("keydown", event => {
  if (!event.ctrlKey || event.altKey || event.metaKey) return;
  const key = event.key.toLowerCase();
  if ((!event.shiftKey && key === "k") || (event.shiftKey && ["h", "j", "k", "l"].includes(key))) {
    event.preventDefault();
    searchSide = event.shiftKey ? ({ h: "left", j: "bottom", k: "top", l: "right" })[key] : "";
    if (!searchDialog.open) searchDialog.showModal();
    searchInput.value = "";
    updateSearch();
    searchInput.focus();
  }
});
document.querySelector("#split-close").onclick = () => {
  const previousScroll = readingScrollTop();
  document.querySelector("#split-pane").hidden = true;
  document.querySelector("#split-frame").removeAttribute("src");
  document.querySelector("#panes").classList.remove("split-left", "split-right", "split-top", "split-bottom");
  scrollReadingTo(previousScroll);
};
for (const [id, property, side] of [["library-resizer", "--library-width", 1], ["outline-resizer", "--outline-width", -1]]) {
  const handle = document.querySelector(`#${id}`);
  const resize = width => document.documentElement.style.setProperty(property, `${Math.max(140, Math.min(window.innerWidth * .45, width))}px`);
  handle.addEventListener("pointerdown", event => {
    if (event.button !== 0) return;
    event.preventDefault();
    const start = event.clientX;
    const width = handle.previousElementSibling?.id === "library" ? document.querySelector("#library").offsetWidth : document.querySelector("#outline").offsetWidth;
    handle.setPointerCapture(event.pointerId);
    const move = movement => resize(width + side * (movement.clientX - start));
    const finish = () => { handle.removeEventListener("pointermove", move); handle.removeEventListener("pointerup", finish); handle.removeEventListener("pointercancel", finish); };
    handle.addEventListener("pointermove", move);
    handle.addEventListener("pointerup", finish);
    handle.addEventListener("pointercancel", finish);
  });
  handle.addEventListener("keydown", event => {
    if (!["ArrowLeft", "ArrowRight"].includes(event.key)) return;
    event.preventDefault();
    const sidebar = document.querySelector(id === "library-resizer" ? "#library" : "#outline");
    resize(sidebar.offsetWidth + side * (event.key === "ArrowRight" ? 10 : -10));
  });
}

let scriptEditor;
let outputEditor;
let scriptPath = "";
let scriptCode = "";
let activeRun = "";
let runPath = "";
let runOutput = "";
let monacoReady;
const scriptDrafts = new Map();
let outputInput = "";
let updatingOutput = false;
let inputOpen = false;
let inputRevision = 0;
window.addEventListener("beforeunload", event => {
  if ([...scriptDrafts.values()].some(draft => draft.code !== draft.original)) event.preventDefault();
});
/** @returns {void} */
function renderOutput() {
  if (!outputEditor) return;
  if (outputEditor.getValue() === runOutput + outputInput) return;
  updatingOutput = true;
  outputEditor.setValue(runOutput + outputInput);
  outputEditor.setPosition(outputEditor.getModel().getPositionAt((runOutput + outputInput).length));
  outputEditor.revealLine(outputEditor.getModel().getLineCount());
  updatingOutput = false;
}

/** @param {{path: string, code: string}} data @param {number} revision @returns {Promise<void>} */
async function showScript(data, revision) {
  if (!monacoReady) {
    monacoReady = new Promise((resolve, reject) => {
      require.config({ paths: { vs: "vs" } });
      require(["vs/editor/editor.main"], resolve, reject);
    });
  }
  await monacoReady;
  if (revision !== navigation || data.path !== current) return;
  document.querySelector("#reading-area").hidden = true;
  document.querySelector("#code-panel").hidden = false;
  document.querySelector("#title").textContent = data.path;
  document.querySelector("#outline nav").replaceChildren();
  if (!scriptEditor) {
    scriptEditor = monaco.editor.create(document.querySelector("#code-editor"), {
      automaticLayout: true, minimap: { enabled: false }, scrollBeyondLastLine: false,
    });
    outputEditor = monaco.editor.create(document.querySelector("#code-output"), {
      automaticLayout: true, minimap: { enabled: false }, scrollBeyondLastLine: false, lineNumbers: "off", wordWrap: "on",
    });
    scriptEditor.onDidChangeModelContent(() => {
      if (scriptPath) scriptDrafts.set(scriptPath, { code: scriptEditor.getValue(), original: scriptCode });
    });
    scriptEditor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => document.querySelector("#save-script").click());
    outputEditor.onDidChangeModelContent(() => {
      if (updatingOutput) return;
      const value = outputEditor.getValue();
      if (!inputOpen || scriptPath !== runPath || !value.startsWith(runOutput) || value.slice(runOutput.length).includes("\n")) { renderOutput(); return; }
      outputInput = value.slice(runOutput.length);
    });
    outputEditor.addCommand(monaco.KeyCode.Enter, async () => {
      if (!inputOpen || scriptPath !== runPath) return;
      const value = outputInput;
      inputOpen = false;
      inputRevision++;
      try {
        const result = await postScript("run-input", { id: activeRun, input: value });
        if (!result.ok) throw new Error(await result.text());
        runOutput += value + "\n";
        outputInput = "";
        renderOutput();
      } catch (error) { document.querySelector("#run-status").textContent = String(error); }
      finally { inputRevision++; inputOpen = Boolean(activeRun) && !document.querySelector("#close-input").disabled; }
    });
  }
  if (data.path !== scriptPath || (data.code !== scriptCode && !scriptDrafts.has(data.path))) {
    if (data.path !== scriptPath) {
      updatingOutput = true;
      outputEditor.setValue(data.path === runPath ? runOutput + outputInput : "");
      updatingOutput = false;
    }
    scriptPath = data.path;
    const draft = scriptDrafts.get(data.path);
    scriptCode = draft ? draft.original : data.code;
    scriptEditor.setValue(draft ? draft.code : data.code);
    monaco.editor.setModelLanguage(scriptEditor.getModel(), data.path.toLowerCase().endsWith(".py") ? "python" : "javascript");
  }
  monaco.editor.setTheme(document.documentElement.dataset.theme === "dark" || (document.documentElement.dataset.theme === "editor" && getComputedStyle(document.documentElement).getPropertyValue("--editor-scheme").trim() === "dark") ? "vs-dark" : "vs");
  status.textContent = "";
}
/** @param {string} route @param {object} value @returns {Promise<Response>} */
function postScript(route, value) {
  return fetch(route, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(value) });
}
document.querySelector("#save-script").onclick = async () => {
  const path = scriptPath;
  const code = scriptEditor.getValue();
  const saveStatus = document.querySelector("#save-status");
  try {
    const result = await postScript("save-script", { path, code, original: scriptCode });
    if (!result.ok) throw new Error(await result.text());
    scriptDrafts.set(path, { code: scriptPath === path ? scriptEditor.getValue() : code, original: code });
    if (scriptPath === path) scriptCode = code;
    saveStatus.textContent = "Saved";
    return true;
  } catch (error) { saveStatus.textContent = String(error); return false; }
};
document.querySelector("#run-script").onclick = async () => {
  if (scriptEditor.getValue() !== scriptCode && !(await document.querySelector("#save-script").onclick())) return;
  const runButton = document.querySelector("#run-script");
  const stopButton = document.querySelector("#stop-script");
  const runStatus = document.querySelector("#run-status");
  const closeInput = document.querySelector("#close-input");
  runButton.disabled = true;
  runPath = scriptPath;
  runOutput = "";
  outputInput = "";
  renderOutput();
  runStatus.textContent = "Starting?";
  try {
    const response = await postScript("run", { path: scriptPath });
    if (!response.ok) throw new Error(await response.text());
    activeRun = (await response.json()).id;
    stopButton.disabled = false;
    inputOpen = true;
    closeInput.disabled = false;
    outputEditor.focus();
    while (activeRun) {
      const revision = inputRevision;
      const result = await fetch("job?id=" + encodeURIComponent(activeRun), { cache: "no-store" });
      if (!result.ok) throw new Error(await result.text());
      const job = await result.json();
      if (revision !== inputRevision || revision % 2 !== 0) continue;
      runOutput = job.output.replace(/\r\n/g, "\n");
      if (scriptPath === runPath) renderOutput();
      if (job.done) { runStatus.textContent = `Exit code: ${job.code}`; break; }
      runStatus.textContent = `Running ${runPath}?`;
      await new Promise(resolve => setTimeout(resolve, 300));
    }
  } catch (error) { runStatus.textContent = String(error); }
  finally { activeRun = ""; runButton.disabled = false; stopButton.disabled = true; inputOpen = false; closeInput.disabled = true; }
};
document.querySelector("#stop-script").onclick = async () => {
  try {
    const result = await postScript("stop-run", { id: activeRun });
    if (!result.ok) throw new Error(await result.text());
    document.querySelector("#run-status").textContent = "Stopping?";
  } catch (error) { document.querySelector("#run-status").textContent = String(error); }
};

document.querySelector("#close-input").onclick = async () => {
  const button = document.querySelector("#close-input");
  button.disabled = true;
  try {
    const result = await postScript("run-input", { id: activeRun, close: true });
    if (!result.ok) throw new Error(await result.text());
    inputOpen = false;
  } catch (error) { document.querySelector("#run-status").textContent = String(error); button.disabled = !activeRun; }
};

const linkPreview = document.querySelector("#link-preview");
let previewTimer;
let previewRevision = 0;
/** @returns {void} */
function hideLinkPreview() { previewRevision++; linkPreview.hidden = true; linkPreview.replaceChildren(); }
article.addEventListener("pointerover", event => {
  const link = event.target.closest("a[data-preview-path]");
  if (!link || link.contains(event.relatedTarget)) return;
  clearTimeout(previewTimer);
  const x = event.clientX;
  const y = event.clientY;
  const revision = ++previewRevision;
  previewTimer = setTimeout(async () => {
    linkPreview.replaceChildren();
    linkPreview.textContent = "Loading preview...";
    linkPreview.hidden = false;
    linkPreview.style.left = `${Math.max(8, Math.min(x + 12, innerWidth - linkPreview.offsetWidth - 8))}px`;
    linkPreview.style.top = `${Math.max(8, Math.min(y + 12, innerHeight - linkPreview.offsetHeight - 8))}px`;
    if (link.dataset.previewLocal !== "true") {
      const frame = document.createElement("iframe");
      frame.title = "Link preview";
      frame.setAttribute("sandbox", "");
      frame.referrerPolicy = "no-referrer";
      frame.src = link.dataset.previewPath;
      linkPreview.replaceChildren(frame);
      return;
    }
    try {
      const result = await fetch("document?path=" + encodeURIComponent(link.dataset.previewPath), { cache: "no-store" });
      if (!result.ok) throw new Error("Preview unavailable");
      const data = await result.json();
      if (revision !== previewRevision) return;
      if (typeof data.html !== "string") { linkPreview.textContent = data.code || ""; return; }
      linkPreview.innerHTML = data.html;
      const base = new URL(data.path.split("/").map(encodeURIComponent).join("/"), "https://workspace.invalid/");
      for (const image of linkPreview.querySelectorAll("img[src]")) {
        const target = new URL(image.getAttribute("src"), base);
        if (target.origin === base.origin) image.src = "image?path=" + encodeURIComponent(decodeURIComponent(target.pathname.slice(1)));
        else if (!["https:", "http:"].includes(target.protocol)) image.removeAttribute("src");
      }
      for (const item of linkPreview.querySelectorAll("a")) item.removeAttribute("href");
    } catch (error) { if (revision === previewRevision) linkPreview.textContent = String(error); }
  }, 350);
});
article.addEventListener("pointerout", event => {
  const link = event.target.closest("a[data-preview-path]");
  if (!link || link.contains(event.relatedTarget)) return;
  clearTimeout(previewTimer);
  previewTimer = setTimeout(hideLinkPreview, 200);
});
linkPreview.addEventListener("pointerenter", () => clearTimeout(previewTimer));
linkPreview.addEventListener("pointerleave", hideLinkPreview);
