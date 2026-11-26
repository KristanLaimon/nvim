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
/** @param {string} path @param {string} source @returns {string} */
function readerImageURL(path, source) {
  try {
    const base = new URL(path.split("/").map(encodeURIComponent).join("/"), "https://workspace.invalid/");
    const target = new URL(source, base);
    if (target.origin === base.origin) return "image?path=" + encodeURIComponent(decodeURIComponent(target.pathname.slice(1)));
    if (target.protocol === "https:" || target.protocol === "http:") return target.href;
  } catch { /* An invalid image path cannot be displayed. */ }
  return "";
}
/** @returns {void} */
function savePosition() {
  if (!current || restoring || !lastHtml) return;
  const content = markdownEditing ? document.querySelector("#markdown-edit") : article;
  const headings = [...content.querySelectorAll("h1,h2,h3,h4,h5,h6")];
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
  if (path !== current) {
    if (!confirmReaderNavigation()) {
      if (!push) history.replaceState({ path: current }, "", "?path=" + encodeURIComponent(current));
      return;
    }
  }
  clearTimeout(scrollTimer);
  hideLinkPreview();
  savePosition();
  closeMarkdownEditor();
  current = path;
  document.querySelector("#markdown-status").textContent = "";
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
  if (path.toLowerCase().endsWith(".md")) await editMarkdown(null);
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
/** @param {string} source @returns {string} */
function renderJSON(source) {
  JSON.parse(source);
  const tokens = source.match(/"(?:\\.|[^"\\])*"|-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?|true|false|null|[{}\[\],:]/g) || [];
  const pre = document.createElement("pre");
  pre.className = "json-view";
  const code = document.createElement("code");
  pre.append(code);
  let depth = 0;
  const newline = () => code.append(document.createTextNode("\n" + "  ".repeat(depth)));
  tokens.forEach((token, index) => {
    const previous = tokens[index - 1];
    const next = tokens[index + 1];
    if (token === "{" || token === "[") {
      code.append(document.createTextNode(token));
      if (next !== "}" && next !== "]") { depth++; newline(); }
    } else if (token === "}" || token === "]") {
      if (previous !== "{" && previous !== "[") { depth--; newline(); }
      code.append(document.createTextNode(token));
    } else if (token === ",") {
      code.append(document.createTextNode(token));
      newline();
    } else if (token === ":") {
      code.append(document.createTextNode(": "));
    } else {
      const value = document.createElement("span");
      value.className = token.startsWith('"') ? (next === ":" ? "json-key" : "json-string") : "json-value";
      value.textContent = token;
      code.append(value);
    }
  });
  return pre.outerHTML;
}
/** @returns {Promise<void>} */
async function refresh() {
  if (!current) return;
  if (markdownEditing) {
    if (markdownRefreshing || markdownSaving) return;
    const draft = markdownDrafts.get(current);
    if (!draft || !markdownEditor) return;
    updateMarkdownDraft(draft, markdownEditor.getMarkdown());
    if (draft.error || draft.source !== draft.original) return;
    const path = current;
    const revision = navigation;
    const saveRevision = markdownSaveRevision;
    markdownRefreshing = true;
    try {
      const response = await fetch("document?path=" + encodeURIComponent(path), { cache: "no-store" });
      const data = response.ok ? await response.json() : null;
      if (revision !== navigation || saveRevision !== markdownSaveRevision || !markdownEditor) return;
      updateMarkdownDraft(draft, markdownEditor.getMarkdown());
      if (draft.error || draft.source !== draft.original) return;
      if (!data || data.html !== lastHtml || (data.frontmatter || "") !== lastMetadata) {
        markdownDrafts.delete(path);
        await openDocument(path, false);
      }
    } catch { /* Retry on the next refresh. */ }
    finally { markdownRefreshing = false; }
    return;
  }
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
    let documentMessage = "";
    if (typeof documentData.json === "string") {
      try { documentData.html = renderJSON(documentData.json); }
      catch {
        const pre = document.createElement("pre");
        pre.className = "plain-text";
        pre.textContent = documentData.json;
        documentData.html = pre.outerHTML;
        documentMessage = "Invalid JSON; showing the original text.";
      }
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
        const url = readerImageURL(current, image.getAttribute("src"));
        if (url) image.src = url; else image.removeAttribute("src");
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
    status.textContent = documentMessage;
    if (path.toLowerCase().endsWith(".md") && !markdownEditing && !markdownOpening) await editMarkdown(null);
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
  followOutline();
  if (restoring) return;
  clearTimeout(scrollTimer);
  scrollTimer = setTimeout(savePosition, 500);
}
window.addEventListener("scroll", schedulePositionSave, { passive: true });
document.addEventListener("scroll", schedulePositionSave, { capture: true, passive: true });
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
  const frame = document.querySelector("#split-frame");
  try { if (!document.querySelector("#split-pane").hidden && frame.contentWindow.confirmReaderNavigation?.() === false) return; } catch { /* External frames do not expose reader state. */ }
  const previousScroll = readingScrollTop();
  const panes = document.querySelector("#panes");
  panes.classList.remove("split-left", "split-right", "split-top", "split-bottom");
  panes.classList.add(`split-${side}`);
  document.querySelector("#split-title").textContent = path;
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
}, true);
document.querySelector("#split-close").onclick = () => {
  try { if (document.querySelector("#split-frame").contentWindow.confirmReaderNavigation?.() === false) return; } catch { /* External frames do not expose reader state. */ }
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

let markdownEditor;
let markdownEditing = false;
let markdownOpening = false;
let markdownRefreshing = false;
let markdownSaving = false;
let markdownSaveRevision = 0;
let markdownRevision = 0;
let markdownImageAnchor;
let markdownOutlineSignature = "";
const markdownDrafts = new Map();
/** @returns {boolean} */
function confirmReaderNavigation() {
  const draft = markdownDrafts.get(current);
  if (draft && markdownEditor) updateMarkdownDraft(draft, markdownEditor.getMarkdown());
  return !draft || (!draft.error && draft.source === draft.original)
    || window.confirm("This document has unsaved changes. Leave it and keep the draft?");
}
window.confirmReaderNavigation = confirmReaderNavigation;
/** @returns {void} */
function rebuildMarkdownOutline() {
  if (!markdownEditing) return;
  const headings = [...document.querySelectorAll("#markdown-edit h1,#markdown-edit h2,#markdown-edit h3,#markdown-edit h4,#markdown-edit h5,#markdown-edit h6")];
  const signature = JSON.stringify(headings.map(heading => [heading.tagName, heading.textContent]));
  if (signature === markdownOutlineSignature) { followOutline(); return; }
  markdownOutlineSignature = signature;
  const outline = document.querySelector("#outline nav");
  outline.replaceChildren();
  const ids = new Map();
  for (const heading of headings) {
    const slug = heading.textContent.trim().toLowerCase().replace(/[^\p{L}\p{N}_\- ]/gu, "").replace(/ /g, "-");
    const count = ids.get(slug) || 0;
    ids.set(slug, count + 1);
    const id = count ? `${slug}-${count}` : slug;
    const link = document.createElement("a");
    link.href = "#" + id;
    link.textContent = heading.textContent;
    link.style.paddingLeft = `${0.5 + (Number(heading.tagName.slice(1)) - 1) * 0.85}rem`;
    link.onclick = event => {
      event.preventDefault();
      const header = document.querySelector("#panes > main > header");
      scrollReadingTo(readingScrollTop() + heading.getBoundingClientRect().top - readingViewportTop() - header.offsetHeight - 8);
      followOutline();
    };
    outline.append(link);
  }
  followOutline();
}
/** @returns {void} */
function followOutline() {
  if (!markdownEditing) return;
  const headings = [...document.querySelectorAll("#markdown-edit h1,#markdown-edit h2,#markdown-edit h3,#markdown-edit h4,#markdown-edit h5,#markdown-edit h6")];
  const links = [...document.querySelectorAll("#outline nav a")];
  if (!headings.length || headings.length !== links.length) return;
  const threshold = readingViewportTop() + document.querySelector("#panes > main > header").offsetHeight + 16;
  let index = 0;
  headings.forEach((heading, currentIndex) => { if (heading.getBoundingClientRect().top <= threshold) index = currentIndex; });
  const selected = links[index];
  if (selected.getAttribute("aria-current") === "location") return;
  links.forEach(link => link.removeAttribute("aria-current"));
  selected.setAttribute("aria-current", "location");
  const outline = document.querySelector("#outline");
  if (outline.clientHeight) {
    const offset = selected.getBoundingClientRect().top - outline.getBoundingClientRect().top + outline.scrollTop;
    outline.scrollTo({ top: offset - outline.clientHeight * .75 });
  }
}
/** @returns {void} */
function closeMarkdownEditor() {
  markdownRevision++;
  markdownImageAnchor?.abort();
  markdownImageAnchor = null;
  const draft = markdownDrafts.get(current);
  if (markdownEditor && draft) updateMarkdownDraft(draft, markdownEditor.getMarkdown());
  markdownEditing = false;
  markdownOutlineSignature = "";
  if (markdownEditor) { markdownEditor.destroy(); markdownEditor = null; }
  document.querySelector("#markdown-edit").replaceChildren();
  document.querySelector("#markdown-edit").hidden = true;
  document.querySelector("#markdown-properties").replaceChildren();
  document.querySelector("#markdown-properties").hidden = true;
  article.hidden = false;
}
/** @param {string} source @returns {[string, string]} */
function splitMarkdownFrontmatter(source) {
  const match = source.match(/^(---\r?\n[\s\S]*?\r?\n(?:---|\.\.\.)[ \t]*\r?\n)/);
  return match ? [match[1], source.slice(match[1].length)] : ["", source];
}
/** @param {object} draft @returns {void} */
function showMarkdownProperties(draft) {
  const root = document.querySelector("#markdown-properties");
  root.replaceChildren();
  const match = draft.frontmatter.match(/^(---\r?\n)([\s\S]*?)(\r?\n(?:---|\.\.\.)[ \t]*\r?\n)$/);
  if (!match) { root.hidden = true; return; }
  const details = document.createElement("details");
  details.className = "metadata";
  details.open = true;
  const title = document.createElement("summary");
  title.textContent = "Properties";
  const editor = document.createElement("textarea");
  editor.setAttribute("aria-label", "Edit properties as YAML");
  editor.spellcheck = false;
  editor.value = match[2];
  const resize = () => { editor.style.height = "auto"; editor.style.height = `${editor.scrollHeight}px`; };
  editor.addEventListener("input", () => {
    const newline = match[1].endsWith("\r\n") ? "\r\n" : "\n";
    draft.frontmatter = match[1] + editor.value.replace(/\n/g, newline) + match[3];
    if (markdownEditor) updateMarkdownDraft(draft, markdownEditor.getMarkdown());
    document.querySelector("#markdown-status").textContent = draft.error || (draft.source === draft.original ? "" : "Unsaved changes");
    resize();
  });
  details.append(title, editor);
  root.append(details);
  root.hidden = false;
  resize();
}
/** @param {string} source @returns {{visual: string, tokens: {token: string, html: string}[]}} */
function protectMarkdownHtml(source) {
  let prefix = "⟦HTML";
  while (source.includes(prefix)) prefix += "_";
  const tokens = [];
  // Keep fenced and inline code untouched while preserving literal HTML through Markdown serialization.
  const parts = /(^ {0,3}(`{3,}|~{3,})[^\n]*\n[\s\S]*?^ {0,3}\2[ \t]*\r?$)|(`+[^`\n]*`+)|(<(?<rawTag>script|style|pre|textarea|table)\b(?:"[^"]*"|'[^']*'|[^'">])*?>[\s\S]*?<\/\k<rawTag>\s*>|<!--[\s\S]*?(?:-->|$)|<\?[\s\S]*?\?>|<![^>]*>|<\/?[a-zA-Z][\w:.-]*(?=[\s/>])(?:"[^"]*"|'[^']*'|[^'">])*?>)/gim;
  const visual = source.replace(parts, (match, fence, _marker, inlineCode, html) => {
    if (fence || inlineCode || !html) return match;
    const token = `${prefix}${tokens.length + 1}⟧`;
    tokens.push({ token, html });
    return token;
  });
  return { visual, tokens };
}
/** @param {object} draft @param {string} markdown @returns {boolean} */
function updateMarkdownDraft(draft, markdown) {
  draft.visual = markdown;
  let restored = markdown;
  let previous = -1;
  for (const item of draft.tokens) {
    const position = markdown.indexOf(item.token);
    if (position <= previous || markdown.indexOf(item.token, position + 1) !== -1) {
      draft.error = "Keep the HTML markers intact to save the document.";
      return false;
    }
    previous = position;
    restored = restored.replace(item.token, () => item.html);
  }
  draft.error = "";
  draft.source = draft.frontmatter + (markdown === draft.baseline ? splitMarkdownFrontmatter(draft.initialSource)[1] : restored);
  return true;
}
/** @param {{tag: string, text: string, occurrence: number, offset: number, top: number} | null} target @returns {Promise<void>} */
async function editMarkdown(target) {
  if (markdownOpening || markdownEditing || !current.toLowerCase().endsWith(".md")) return;
  markdownOpening = true;
  const path = current;
  const revision = ++markdownRevision;
  const markdownStatus = document.querySelector("#markdown-status");
  try {
    const response = await fetch("markdown-source?path=" + encodeURIComponent(path), { cache: "no-store" });
    if (!response.ok) throw new Error(await response.text());
    const original = await response.text();
    if (revision !== markdownRevision || current !== path) return;
    const existing = markdownDrafts.get(path);
    const source = existing ? existing.source : original;
    const [frontmatter, body] = splitMarkdownFrontmatter(source);
    const protectedHtml = existing?.error ? { visual: existing.visual, tokens: existing.tokens } : protectMarkdownHtml(body);
    const root = document.querySelector("#markdown-edit");
    const imageSizes = new Map([...article.querySelectorAll("img[src]")].map(image => [image.src, { width: image.naturalWidth, height: image.naturalHeight }]));
    const resolveImage = source => {
      const url = readerImageURL(path, source);
      return { url, ...(url ? imageSizes.get(new URL(url, document.baseURI).href) : null) };
    };
    const htmlImages = protectedHtml.tokens.flatMap(item => {
      if (!/<img(?:\s|\/?>)/i.test(item.html)) return [];
      const template = document.createElement("template");
      template.innerHTML = item.html;
      return [...template.content.querySelectorAll("img[src]")].map((image, index) => ({
        token: item.token, key: `${item.token}:${index}`, src: image.getAttribute("src"), alt: image.alt,
        width: Number(image.getAttribute("width")) || 0, height: Number(image.getAttribute("height")) || 0,
      }));
    });
    const editor = new FoxMarkdownEditor({ root, defaultValue: protectedHtml.visual, resolveImage, htmlImages, htmlTokens: protectedHtml.tokens });
    await editor.create();
    if (revision !== markdownRevision || current !== path) { await editor.destroy(); return; }
    const images = [...root.querySelectorAll("img[src]")];
    await Promise.race([
      Promise.allSettled(images.map(image => image.decode())),
      new Promise(resolve => setTimeout(resolve, 1500)),
    ]);
    if (revision !== markdownRevision || current !== path) { await editor.destroy(); return; }
    markdownEditor = editor;
    const baseline = editor.getMarkdown();
    const draft = existing || { original, source, baseline };
    draft.baseline = baseline;
    draft.frontmatter = frontmatter;
    draft.initialSource = source;
    draft.tokens = protectedHtml.tokens;
    markdownDrafts.set(path, draft);
    editor.on(listener => listener.markdownUpdated(() => queueMicrotask(() => {
      if (markdownEditor !== editor || current !== path) return;
      updateMarkdownDraft(draft, editor.getMarkdown());
      if (draft.error || draft.source !== draft.original) markdownStatus.textContent = draft.error || "Unsaved changes";
      else if (markdownStatus.textContent !== "Saved") markdownStatus.textContent = "";
      requestAnimationFrame(rebuildMarkdownOutline);
    })));
    markdownEditing = true;
    article.hidden = true;
    root.hidden = false;
    showMarkdownProperties(draft);
    const oldHeadings = [...article.querySelectorAll("h1,h2,h3,h4,h5,h6")];
    oldHeadings.forEach(heading => heading.removeAttribute("id"));
    rebuildMarkdownOutline();
    markdownStatus.textContent = draft.error || (draft.source === draft.original ? "" : "Unsaved changes");
    const editable = root.querySelector('[contenteditable="true"]');
    if (target) editable?.focus({ preventScroll: true });
    if (target && editable) {
      const visibleText = text => draft.tokens.reduce((value, item) => value.split(item.token).join("").split(item.html).join(""), text);
      const blocks = [...editable.querySelectorAll(target.tag)].filter(block => visibleText(block.textContent) === visibleText(target.text));
      const block = blocks[target.occurrence];
      if (block) {
        const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT);
        let remaining = visibleText(target.text.slice(0, target.offset)).length;
        let node;
        while ((node = walker.nextNode())) {
          let position = 0;
          while (position < node.length) {
            const token = draft.tokens.find(item => node.data.startsWith(item.token, position));
            if (token) { position += token.token.length; continue; }
            if (remaining === 0) break;
            remaining--;
            position++;
          }
          if (remaining === 0) {
            const range = document.createRange();
            range.setStart(node, position);
            range.collapse(true);
            const selection = window.getSelection();
            selection.removeAllRanges();
            selection.addRange(range);
            break;
          }
        }
        scrollReadingTo(readingScrollTop() + block.getBoundingClientRect().top - target.top);
        const pendingImages = images.filter(image => !image.complete);
        if (pendingImages.length) {
          const anchor = new AbortController();
          markdownImageAnchor = anchor;
          const stop = () => anchor.abort();
          for (const name of ["wheel", "pointerdown", "touchstart", "keydown", "resize"]) {
            window.addEventListener(name, stop, { once: true, passive: true, signal: anchor.signal });
          }
          let pending = pendingImages.length;
          const settle = () => {
            if (block.isConnected) scrollReadingTo(readingScrollTop() + block.getBoundingClientRect().top - target.top);
            if (--pending === 0) anchor.abort();
          };
          for (const image of pendingImages) {
            image.addEventListener("load", settle, { once: true, signal: anchor.signal });
            image.addEventListener("error", settle, { once: true, signal: anchor.signal });
          }
        }
      }
    }
  } catch (error) { if (revision === markdownRevision) markdownStatus.textContent = String(error); }
  finally { markdownOpening = false; }
}
article.addEventListener("click", event => {
  if (event.button !== 0 || event.ctrlKey || event.metaKey || event.altKey || event.shiftKey || !window.getSelection().isCollapsed) return;
  if (event.target.closest("a,button,input,summary,video,audio,.metadata")) return;
  const block = event.target.closest("h1,h2,h3,h4,h5,h6,p,li,td,th,pre");
  if (!block || !article.contains(block)) { editMarkdown(null); return; }
  const caret = document.caretRangeFromPoint(event.clientX, event.clientY);
  let offset = block.textContent.length;
  if (caret && block.contains(caret.startContainer)) {
    const before = document.createRange();
    before.selectNodeContents(block);
    before.setEnd(caret.startContainer, caret.startOffset);
    offset = before.toString().length;
  }
  const tag = block.tagName.toLowerCase();
  const matches = [...article.querySelectorAll(tag)].filter(item => item.textContent === block.textContent);
  editMarkdown({ tag, text: block.textContent, occurrence: matches.indexOf(block), offset, top: block.getBoundingClientRect().top });
});
article.addEventListener("keydown", event => {
  if (event.target === article && event.key === "Enter" && !event.ctrlKey && !event.metaKey && !event.altKey && !event.shiftKey) {
    event.preventDefault();
    editMarkdown(null);
  }
});
document.querySelector("#reading-area").addEventListener("click", event => {
  if (event.target === event.currentTarget && event.button === 0 && !event.ctrlKey && !event.metaKey && !event.altKey && !event.shiftKey) editMarkdown(null);
});
document.querySelector("#markdown-edit").addEventListener("input", () => {
  if (markdownEditing) document.querySelector("#markdown-status").textContent = "Unsaved changes";
});
async function saveMarkdown() {
  if (markdownSaving) { document.querySelector("#markdown-status").textContent = "Saving; try again shortly."; return false; }
  const path = current;
  const draft = markdownDrafts.get(path);
  if (draft && markdownEditor) updateMarkdownDraft(draft, markdownEditor.getMarkdown());
  if (draft?.error) { document.querySelector("#markdown-status").textContent = draft.error; return false; }
  if (!draft || draft.source === draft.original) return true;
  const source = draft.source;
  markdownSaving = true;
  markdownSaveRevision++;
  document.querySelector("#markdown-status").textContent = "Saving...";
  try {
    const result = await postScript("save-markdown", { path, code: source, original: draft.original });
    if (!result.ok) throw new Error(await result.text());
    draft.original = source;
    if (current === path) {
      try {
        const view = await fetch("document?path=" + encodeURIComponent(path), { cache: "no-store" });
        if (view.ok) {
          const data = await view.json();
          if (current === path) { lastHtml = data.html; lastMetadata = data.frontmatter || ""; }
        }
      } catch { /* The save succeeded; the next refresh will retry the preview. */ }
    }
    if (current === path) document.querySelector("#markdown-status").textContent = draft.source === source ? "Saved" : "Unsaved changes";
    return true;
  } catch (error) { if (current === path) document.querySelector("#markdown-status").textContent = String(error); return false; }
  finally { markdownSaving = false; }
}
document.addEventListener("keydown", event => {
  if (markdownEditing && (event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "s") {
    event.preventDefault();
    saveMarkdown();
  }
}, true);
window.addEventListener("beforeunload", event => {
  const draft = markdownDrafts.get(current);
  if (draft && markdownEditor) updateMarkdownDraft(draft, markdownEditor.getMarkdown());
  if ([...markdownDrafts.values()].some(draft => draft.error || draft.source !== draft.original)) event.preventDefault();
});

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
/** @param {HTMLAnchorElement} link @returns {{path: string, local: boolean, anchor: string} | null} */
function markdownLinkTarget(link) {
  try {
    const base = new URL(current.split("/").map(encodeURIComponent).join("/"), "https://workspace.invalid/");
    const target = new URL(link.getAttribute("href"), base);
    const local = target.origin === base.origin;
    if (!local && !["http:", "https:"].includes(target.protocol)) return null;
    return { path: local ? decodeURIComponent(target.pathname.slice(1)) : target.href, local, anchor: target.hash };
  } catch { return null; }
}
document.querySelector("#markdown-edit").addEventListener("click", event => {
  const link = event.target.closest("a[href]");
  if (!link || event.button !== 0 || event.altKey || event.metaKey) return;
  const target = markdownLinkTarget(link);
  if (!target) return;
  if (event.ctrlKey && event.shiftKey) {
    event.preventDefault();
    window.top.openReaderSplit(target.path, "right", target.local ? target.anchor : "", !target.local);
  } else if (target.local && !event.ctrlKey && !event.shiftKey) {
    event.preventDefault();
    if (target.path === current && target.anchor) document.getElementById(decodeURIComponent(target.anchor.slice(1)))?.scrollIntoView();
    else openDocument(target.path, true, target.anchor);
  }
});
/** @param {PointerEvent} event @returns {void} */
function previewLink(event) {
  const link = event.target.closest("a[href]");
  if (!link || link.contains(event.relatedTarget)) return;
  const target = link.dataset.previewPath
    ? { path: link.dataset.previewPath, local: link.dataset.previewLocal === "true" }
    : markdownLinkTarget(link);
  if (!target) return;
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
    if (!target.local) {
      const frame = document.createElement("iframe");
      frame.title = "Link preview";
      frame.setAttribute("sandbox", "");
      frame.referrerPolicy = "no-referrer";
      frame.src = target.path;
      linkPreview.replaceChildren(frame);
      return;
    }
    try {
      const result = await fetch("document?path=" + encodeURIComponent(target.path), { cache: "no-store" });
      if (!result.ok) throw new Error("Preview unavailable");
      const data = await result.json();
      if (revision !== previewRevision) return;
      if (typeof data.html !== "string") { linkPreview.textContent = data.code || data.json || ""; return; }
      linkPreview.innerHTML = data.html;
      for (const image of linkPreview.querySelectorAll("img[src]")) {
        const url = readerImageURL(data.path, image.getAttribute("src"));
        if (url) image.src = url; else image.removeAttribute("src");
      }
      for (const item of linkPreview.querySelectorAll("a")) item.removeAttribute("href");
    } catch (error) { if (revision === previewRevision) linkPreview.textContent = String(error); }
  }, 350);
}
/** @param {PointerEvent} event @returns {void} */
function leavePreviewLink(event) {
  const link = event.target.closest("a[href]");
  if (!link || link.contains(event.relatedTarget)) return;
  clearTimeout(previewTimer);
  previewTimer = setTimeout(hideLinkPreview, 200);
}
for (const content of [article, document.querySelector("#markdown-edit")]) {
  content.addEventListener("pointerover", previewLink);
  content.addEventListener("pointerout", leavePreviewLink);
}
linkPreview.addEventListener("pointerenter", () => clearTimeout(previewTimer));
linkPreview.addEventListener("pointerleave", hideLinkPreview);
