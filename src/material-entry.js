// JerryManager Material Web entry point.
//
// This imports the full @material/web package rather than
// hand-picking individual components. Vite's own tree-shaking
// during `npm run build` already drops anything genuinely unused
// by the WebUI, without the risk of manually guessing which
// components matter (icon-font rendering, dialog internals, etc.
// can silently depend on things that aren't obvious from a grep).
//
// If you know Jerry/webroot/index.html only uses a handful of
// components, you can narrow these imports later — just test
// thoroughly (icons, switches, dialogs, cards, ripples) before
// shipping a trimmed build.

import '@material/web/all.js';
import '@material/web/typography/md-typescale-styles.js';
