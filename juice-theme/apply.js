#!/usr/bin/env node
/**
 * Installs the Break It / Build It theme into Juice Shop's built frontend.
 * frontend/dist is gitignored build output (like build/ that Build-It patches),
 * so the OWASP sources stay untouched and no Angular rebuild is needed.
 *
 * Usage:
 *   node juice-theme/apply.js            install or update (safe to run again)
 *   node juice-theme/apply.js --remove   back to the stock look
 *   JUICE_ROOT=/path/to/juice-shop node juice-theme/apply.js
 *
 * Re-run after any `npm install` / frontend rebuild in juice-shop, which recreates dist.
 */
const fs = require('fs')
const path = require('path')

const ROOT = process.env.JUICE_ROOT || path.join(__dirname, '..', 'juice-shop')
const DIST = path.join(ROOT, 'frontend', 'dist', 'frontend')
const INDEX = path.join(DIST, 'index.html')
const DEST = path.join(DIST, 'assets', 'bib')
const START = '<!-- bib:start -->'
const END = '<!-- bib:end -->'
const OLD_BLOCK = new RegExp(`${START}[\\s\\S]*?${END}\\n?`)

if (!fs.existsSync(INDEX)) {
  console.error(`No built frontend at ${INDEX}. Install/build Juice Shop first.`)
  process.exit(1)
}
const html = fs.readFileSync(INDEX, 'utf8').replace(OLD_BLOCK, '')

if (process.argv.includes('--remove')) {
  fs.rmSync(DEST, { recursive: true, force: true })
  fs.writeFileSync(INDEX, html)
  console.log('Theme removed. Reload Juice Shop.')
  process.exit(0)
}

if (!html.includes('</body>')) {
  console.error(`${INDEX} has no </body>; not touching it.`)
  process.exit(1)
}
fs.mkdirSync(DEST, { recursive: true })
for (const f of ['bib.css', 'bib.js']) fs.copyFileSync(path.join(__dirname, f), path.join(DEST, f))

// Last in the body so it wins ties with Angular's component styles; ?v busts the cache on re-apply.
const v = Date.now()
const block = `${START}
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Geist:wght@400;500;600;700&family=JetBrains+Mono:wght@400;500;700;800&display=swap">
<link rel="stylesheet" href="assets/bib/bib.css?v=${v}">
<script src="assets/bib/bib.js?v=${v}" defer></script>
${END}
`
fs.writeFileSync(INDEX, html.replace('</body>', block + '</body>'))
console.log(`Theme applied to ${DIST}. Reload Juice Shop.`)
