import { CrepeBuilder } from "@milkdown/crepe/builder";
import { editorViewCtx, editorViewOptionsCtx } from "@milkdown/kit/core";
import { imageSchema, bulletListSchema, orderedListSchema, listItemSchema } from "@milkdown/kit/preset/commonmark";
import { $prose } from "@milkdown/kit/utils";
import { Plugin } from "@milkdown/kit/prose/state";
import { Decoration, DecorationSet } from "@milkdown/kit/prose/view";

window.FoxMarkdownEditor = class extends CrepeBuilder {
  constructor({ resolveImage, htmlImages, htmlTokens, ...options }) {
    super(options);
    const getMarkdown = this.getMarkdown;
    this.getMarkdown = () => {
      this.editor.action(ctx => ctx.get(editorViewCtx).domObserver.flush());
      return getMarkdown();
    };
    // Milkdown 7.19's Markdown runners pass nullable images and string list flags to strictly typed schemas.
    this.editor.use(imageSchema.extendSchema(previous => ctx => {
      const schema = previous(ctx);
      return {
        ...schema,
        parseMarkdown: {
          ...schema.parseMarkdown,
          runner: (state, node, type) => state.addNode(type, {
            src: node.url || "", alt: node.alt || "", title: node.title || "",
          }),
        },
      };
    }));
    for (const listSchema of [bulletListSchema, orderedListSchema]) {
      this.editor.use(listSchema.extendSchema(previous => ctx => {
        const schema = previous(ctx);
        return {
          ...schema,
          ...(listSchema === orderedListSchema ? {
            toDOM: node => ["ol", { start: node.attrs.order, "data-spread": node.attrs.spread }, 0],
          } : {}),
          parseMarkdown: {
            ...schema.parseMarkdown,
            runner: (state, node, type) => state.openNode(type, {
              spread: Boolean(node.spread), ...(node.ordered ? { order: node.start ?? 1 } : {}),
            }).next(node.children).closeNode(),
          },
          toMarkdown: {
            ...schema.toMarkdown,
            runner: (state, node) => {
              state.openNode("list", undefined, {
                ordered: node.type.name === "ordered_list", start: node.attrs.order ?? null, spread: node.attrs.spread,
              });
              state.next(node.content).closeNode();
            },
          },
        };
      }));
    }
    this.editor.use(listItemSchema.extendSchema(previous => ctx => {
      const schema = previous(ctx);
      return {
        ...schema,
        attrs: { ...schema.attrs, checked: { default: null, validate: "boolean|null" } },
        toDOM: node => node.attrs.checked == null ? schema.toDOM(node) : ["li", {
          "data-item-type": "task", "data-label": node.attrs.label, "data-list-type": node.attrs.listType,
          "data-spread": node.attrs.spread, "data-checked": node.attrs.checked,
        }, 0],
        parseDOM: [{
          tag: 'li[data-item-type="task"]',
          getAttrs: dom => ({
            label: dom.dataset.label || "•", listType: dom.dataset.listType || "bullet",
            spread: dom.dataset.spread === "true", checked: dom.dataset.checked === "true",
          }),
        }, ...schema.parseDOM],
        parseMarkdown: {
          ...schema.parseMarkdown,
          runner: (state, node, type) => {
            state.openNode(type, {
              label: node.label != null ? `${node.label}.` : "•",
              listType: node.label != null ? "ordered" : "bullet",
              spread: Boolean(node.spread), checked: node.checked ?? null,
            });
            state.next(node.children).closeNode();
          },
        },
        toMarkdown: {
          ...schema.toMarkdown,
          runner: (state, node) => {
            state.openNode("listItem", undefined, { spread: node.attrs.spread, checked: node.attrs.checked });
            state.next(node.content).closeNode();
          },
        },
      };
    }));
    this.editor.use($prose(() => new Plugin({
      state: {
        init: (_, state) => imageDecorations(state.doc),
        apply: (transaction, decorations) => transaction.docChanged ? imageDecorations(transaction.doc) : decorations,
      },
      props: { decorations(state) { return this.getState(state); } },
    })));
    function imageDecorations(doc) {
      const decorations = [];
      const positions = new Map();
      doc.descendants((node, position) => {
        if (!node.isText) return;
        for (const item of htmlTokens) {
          const offset = node.text.indexOf(item.token);
          if (offset >= 0) {
            positions.set(item.token, { from: position + offset, to: position + offset + item.token.length });
            decorations.push(Decoration.inline(position + offset, position + offset + item.token.length, {
              class: "markdown-html-token", "aria-hidden": "true",
            }));
          }
        }
        for (const image of htmlImages) {
          const offset = node.text.indexOf(image.token);
          if (offset < 0) continue;
          decorations.push(Decoration.widget(position + offset + image.token.length, () => {
            const dom = document.createElement("img");
            const resolved = resolveImage(image.src);
            if (resolved.url) dom.src = resolved.url;
            dom.alt = image.alt;
            const width = image.width || (image.height && resolved.width && resolved.height
              ? Math.round(image.height * resolved.width / resolved.height) : resolved.width);
            const height = image.height || (image.width && resolved.width && resolved.height
              ? Math.round(image.width * resolved.height / resolved.width) : resolved.height);
            if (width) dom.width = width;
            if (height) dom.height = height;
            return dom;
          }, { ignoreSelection: true, key: image.key }));
        }
      });
      const stack = [];
      for (const item of htmlTokens) {
        const position = positions.get(item.token);
        if (!position) continue;
        const open = item.html.match(/^<(a|b|strong|i|em|s|del|u|code)(?=\s|>)/i);
        const close = item.html.match(/^<\/(a|b|strong|i|em|s|del|u|code)\s*>$/i);
        if (open) {
          const tag = open[1].toLowerCase();
          let href;
          if (tag === "a") {
            const template = document.createElement("template");
            template.innerHTML = item.html;
            href = template.content.querySelector("a")?.getAttribute("href");
            try { if (!href || !["http:", "https:", "mailto:"].includes(new URL(href, document.baseURI).protocol)) href = null; }
            catch { href = null; }
          }
          stack.push({ tag, start: position.to, href });
        } else if (close) {
          const itemIndex = stack.findLastIndex(entry => entry.tag === close[1].toLowerCase());
          if (itemIndex < 0) continue;
          const entry = stack.splice(itemIndex, 1)[0];
          if (entry.start < position.from && (entry.tag !== "a" || entry.href)) {
            decorations.push(Decoration.inline(entry.start, position.from, {
              nodeName: entry.tag, ...(entry.href ? { href: entry.href } : {}),
            }));
          }
        }
      }
      return DecorationSet.create(doc, decorations);
    }
    this.editor.config(ctx => ctx.update(editorViewOptionsCtx, current => ({
      ...current,
      nodeViews: {
        ...current.nodeViews,
        image(node) {
          const image = document.createElement("img");
          const update = value => {
            if (value.type.name !== "image") return false;
            const resolved = resolveImage(value.attrs.src);
            if (resolved.url) image.src = resolved.url; else image.removeAttribute("src");
            image.alt = value.attrs.alt || "";
            if (value.attrs.title) image.title = value.attrs.title; else image.removeAttribute("title");
            if (resolved.width && resolved.height) {
              image.width = resolved.width;
              image.height = resolved.height;
            } else {
              image.removeAttribute("width");
              image.removeAttribute("height");
            }
            return true;
          };
          update(node);
          return { dom: image, update, ignoreMutation: () => true };
        },
      },
    })));
  }
};
