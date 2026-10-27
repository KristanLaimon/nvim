/* Local browser client: no Node runtime or package installation. */
"use strict";
mermaid.initialize({ startOnLoad: false, securityLevel: "strict" });
let revision = "";
const article = document.querySelector("article");
const status = document.querySelector("#status");

/** Poll the editor serially so a slow diagram cannot race a later edit. */
async function refresh() {
	try {
		const response = await fetch("content", { cache: "no-store" });
		if (!response.ok) throw new Error("Preview stopped or buffer closed");
		const page = await response.json();
		if (revision !== page.revision) {
			const y = window.scrollY;
			article.innerHTML = page.html;
			document.title = page.title + " — FoxVim";
			revision = page.revision;
			status.textContent = page.title + " · Live preview";
			try {
				await mermaid.init(undefined, article.querySelectorAll(".mermaid"));
			} catch (error) {
				status.textContent = "Diagram error: " + String(error);
			}
			window.scrollTo(0, y);
		}
		setTimeout(refresh, 700);
	} catch (error) {
		status.textContent = String(error) + ". Run :MarkdownPreview to reconnect.";
	}
}
refresh();
