/* Break It / Build It — theme layer for OWASP Juice Shop v20.1.1.
   Decoration only: it adds its own elements beside Angular's and never touches bindings.
   The one edit to Angular's text is the currency sign ("1.99¤" → "$1.99"), so every
   intended vulnerability behaves as stock. */
(() => {
  'use strict'
  const doc = document
  const body = doc.body
  const reduced = matchMedia('(prefers-reduced-motion: reduce)').matches
  const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]))
  const el = (tag, cls, html) => { const e = doc.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e }
  const paused = () => body.classList.contains('bib-paused')
  const moving = () => !reduced && !paused() && !doc.hidden
  const safe = fn => (...a) => { try { return fn(...a) } catch (e) { console.warn('[bib]', e) } }
  const money = n => '$' + Number(n).toLocaleString('en-US', { maximumFractionDigits: 2 })

  // ── Dollars: Juice Shop hard-codes "¤" after prices in its templates ─────
  // Angular only rewrites a text node when its value changes, so a one-off swap sticks;
  // when a price does change (basket total), the observer swaps the new text too.
  // Stock totals can read "6.859999999999999¤" (float sums); show cents.
  const cents = n => /\.\d{3,}/.test(n) ? Number(n.replace(/,/g, '')).toFixed(2) : n
  const toDollars = s => s.replace(/(\d[\d,]*(?:\.\d+)?)\s*¤/g, (_, n) => '$' + cents(n)).replace(/¤/g, '$')
  const swapText = node => { const v = node.nodeValue; if (v && v.includes('¤')) node.nodeValue = toDollars(v) }
  const swapTree = root => {
    if (root.nodeType === 3) return swapText(root)
    const walk = doc.createTreeWalker(root, NodeFilter.SHOW_TEXT)
    for (let n = walk.nextNode(); n; n = walk.nextNode()) swapText(n)
  }
  swapTree(body)
  new MutationObserver(safe(muts => {
    for (const m of muts) {
      if (m.type === 'characterData') swapText(m.target)
      else for (const n of m.addedNodes) swapTree(n)
    }
  })).observe(body, { childList: true, subtree: true, characterData: true })

  // Characters roll through junk before settling (cancels any roll already running on node).
  function scramble (node, word) {
    const tok = node._bibTok = {}
    if (!moving()) { node.textContent = word; return }
    const junk = '!<>-_\\/[]{}=+*^?#01'
    let f = 0
    const tick = () => {
      if (node._bibTok !== tok) return
      node.textContent = [...word].map((c, i) => c === ' ' || i < f / 2 ? c : junk[(Math.random() * junk.length) | 0]).join('')
      if (f++ < word.length * 2) requestAnimationFrame(tick); else node.textContent = word
    }
    tick()
  }

  // A text slot that cycles through words while motion is allowed.
  function cycler (node, words, ms) {
    let i = 0, timer = 0
    node.textContent = words[0]; node.dataset.text = words[0]
    return () => {
      clearInterval(timer); timer = 0
      if (moving() && node.isConnected && !node.closest('[hidden]')) {
        timer = setInterval(() => { const w = words[++i % words.length]; node.dataset.text = w; scramble(node, w) }, ms)
      }
    }
  }

  // ── Announcement bar, with the one pause control for all theme motion ───
  const LINES = ['Free shipping on negative orders', '100% organic SQL', 'Now accepting alg: none', 'Disallow: /ftp (please don\'t look)',
    'Cold-pressed since 2014', 'Fri Nov 27 · Room S235 · ISS × GDG on Campus Sheridan']
  const bar = el('div', 'bib-bar',
    '<span class="bib-bar-tag" aria-hidden="true">&gt; break_it</span><span class="bib-bar-msg" aria-hidden="true"></span>' +
    '<button type="button" class="bib-pause" aria-pressed="false" aria-label="Pause theme animations">❚❚</button>')
  body.appendChild(bar)
  const barRun = cycler(bar.querySelector('.bib-bar-msg'), LINES, 3600)
  const pauseBtn = bar.querySelector('.bib-pause')
  pauseBtn.addEventListener('click', () => {
    const on = body.classList.toggle('bib-paused')
    pauseBtn.setAttribute('aria-pressed', on)
    pauseBtn.setAttribute('aria-label', on ? 'Play theme animations' : 'Pause theme animations')
    pauseBtn.textContent = on ? '▶' : '❚❚'
    sync()
  })

  // ── Every solved challenge gets the deck's "> break_it" moment ──────────
  const flash = el('div', 'bib-flash', '<span class="bib-flash-word bib-glitch" data-text="> break_it">&gt; break_it</span><span class="bib-flash-sub"></span>')
  flash.setAttribute('aria-hidden', 'true')
  body.appendChild(flash)
  flash.addEventListener('animationend', e => { if (e.target === flash) flash.classList.remove('go') })
  function hackFlash (card) {
    if (reduced || paused()) return
    const m = /challenge:\s*([^(]+?)\s*\(/.exec(card.textContent || '')
    flash.querySelector('.bib-flash-sub').textContent = m ? `challenge solved: ${m[1]}` : 'challenge solved'
    flash.classList.remove('go'); void flash.offsetWidth; flash.classList.add('go')
  }
  new MutationObserver(safe(muts => {
    for (const m of muts) {
      for (const n of m.addedNodes) {
        if (n.nodeType !== 1) continue
        const card = n.matches('app-challenge-solved-notification .mat-mdc-card') ? n : n.querySelector('app-challenge-solved-notification .mat-mdc-card, .challenge-solved-toast .mat-mdc-card')
        // Angular fills the text after inserting the node.
        if (card) setTimeout(() => hackFlash(card), 120)
      }
    }
  })).observe(doc.querySelector('app-root') || body, { childList: true, subtree: true })

  // ── Home: drop hero with three real products, then trending searches ────
  const home = (() => {
    // Real catalogue items; the tag only says what is true of them.
    const PICKS = [{ id: 19, q: 'Hoodie' }, { id: 41, q: 'Permafrost', tag: 'most expensive' }, { id: 1, q: 'Apple Juice' }]
    const TRENDING = ['Apple', 'Smoothie', 'Sticker', 'Melon', 'Shirt', 'Lemon']
    const WORDS = ['Leaky checkout.', 'Open baskets.', 'Free refunds.', 'Wide-open login.']
    let root = null, kinRun = () => {}, tries = 0

    function build () {
      root = el('section', 'bib-home', `
        <div class="bib-hero">
          <div>
            <p class="bib-eyebrow"><i aria-hidden="true"></i><b>&gt; break_it</b> fall '26 drop</p>
            <h2 class="bib-h1">Fresh juice.<span class="bib-kinetic bib-glitch" aria-hidden="true"></span></h2>
            <p class="bib-lede">OWASP's famously insecure juice shop, restocked for tonight's workshop. Browse it like a customer, then break it like an attacker.</p>
            <div class="bib-ctas">
              <button type="button" class="bib-btn solid" data-scroll>Shop all products ↓</button>
              <a class="bib-btn ghost" href="#/login">Log in →</a>
            </div>
            <ul class="bib-meta"><li data-count></li><li data-range></li><li data-version></li></ul>
          </div>
          <div class="bib-stack" aria-label="Featured products"></div>
        </div>
        <nav class="bib-trending" aria-label="Trending searches"><span>Trending</span>${TRENDING.map(t => `<a class="bib-chip" href="#/search?q=${encodeURIComponent(t)}">${esc(t)}</a>`).join('')}</nav>`)
      kinRun = cycler(root.querySelector('.bib-kinetic'), WORDS, 2800)
      root.querySelector('[data-scroll]').addEventListener('click', () => {
        const t = doc.querySelector('app-search-result .heading')
        if (t) t.scrollIntoView({ behavior: reduced ? 'auto' : 'smooth', block: 'start' })
      })
      load()
    }

    async function load () {
      try {
        const [pr, vr] = await Promise.all([fetch('/rest/products/search?q='), fetch('/rest/admin/application-version')])
        const products = (await pr.json()).data || []
        const v = await vr.json().catch(() => ({}))
        const prices = products.map(p => Number(p.price) || 0)
        root.querySelector('[data-count]').innerHTML = `<b>${products.length}</b> products`
        if (prices.length) root.querySelector('[data-range]').innerHTML = `from <b>${money(Math.min(...prices))}</b> to <b>${money(Math.max(...prices))}</b>`
        if (v.version) root.querySelector('[data-version]').innerHTML = `Juice Shop <b>v${esc(v.version)}</b>`
        root.querySelector('.bib-stack').innerHTML = PICKS.map(k => {
          const p = products.find(x => x.id === k.id)
          return p ? `<a class="bib-pick" href="#/search?q=${encodeURIComponent(k.q)}">
            <span class="bib-pick-img"><img src="/assets/public/images/products/${encodeURIComponent(p.image)}" alt=""></span>
            ${k.tag ? `<span class="bib-pick-tag">${esc(k.tag)}</span>` : ''}
            <span class="bib-pick-name">${esc(p.name)}</span><span class="bib-pick-price">${money(p.price)}</span></a>` : ''
        }).join('')
      } catch (e) { console.warn('[bib] catalog', e) }
    }

    function toggle (on) {
      if (on) {
        // Under the solved-challenge banners, above the product grid.
        const content = doc.querySelector('mat-sidenav-content')
        const outlet = content && content.querySelector(':scope > router-outlet')
        if (!outlet) { if (tries++ < 60) setTimeout(() => toggle(isHome()), 200); return }
        if (!root) build()
        if (root.nextElementSibling !== outlet) outlet.before(root)
        root.hidden = false
      } else if (root) root.hidden = true
      kinRun()
    }
    return { toggle, run: () => kinRun() }
  })()

  function sync () { barRun(); home.run() }
  doc.addEventListener('visibilitychange', sync)

  // ── Route changes (Angular's hash routing uses pushState, which fires no event) ──
  // "All Products" lives at #/ and at #/search without a query (where login lands you).
  const isHome = () => {
    const [path, query = ''] = location.hash.replace(/^#\/?/, '').split('?')
    return path === '' || (path === 'search' && !new URLSearchParams(query).get('q'))
  }
  const onRoute = safe(() => home.toggle(isHome()))
  for (const m of ['pushState', 'replaceState']) {
    const orig = history[m]
    history[m] = function (...a) { const r = orig.apply(this, a); queueMicrotask(onRoute); return r }
  }
  addEventListener('popstate', onRoute)
  addEventListener('hashchange', onRoute)

  // ── Boot screen, once per browser session ───────────────────────────────
  function boot () {
    if (reduced || sessionStorage.getItem('bib-booted')) return
    sessionStorage.setItem('bib-booted', '1')
    const b = el('div', 'bib-boot', '<div class="bib-term"><div class="bib-term-bar"><i></i><i></i><i></i><span>zsh — juice_shop</span></div><div class="bib-boot-line"></div></div>')
    b.setAttribute('aria-hidden', 'true')
    body.appendChild(b)
    const line = b.querySelector('.bib-boot-line'), cmd = "> ./juice_shop --edition fall26"
    let i = 0, done = false
    const typing = setInterval(() => { line.textContent = cmd.slice(0, ++i); if (i >= cmd.length) clearInterval(typing) }, 22)
    const finish = () => { if (done) return; done = true; clearInterval(typing); b.classList.add('out'); setTimeout(() => b.remove(), 600) }
    setTimeout(() => { if (done) return; line.classList.add('big'); line.innerHTML = '<span class="bib-glitch" data-text="&gt; break_it">&gt; break_it</span><i class="bib-block"></i>' }, 950)
    setTimeout(finish, 2000)
    b.addEventListener('click', finish)
    addEventListener('keydown', finish, { once: true })
  }

  boot()
  barRun()
  onRoute()
})()
