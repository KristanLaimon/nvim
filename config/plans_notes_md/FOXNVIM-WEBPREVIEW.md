Best approaches for a 100% browser-based Foxnvim demo
There are two legitimate ways to accomplish this without a backend. Both can be delivered through static hosting such as GitHub Pages.










1. WebVM — best chance of preserving your configuration

Runs a Linux environment entirely client-side using WebAssembly-based x86 virtualization. Visitors can execute native Neovim and its compatible plugins, with no remote shell. 
GitHub














2. nvim-wasm — best for a lightweight editor showcase

Runs Neovim itself as WebAssembly rather than emulating Linux. Supports a browser-native interface, but your configuration would need compatibility changes and some features would be unavailable. 
GitHub




The key distinction is that WASM Neovim is not yet equivalent to desktop Neovim. Your current repository lists 20 external dependencies and 71 local plugin specifications, including native-dependent features such as Tree-sitter, Blink completion, LSPs, DAP and external Git tooling. 
GitHub


For a demo that genuinely demonstrates what Foxnvim feels like, WebVM is worth evaluating first.
How I would build it
GitHub Pages

HTML + JavaScript + static assets

WebVM / CheerpX

Client-side Linux execution

Neovim + Foxnvim

Preinstalled plugins + demo project

Browser memory and virtual filesystem

Every visitor gets an independent session


You would:
1. Fork WebVM.
2. Prepare a custom Linux filesystem image containing Foxnvim, compatible Neovim binaries, its pinned plugins and example source files.
3. Configure WebVM to start Neovim automatically rather than launching Bash.
4. Build the static site through GitHub Actions.
5. Publish the resulting assets to GitHub Pages.
WebVM already documents custom .ext2 images, Dockerfile-based image creation and GitHub Pages deployment. 
GitHub

The important technical obstacle
CheerpX currently supports 32-bit x86 binaries, not x86-64. Therefore, the Neovim binary and any native plugins must be compatible with that architecture. 
npm


For example, your Blink completion dependency has no official prebuilt Linux i686 fuzzy-matcher binary, but it supports a Lua fallback. 
Blink Completion (blink.cmp)


This means I would create a separate browser demo profile rather than modify your normal Foxnvim configuration.
-- Conceptual browser compatibility switch
vim.g.foxnvim_browser_demo = true


That profile could disable unsupported native dependencies and network-dependent features while preserving your dashboard, keymaps, colors, file navigation, editor interactions, and compatible plugins.

External tooling such as LSPs or formatters would work only when compatible binaries and the required process functionality are available in the browser environment.

There is also a licensing consideration: the WebVM application is open source, but CheerpX has its own proprietary licensing terms. Personal and open-source use is generally permitted; verify that your intended public deployment complies with those terms. 
npm+1

An alternative without proprietary virtualization
If you want the entire implementation to be open source, investigate v86. It emulates an x86 computer inside the browser, and its core is licensed under BSD-2-Clause. However, it also has 32-bit architectural constraints and adds emulation overhead. 
GitHub

What I would prototype first
I'd test WebVM + a 32-bit build of Neovim 0.12.4 + Foxnvim's dashboard, without loading every plugin. This determines whether the interface works before investing in full plugin compatibility.

The final experience would be a README button:
Try Foxnvim Online

No installation · No account · Runs locally in your browser


An interactive editor with sample code, a resettable workspace, and the Foxnvim interface.

Bottom line: A genuine browser-only demo is feasible, but I can't promise your complete current configuration will work unchanged. WebVM offers the strongest starting point for native-tool compatibility; nvim-wasm is more lightweight and more experimental.

For Foxnvim specifically, I would prioritize preserving the actual editor UI and navigation experience over reproducing every development tool.

















YES, i love WebVM













Then I think we've found the right foundation for Foxnvim Online! 🦊

The coolest part is that we can make it a real, interactive Neovim environment—not a simulation—and host it as a static website.
Foxnvim Web

Proposed project

Browser — GitHub Pages


WebVM + CheerpX


Real Neovim + Foxnvim


Sample projects and code


No backend


No installation


No login


Resettable demo




How I'd start
1. Fork WebVM into a separate foxnvim-web repository.
2. Create a custom Debian i386 image containing Neovim, your Foxnvim configuration and preinstalled plugins.
3. Make Neovim launch automatically when someone opens the website.
4. Create a lightweight browser-specific profile for incompatible plugins.
5. Deploy through GitHub Actions to GitHub Pages.
WebVM already supports building custom Linux images from Dockerfiles and deploying them to GitHub Pages. 
GitHub

One challenge we should solve first
Your current Foxnvim requires Neovim 0.12.4 or newer, while CheerpX currently runs only 32-bit x86 binaries. 
GitHub+1


Our first milestone should therefore be getting a compatible 32-bit Neovim build running inside WebVM. Once that works, we can progressively enable your plugins.

I'd also keep the browser-specific code separate from your regular configuration so that supporting WebVM never compromises your desktop setup.

The final goal: someone clicks Try Foxnvim Online on your GitHub README and lands directly in your actual Neovim dashboard, ready to experiment.
