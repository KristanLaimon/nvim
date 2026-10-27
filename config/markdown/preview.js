/* Local browser client: no Node runtime or package installation. */
"use strict";
let revision = "";
let cursorLine = 0;
/** @type {HTMLElement[]} */
let sourceElements = [];
const article = document.querySelector("article");
const status = document.querySelector("#status");
const themeButton = document.querySelector("#theme");

/** Apply the browser's color scheme and use matching Mermaid colors.
 * @param {boolean} dark Whether to use the dark theme.
 */
function setTheme(dark) {
	document.documentElement.dataset.theme = dark ? "dark" : "light";
	themeButton.textContent = dark ? "Light" : "Dark";
	themeButton.setAttribute("aria-pressed", String(dark));
	mermaid.initialize({ startOnLoad: false, securityLevel: "strict", theme: dark ? "dark" : "default" });
}
setTheme(matchMedia("(prefers-color-scheme: dark)").matches);
themeButton.addEventListener("click", () => {
	setTheme(document.documentElement.dataset.theme !== "dark");
	revision = "";
});

/** Center the nearest source line without moving keyboard focus out of the editor.
 * @param {number} line One-based source line in Neovim.
 */
function followCursor(line) {
	let best = null;
	let bestDistance = Infinity;
	let bestSpan = Infinity;
	for (const element of sourceElements) {
		const first = Number(element.dataset.sourceLine);
		const last = Number(element.dataset.sourceEnd || first);
		const distance = Math.max(first - line, line - last, 0);
		if (distance < bestDistance || (distance === bestDistance && last - first < bestSpan)) {
			best = element;
			bestDistance = distance;
			bestSpan = last - first;
		}
	}
	if (!best) return;
	for (let parent = best.parentElement; parent; parent = parent.parentElement) {
		if (parent.tagName === "DETAILS") parent.open = true;
	}
	article.querySelector('[aria-current="location"]')?.removeAttribute("aria-current");
	best.setAttribute("aria-current", "location");
	const bounds = best.getBoundingClientRect();
	const first = Number(best.dataset.sourceLine);
	const last = Number(best.dataset.sourceEnd || first);
	const fraction = Math.max(0, Math.min(1, (line - first + 0.5) / (last - first + 1)));
	window.scrollTo({ top: window.scrollY + bounds.top + bounds.height * fraction - window.innerHeight / 2, behavior: "instant" });
}

new ResizeObserver(() => followCursor(cursorLine)).observe(article);
window.addEventListener("resize", () => followCursor(cursorLine));

/** Poll the editor serially so a slow diagram cannot race a later edit. */
async function refresh() {
	try {
		const response = await fetch("content?revision=" + encodeURIComponent(revision), { cache: "no-store" });
		if (!response.ok) throw new Error("Preview stopped or buffer closed");
		const page = await response.json();
		const changed = revision !== page.revision;
		if (changed) {
			article.innerHTML = page.html;
			document.title = page.title + " — FoxVim";
			revision = page.revision;
			status.textContent = page.title + " · Live preview";
			try {
				await mermaid.init(undefined, article.querySelectorAll(".mermaid"));
			} catch (error) {
				status.textContent = "Diagram error: " + String(error);
			}
			sourceElements = [...article.querySelectorAll("[data-source-line]")];
		}
		if (changed || cursorLine !== page.line) {
			cursorLine = page.line;
			followCursor(cursorLine);
		}
		setTimeout(refresh, 150);
	} catch (error) {
		status.textContent = String(error) + ". Run :MarkdownPreview to reconnect.";
	}
}
refresh();
