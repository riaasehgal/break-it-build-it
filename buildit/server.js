/**
 * Build-It Tool — Break It / Build It Workshop
 * ISS x GDG on Campus Sheridan — Nov 27, 2026
 *
 * Zero external dependencies — uses only Node built-ins.
 * Edits the compiled JS files in juice-shop/build/ directly,
 * so no TypeScript recompile is needed. nodemon restarts instantly.
 *
 * Usage:
 *   node server.js
 *   JUICE_ROOT=C:\path\to\juice-shop node server.js
 *
 * Default JUICE_ROOT: ..\juice-shop  (sibling of this folder)
 * Default PORT: 3100
 */

const http = require('http')
const fs   = require('fs')
const path = require('path')
const url  = require('url')

const JUICE_ROOT = process.env.JUICE_ROOT || path.join(__dirname, '..', 'juice-shop')
const PORT       = Number(process.env.PORT) || 3100
const PUBLIC_DIR = path.join(__dirname, 'public')

// ─── Vulnerability definitions ────────────────────────────────────────────────
// All `file` paths are inside build/ — compiled JS, no recompile needed.
// All `vulnerable` strings are verified present in the real v20.1.1 compiled output.

const VULNS = [
  {
    id: 'sqli',
    title: '1. SQL Injection — Admin Login Bypass',
    file: 'build/routes/login.js',
    explanation:
      'The login query concatenates user-supplied input directly into the SQL string.\n' +
      "An attacker can enter  ' OR 1=1--  in the email field to bypass authentication entirely\n" +
      'and log in as the first user in the database (the admin).\n\n' +
      'Fix: use Sequelize parameterised bindings (prepared statements) so user input\n' +
      'is never interpreted as SQL.',
    vulnerable:
      "models.sequelize.query(`SELECT * FROM Users WHERE email = '${req.body.email || ''}' AND password = '${security.hash(req.body.password || '')}' AND deletedAt IS NULL`, { model: user_1.UserModel, plain: true }) // vuln-code-snippet vuln-line loginAdminChallenge loginBenderChallenge loginJimChallenge",
    fixed:
      "models.sequelize.query('SELECT * FROM Users WHERE email = $1 AND password = $2 AND deletedAt IS NULL',\n" +
      '            { bind: [req.body.email, security.hash(req.body.password)], model: user_1.UserModel, plain: true }) // fixed: parameterised query'
  },
  {
    id: 'idor',
    title: '2. Broken Access Control — View Basket (IDOR)',
    file: 'build/routes/basket.js',
    explanation:
      'The basket endpoint accepts a basket ID from the URL and returns that basket\n' +
      "with no check that it belongs to the logged-in user.\n" +
      "An attacker can change the ID in the request to view anyone else's basket.\n\n" +
      "Fix: compare the requested basket ID against the authenticated user's own\n" +
      'basket ID server-side, and reject the request with 403 if they differ.',
    vulnerable:
      '            const id = req.params.id;\n' +
      '            const basket = await basket_1.BasketModel.findOne({ where: { id }, include: [{ model: product_1.ProductModel, paranoid: false, as: \'Products\' }] });',
    fixed:
      '            const id = req.params.id;\n' +
      '            const user = security.authenticatedUsers.from(req);\n' +
      '            if (!user || !user.bid || user.bid != parseInt(id, 10)) {\n' +
      "                res.status(403).json({ error: 'Forbidden' });\n" +
      '                return;\n' +
      '            }\n' +
      '            const basket = await basket_1.BasketModel.findOne({ where: { id }, include: [{ model: product_1.ProductModel, paranoid: false, as: \'Products\' }] });'
  },
  {
    id: 'ftp',
    title: '3. Information Disclosure — /ftp Exposed',
    file: 'build/server.js',
    explanation:
      'The /ftp directory is listed in robots.txt as disallowed — but that actually\n' +
      'advertises its existence to attackers. Worse, the route is fully accessible:\n' +
      'anyone can browse the directory listing and download sensitive files.\n\n' +
      'Fix: remove both routes that expose /ftp — the directory listing middleware\n' +
      'and the individual file-serving route.',
    vulnerable:
      "    app.use('/ftp', serveIndexMiddleware, (0, serve_index_1.default)('ftp', { icons: true })); // vuln-code-snippet vuln-line directoryListingChallenge\n" +
      "    app.use('/ftp(?!/quarantine)/:file', (0, fileServer_1.servePublicFiles)()); // vuln-code-snippet vuln-line directoryListingChallenge",
    fixed:
      '    // /ftp routes removed — directory listing and file download disabled'
  },
  {
    id: 'negqty',
    title: '5. Improper Input Validation — Negative Quantity Checkout',
    file: 'build/routes/basketItems.js',
    explanation:
      'The quantity check verifies stock levels and per-user limits but never confirms\n' +
      'that the quantity itself is positive.\n' +
      'An attacker can submit a negative quantity, which causes the total price to go\n' +
      'negative and effectively gives them store credit.\n\n' +
      'Fix: reject any quantity that is not a positive integer before the other checks.',
    vulnerable:
      '    // is product limited per user and order, except if user is deluxe?\n' +
      '    if (!product.limitPerUser || (product.limitPerUser && product.limitPerUser >= quantity) || security.isDeluxe(req)) {',
    fixed:
      '    if (!Number.isInteger(quantity) || quantity <= 0) {\n' +
      "        res.status(400).json({ error: 'Quantity must be a positive integer.' });\n" +
      '        return;\n' +
      '    }\n' +
      '    // is product limited per user and order, except if user is deluxe?\n' +
      '    if (!product.limitPerUser || (product.limitPerUser && product.limitPerUser >= quantity) || security.isDeluxe(req)) {'
  },
  {
    id: 'xss',
    title: '4. Cross-Site Scripting — DOM XSS',
    file: null, // frontend rebuild required — read-only entry
    explanation:
      'The search bar takes whatever you type and renders it as raw HTML in the page.\n' +
      'An attacker can type a script tag or iframe as the search term and the browser\n' +
      'will execute it — no server involved at all.\n\n' +
      'Vulnerable line (search-result.component.ts):\n' +
      '  this.searchValue = this.sanitizer.bypassSecurityTrustHtml(queryParam)\n\n' +
      'Fix — remove bypassSecurityTrustHtml, assign the string directly:\n' +
      '  this.searchValue = queryParam\n\n' +
      'Angular sanitizes [innerHTML] bindings automatically. The moment you stop\n' +
      'bypassing the sanitizer, script tags are stripped before they hit the DOM.\n\n' +
      'Note: this fix lives in the Angular frontend. Rebuilding it takes a few minutes,\n' +
      'so we show the fix here but do not demo it live.',
    vulnerable: null,
    fixed: null
  },
  {
    id: 'jwt',
    title: '6. Broken Authentication — JWT Forging (alg: none)',
    file: 'build/lib/insecurity.js',
    explanation:
      'The verify function uses the low-level  jws  library which accepts ANY algorithm\n' +
      'including  alg: none  — meaning no signature at all.\n' +
      'An attacker can craft a JWT with  "alg": "none"  and an arbitrary payload\n' +
      '(e.g. admin role) and the server will accept it as legitimate.\n\n' +
      "Fix: replace jws.verify with jsonwebtoken's jwt.verify and explicitly whitelist\n" +
      'only the RS256 algorithm, so tokens with any other algorithm are rejected.',
    vulnerable:
      'const verify = (token) => token ? jws_1.default.verify(token, exports.publicKey) : false;',
    fixed:
      'const verify = (token) => {\n' +
      '    if (!token) return false;\n' +
      '    try {\n' +
      "        return jsonwebtoken_1.default.verify(token, exports.publicKey, { algorithms: ['RS256'] });\n" +
      '    } catch {\n' +
      '        return false;\n' +
      '    }\n' +
      '};'
  }
]

