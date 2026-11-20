"use strict";
const files = document.querySelector("#files");
const article = document.querySelector("#content");
const status = document.querySelector("#status");
let current = new URL(location.href).searchParams.get("path") || "";
let lastHtml = "";
let navigation = 0;
let allFiles = [];
const expandedFolders = new Set();
const preferences = { theme: document.documentElement.dataset.theme || "editor", font: "Trebuchet MS", alignment: "justify", size: 18, lineSpacing: 1.8, width: 760, focus: false };
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
/** @returns {void} */
function savePosition() {
  if (!current || restoring || !lastHtml) return;
  const headings = [...article.querySelectorAll("h1,h2,h3,h4,h5,h6")];
  const heading = headings.filter(item => item.getBoundingClientRect().top <= 0).pop();
  saveState({ kind: "position", path: current, value: { heading: heading?.id || "", offset: heading?.getBoundingClientRect().top || 0, scroll: window.scrollY } });
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
  for (const path of allFiles.filter(name => name.toLowerCase().includes(query))) {
    const parts = path.split("/");
    const filename = parts.pop();
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
    const link = document.createElement("a");
    link.href = "?path=" + encodeURIComponent(path);
    link.textContent = filename;
    link.dataset.extension = (filename.split(".").pop() || "").toLowerCase();
    if (path === current) link.setAttribute("aria-current", "page");
    link.onclick = event => { event.preventDefault(); openDocument(path); };
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
  renderFiles();
  navigation++;
  const revision = navigation;
  restoring = true;
  lastHtml = "";
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
    window.scrollTo(0, heading && typeof saved.position.offset === "number"
      ? window.scrollY + heading.getBoundingClientRect().top - saved.position.offset : saved.position.scroll);
  } else window.scrollTo(0, 0);
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
    if (documentData.html !== lastHtml) {
      const headings = [...article.querySelectorAll("h1,h2,h3,h4,h5,h6")];
      const visible = headings.filter(heading => heading.getBoundingClientRect().top <= 0).pop();
      const anchorId = visible?.id;
      const offset = visible?.getBoundingClientRect().top;
      const top = window.scrollY;
      article.innerHTML = documentData.html;
      lastHtml = documentData.html;
      document.querySelector("#title").textContent = current;
      const base = new URL(current.split("/").map(encodeURIComponent).join("/"), "https://workspace.invalid/");
      for (const image of article.querySelectorAll("img[src]")) {
        try {
          const target = new URL(image.getAttribute("src"), base);
          if (target.origin === base.origin) image.src = "image?path=" + encodeURIComponent(decodeURIComponent(target.pathname.slice(1)));
          else image.removeAttribute("src");
        } catch { image.removeAttribute("src"); }
      }
      for (const link of article.querySelectorAll("a[href]")) {
        try {
          const target = new URL(link.getAttribute("href"), base);
          if (target.origin !== base.origin) continue;
          const targetPath = decodeURIComponent(target.pathname.slice(1));
          link.href = "?path=" + encodeURIComponent(targetPath) + target.hash;
          link.onclick = event => {
            if (event.button !== 0 || event.ctrlKey || event.metaKey || event.shiftKey || event.altKey) return;
            event.preventDefault();
            openDocument(targetPath, true, target.hash);
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
        outline.append(link);
      }
      await mermaid.run({ nodes: article.querySelectorAll(".mermaid") });
      if (revision !== navigation) return;
      const restored = anchorId && document.getElementById(anchorId);
      window.scrollTo(0, restored ? window.scrollY + restored.getBoundingClientRect().top - offset : top);
    }
    status.textContent = "";
  } catch (error) {
    if (revision !== navigation) return;
    lastHtml = "";
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
document.querySelector("#focus").onclick = () => {
  preferences.focus = !preferences.focus;
  applyReadingStyle();
  saveState({ kind: "preferences", value: { ...preferences } });
};
document.querySelector("#library-toggle").onclick = () => document.body.classList.toggle("show-library");
document.querySelector("#theme").onclick = () => {
  const themes = ["editor", "paper", "light", "dark"];
  preferences.theme = themes[(themes.indexOf(document.documentElement.dataset.theme) + 1) % themes.length];
  document.documentElement.dataset.theme = preferences.theme;
  saveState({ kind: "preferences", value: { ...preferences } });
};
for (const setting of ["font", "alignment", "size", "lineSpacing", "width"]) {
  document.querySelector(`#${setting}`).onchange = event => {
    preferences[setting] = ["size", "lineSpacing", "width"].includes(setting) ? Number(event.target.value) : event.target.value;
    applyReadingStyle();
    saveState({ kind: "preferences", value: { ...preferences } });
  };
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
window.addEventListener("scroll", () => {
  if (restoring) return;
  clearTimeout(scrollTimer);
  scrollTimer = setTimeout(savePosition, 500);
}, { passive: true });
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
  }
  applyReadingStyle();
  if (current) openDocument(current, false, location.hash);
});
setInterval(refresh, 1000);
setInterval(refreshLibrary, 5000);
setInterval(refreshTheme, 1000);
