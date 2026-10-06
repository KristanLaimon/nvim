# Taste

## Communication
- Communicates in Spanish and expects the agent's responses (including summaries and explanations) in Spanish. Confidence: 0.85

## Workflow
- Declines plan mode for feature work: prefers the agent to go straight to exploring and implementing rather than pausing for a planning step. Confidence: 0.55

## UI / Coding Style
- Wants UI element widths (e.g. a gutter/column) sized exactly to their content — the width of the longest item present — instead of arbitrary min/max constants or fixed padding. Confidence: 0.65
- Expects panels/columns that sit alongside the main buffer (gutters, side views) to stay perfectly scroll-synchronized with it; any drift or content appearing/disappearing during scrolling is treated as a bug to fix. Confidence: 0.6
- Expects backend/API errors to be caught and surfaced as a contextual inline message near the triggering control (e.g. above the "generate PDF" button) instead of letting the raw error message blow up on the page. Confidence: 0.6