// ─── Helpers ──────────────────────────────────────────────────────────────────
function readBody (req) {
  return new Promise((resolve, reject) => {
    const chunks = []
    req.on('data', c => chunks.push(c))
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
    req.on('error', reject)
  })
}

function sendJson (res, status, obj) {
  const body = JSON.stringify(obj)
  res.writeHead(status, { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) })
  res.end(body)
}

function serveFile (res, filePath) {
  const ext = path.extname(filePath).toLowerCase()
  const mime = { '.html': 'text/html', '.css': 'text/css', '.js': 'application/javascript' }
  try {
    const data = fs.readFileSync(filePath)
    res.writeHead(200, { 'Content-Type': mime[ext] || 'application/octet-stream' })
    res.end(data)
  } catch {
    res.writeHead(404); res.end('Not found')
  }
}

// ─── Router ───────────────────────────────────────────────────────────────────
const server = http.createServer(async (req, res) => {
  const parsed   = url.parse(req.url, true)
  const pathname = parsed.pathname

  // GET /api/vulns
  if (req.method === 'GET' && pathname === '/api/vulns') {
    return sendJson(res, 200, VULNS.map(v => ({ id: v.id, title: v.title })))
  }

  // GET /api/vulns/:id
  const detailMatch = pathname.match(/^\/api\/vulns\/([^/]+)$/)
  if (req.method === 'GET' && detailMatch) {
    const vuln = VULNS.find(v => v.id === detailMatch[1])
    if (!vuln) return sendJson(res, 404, { error: 'Not found' })
    if (!vuln.file) {
      return sendJson(res, 200, {
        id: vuln.id, title: vuln.title, file: null, explanation: vuln.explanation,
        vulnerable: null, fixed: null, isVulnerable: true, currentCode: null, readOnly: true
      })
    }
    const filePath = path.join(JUICE_ROOT, vuln.file)
    let fileContent = ''
    try { fileContent = fs.readFileSync(filePath, 'utf8') }
    catch (e) { return sendJson(res, 500, { error: `Cannot read ${vuln.file}: ${e.message}` }) }
    const isVulnerable = fileContent.includes(vuln.vulnerable)
    return sendJson(res, 200, {
      id: vuln.id, title: vuln.title, file: vuln.file, explanation: vuln.explanation,
      vulnerable: vuln.vulnerable, fixed: vuln.fixed, isVulnerable,
      currentCode: isVulnerable ? vuln.vulnerable : vuln.fixed, readOnly: false
    })
  }

  // POST /api/vulns/:id/save
  const saveMatch = pathname.match(/^\/api\/vulns\/([^/]+)\/save$/)
  if (req.method === 'POST' && saveMatch) {
    const vuln = VULNS.find(v => v.id === saveMatch[1])
    if (!vuln) return sendJson(res, 404, { error: 'Not found' })
    let body
    try { body = JSON.parse(await readBody(req)) }
    catch { return sendJson(res, 400, { error: 'Invalid JSON' }) }
    if (typeof body.code !== 'string') return sendJson(res, 400, { error: 'Missing code' })
    const filePath = path.join(JUICE_ROOT, vuln.file)
    let fileContent = ''
    try { fileContent = fs.readFileSync(filePath, 'utf8') }
    catch (e) { return sendJson(res, 500, { error: `Cannot read file: ${e.message}` }) }
    if (!fileContent.includes(vuln.vulnerable)) {
      return sendJson(res, 200, { status: 'already_fixed', message: 'File does not contain the vulnerable snippet — may already be patched.' })
    }
    try { fs.writeFileSync(filePath, fileContent.replace(vuln.vulnerable, body.code), 'utf8') }
    catch (e) { return sendJson(res, 500, { error: `Cannot write file: ${e.message}` }) }
    return sendJson(res, 200, { status: 'saved', message: `${vuln.file} updated. Juice Shop will restart in ~2 seconds.` })
  }

  // POST /api/vulns/:id/reset
  const resetMatch = pathname.match(/^\/api\/vulns\/([^/]+)\/reset$/)
  if (req.method === 'POST' && resetMatch) {
    const vuln = VULNS.find(v => v.id === resetMatch[1])
    if (!vuln) return sendJson(res, 404, { error: 'Not found' })
    const filePath = path.join(JUICE_ROOT, vuln.file)
    let fileContent = ''
    try { fileContent = fs.readFileSync(filePath, 'utf8') }
    catch (e) { return sendJson(res, 500, { error: `Cannot read file: ${e.message}` }) }
    if (fileContent.includes(vuln.vulnerable)) {
      return sendJson(res, 200, { status: 'already_vulnerable', message: 'File already contains the vulnerable code.' })
    }
    if (!fileContent.includes(vuln.fixed)) {
      return sendJson(res, 400, { error: 'Cannot find the fixed snippet to reverse — file may be in an unexpected state.' })
    }
    try { fs.writeFileSync(filePath, fileContent.replace(vuln.fixed, vuln.vulnerable), 'utf8') }
    catch (e) { return sendJson(res, 500, { error: `Cannot write file: ${e.message}` }) }
    return sendJson(res, 200, { status: 'reset', message: `${vuln.file} restored to vulnerable state. Juice Shop will restart in ~2 seconds.` })
  }

  // Static files
  if (req.method === 'GET') {
    const filePath = pathname === '/' ? path.join(PUBLIC_DIR, 'index.html') : path.join(PUBLIC_DIR, pathname)
    return serveFile(res, filePath)
  }

  res.writeHead(405); res.end('Method not allowed')
})

server.listen(PORT, () => {
  console.log(`\nBuild-It tool running at http://localhost:${PORT}`)
  console.log(`Juice Shop root: ${JUICE_ROOT}\n`)
})
