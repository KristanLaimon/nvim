"use strict";
const files = document.querySelector("#files");
const article = document.querySelector("#content");
const status = document.querySelector("#status");
let current = new URL(location.href).searchParams.get("path") || "";
let lastHtml = "";
let allFiles = [];
const expandedFolders = new Set();
const preferences = JSON.parse(localStorage.getItem("fox-reader-preferences") || "{}");
document.documentElement.dataset.theme = preferences.theme || "paper";
document.querySelector("#size").value = preferences.size || 18;
document.documentElement.style.setProperty("--reading-size", `${document.querySelector("#size").value}px`);
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
  current = path;
  lastHtml = "";
  if (push) history.pushState({ path }, "", "?path=" + encodeURIComponent(path) + anchor);
  await refresh();
  if (anchor) document.getElementById(decodeURIComponent(anchor.slice(1)))?.scrollIntoView();
  else window.scrollTo(0, 0);
}
/** @returns {Promise<void>} */
async function refresh() {
  if (!current) return;
  try {
    const result = await fetch("document?path=" + encodeURIComponent(current), { cache: "no-store" });
    if (!result.ok) throw new Error("Document is unavailable");
    const documentData = await result.json();
    if (documentData.path !== current) return;
    if (documentData.html !== lastHtml) {
      const top = window.scrollY;
      article.innerHTML = documentData.html;
      lastHtml = documentData.html;
      document.querySelector("#title").textContent = current;
      const base = new URL(current.split("/").map(encodeURIComponent).join("/"), "https://workspace.invalid/");
      for (const image of article.querySelectorAll("img[src]")) {
        const target = new URL(image.getAttribute("src"), base);
        if (target.origin === base.origin) image.src = "image?path=" + encodeURIComponent(decodeURIComponent(target.pathname.slice(1)));
      }
      for (const link of article.querySelectorAll("a[href]")) {
        const href = link.getAttribute("href");
        if (href.startsWith("#")) continue;
        const target = new URL(href, base);
        const targetPath = decodeURIComponent(target.pathname.slice(1));
        if (target.origin === base.origin) {
          link.onclick = event => {
            if (!allFiles.includes(targetPath)) return;
            event.preventDefault();
            openDocument(targetPath, true, target.hash);
          };
        }
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
      window.scrollTo(0, top);
    }
    status.textContent = "";
  } catch (error) { status.textContent = String(error); }
}
/** @returns {Promise<void>} */
async function refreshLibrary() {
  try { allFiles = (await (await fetch("library", { cache: "no-store" })).json()).files; renderFiles(); }
  catch (error) { status.textContent = String(error); }
}
document.querySelector("#filter").oninput = renderFiles;
document.querySelector("#focus").onclick = () => document.body.classList.toggle("focus");
document.querySelector("#library-toggle").onclick = () => document.body.classList.toggle("show-library");
document.querySelector("#theme").onclick = () => {
  const themes = ["paper", "light", "dark"];
  preferences.theme = themes[(themes.indexOf(document.documentElement.dataset.theme) + 1) % themes.length];
  document.documentElement.dataset.theme = preferences.theme;
  localStorage.setItem("fox-reader-preferences", JSON.stringify(preferences));
};
document.querySelector("#size").oninput = event => {
  preferences.size = event.target.value;
  document.documentElement.style.setProperty("--reading-size", `${preferences.size}px`);
  localStorage.setItem("fox-reader-preferences", JSON.stringify(preferences));
};
window.onpopstate = () => openDocument(new URL(location.href).searchParams.get("path") || "", false, location.hash);
refreshLibrary();
if (current) refresh();
setInterval(refresh, 1000);
setInterval(refreshLibrary, 5000);
