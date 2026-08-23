#!/usr/bin/env node
// dsh-desktop gate — token-authenticated LAN front door for the harness web UI.
//
// Binds 0.0.0.0:<gatePort>, forwards every accepted request to the loopback
// harness server at 127.0.0.1:<upstreamPort>, and refuses everything that does
// not carry the pairing secret. First use rides a one-time pair code embedded
// in the QR URL (/pair/<code>): presenting it exchanges the code for a
// long-lived HttpOnly cookie; every later request must present that cookie
// (or an Authorization: Bearer <secret>). HTTP and WebSocket upgrades are both
// piped. The harness browser-trust fence stays authoritative behind the gate —
// the gate adds authentication, the fence keeps its confused-deputy defenses.

import http from 'node:http'
import crypto from 'node:crypto'

const {
  GATE_PORT,
  GATE_BIND = '0.0.0.0',
  UPSTREAM_PORT,
  PAIR_SECRET,        // long random hex; grants access via cookie/bearer
  PAIR_CODE,          // short one-time code embedded in the QR URL
} = process.env

for (const [name, value] of Object.entries({ GATE_PORT, UPSTREAM_PORT, PAIR_SECRET, PAIR_CODE })) {
  if (!value) {
    console.error(`gate: missing ${name}`)
    process.exit(1)
  }
}

const COOKIE_NAME = 'dsh_pair'
const upstreamOrigin = `http://127.0.0.1:${UPSTREAM_PORT}`
const safeEqual = (a, b) =>
  a.length === b.length && crypto.timingSafeEqual(Buffer.from(a), Buffer.from(b))

/**
 * Every credential the request carries: bearer token, cookie value, and any
 * one-time pair code from /pair/<code> or ?pair=<code>. All candidates are
 * evaluated — a stale cookie from an earlier gate generation must not shadow
 * the fresh pair code in the URL (cookies ignore ports, so every restart of
 * the app re-keys the secret under the same host).
 */
function presentedCandidates(req, url) {
  const candidates = []
  const auth = req.headers.authorization
  if (typeof auth === 'string' && auth.startsWith('Bearer ')) candidates.push(auth.slice(7))
  const cookies = req.headers.cookie ?? ''
  const match = cookies.split(/;\s*/).find(entry => entry.startsWith(`${COOKIE_NAME}=`))
  if (match) candidates.push(decodeURIComponent(match.slice(COOKIE_NAME.length + 1)))
  // One-time exchange: /pair/<code> may appear as the path or the hash-target
  // query (?pair=<code>) because phones preserve both across share sheets.
  const q = url.searchParams.get('pair')
  if (q) candidates.push(`code:${q}`)
  const pathMatch = /^\/pair\/([A-Za-z0-9_-]+)$/.exec(url.pathname)
  if (pathMatch) candidates.push(`code:${pathMatch[1]}`)
  return candidates
}

/** True when any candidate is the current one-time pair code. */
function hasValidPairCode(candidates) {
  return candidates.some(c => c.startsWith('code:') && safeEqual(c.slice(5), PAIR_CODE))
}

/** True when any candidate is the current durable secret. */
function hasValidSecret(candidates) {
  return candidates.some(c => !c.startsWith('code:') && safeEqual(c, PAIR_SECRET))
}

function grantCookie(res, secret) {
  res.setHeader('Set-Cookie',
    `${COOKIE_NAME}=${encodeURIComponent(secret)}; Path=/; HttpOnly; SameSite=Lax; Max-Age=${60 * 60 * 24 * 365}`)
}

/** Exchange a one-time pair code for the durable cookie; false when wrong. */
function consumePairCode(presented) {
  if (!presented?.startsWith('code:')) return false
  const code = presented.slice(5)
  if (!safeEqual(code, PAIR_CODE)) return false
  return true
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? '/', upstreamOrigin)
  const candidates = presentedCandidates(req, url)

  if (!hasValidPairCode(candidates) && !hasValidSecret(candidates)) {
    console.log(`${req.method} ${url.pathname}${url.search} -> 401 unpaired`)
    res.writeHead(401, { 'content-type': 'text/plain; charset=utf-8', 'cache-control': 'no-store' })
    res.end('DeepSeek Harness: paired device required.\nOpen the pairing QR link to sign in.')
    return
  }

  const headers = { ...req.headers }
  delete headers.cookie            // never leak pairing material upstream
  delete headers.authorization
  delete headers['accept-encoding'] // HTML polyfill injection needs identity bodies
  // The phone's Host (tailnet name/IP : gate port) fails the harness
  // browser-trust fence, which accepts loopback, LAN-literal, or explicitly
  // trusted authorities. Rewrite to the upstream authority so proxied
  // requests look like the loopback clients they effectively are. The fence
  // also compares Origin against Host when a browser attaches one — rewrite
  // it to the same authority or every POST from the phone is refused.
  headers.host = `127.0.0.1:${UPSTREAM_PORT}`
  if (headers.origin !== undefined) headers.origin = `http://127.0.0.1:${UPSTREAM_PORT}`

  if (hasValidPairCode(candidates)) {
    // Code accepted: set the durable cookie, then strip the code from the URL
    // so it leaves the browser history/address bar.
    console.log(`${req.method} ${url.pathname} -> 302 paired`)
    grantCookie(res, PAIR_SECRET)
    url.searchParams.delete('pair')
    url.pathname = '/'
    const target = url.pathname + url.search + url.hash
    res.writeHead(302, { location: target })
    res.end()
    return
  }

  const upstream = http.request(upstreamOrigin + url.pathname + url.search, {
    method: req.method,
    headers,
  })
  upstream.on('response', upstreamRes => {
    console.log(`${req.method} ${url.pathname} -> ${upstreamRes.statusCode ?? '?'} (upstream)`)
    const contentType = String(upstreamRes.headers['content-type'] ?? '')
    if (!contentType.includes('text/html')) {
      res.writeHead(upstreamRes.statusCode ?? 502, upstreamRes.headers)
      upstreamRes.pipe(res)
      return
    }
    // HTML over plain http lacks secure-context APIs the UI needs
    // (crypto.randomUUID); inject a fallback before the app boots. HTTPS
    // via tailscale serve has them natively and gets an untouched body.
    const chunks = []
    let size = 0
    upstreamRes.on('data', chunk => {
      size += chunk.length
      if (size <= 5 * 1024 * 1024) chunks.push(chunk)
    })
    upstreamRes.on('end', () => {
      let body = Buffer.concat(chunks).toString('utf8')
      if (size > 5 * 1024 * 1024) body = '' // oversized html: pass nothing rather than a broken page
      const polyfill = '<script>if(!window.crypto.randomUUID){window.crypto.randomUUID=function(){const b=window.crypto.getRandomValues(new Uint8Array(16));b[6]=(b[6]&15)|64;b[8]=(b[8]&63)|128;const h=Array.from(b,x=>x.toString(16).padStart(2,"0"));return h.slice(0,4).join("")+"-"+h.slice(4,6).join("")+"-"+h.slice(6,8).join("")+"-"+h.slice(8,10).join("")+"-"+h.slice(10).join("")}};</script>'
      if (body.includes('</head>')) {
        body = body.replace('</head>', polyfill + '</head>')
      } else {
        body = polyfill + body
      }
      const headers = { ...upstreamRes.headers }
      headers['content-length'] = String(Buffer.byteLength(body))
      delete headers['content-encoding'] // body was decompressed implicitly? no - only when upstream sent identity
      res.writeHead(upstreamRes.statusCode ?? 502, headers)
      res.end(body)
    })
  })
  upstream.on('error', error => {
    if (!res.headersSent) res.writeHead(502, { 'content-type': 'text/plain; charset=utf-8' })
    res.end(`gate: upstream unavailable: ${error.message}`)
  })
  req.pipe(upstream)
})

// WebSocket upgrades (the /api/events.mux stream) are raw socket pipes.
server.on('upgrade', (req, socket, head) => {
  const url = new URL(req.url ?? '/', upstreamOrigin)
  const candidates = presentedCandidates(req, url)
  if (!hasValidPairCode(candidates) && !hasValidSecret(candidates)) {
    socket.write('HTTP/1.1 401 Unauthorized\r\nconnection: close\r\n\r\n')
    socket.destroy()
    return
  }
  // Strip pairing material from the forwarded upgrade request and rewrite
  // Host/Origin to the upstream authority (same fence reasoning as HTTP).
  const { cookie: _c, authorization: _a, host: _h, origin: _o, ...forwardHeaders } = req.headers
  forwardHeaders.host = `127.0.0.1:${UPSTREAM_PORT}`
  forwardHeaders.origin = `http://127.0.0.1:${UPSTREAM_PORT}`
  const upstreamReq = http.request({
    host: '127.0.0.1',
    port: Number(UPSTREAM_PORT),
    method: req.method,
    path: req.url,
    headers: forwardHeaders,
  })
  upstreamReq.on('upgrade', (upstreamRes, upstreamSocket, upstreamHead) => {
    const lines = [`HTTP/1.1 ${upstreamRes.statusCode} ${upstreamRes.statusMessage}`]
    for (const [key, value] of Object.entries(upstreamRes.headers)) {
      if (value !== undefined) lines.push(`${key}: ${Array.isArray(value) ? value.join(', ') : value}`)
    }
    socket.write(lines.join('\r\n') + '\r\n\r\n')
    if (upstreamHead.length > 0) socket.write(upstreamHead)
    upstreamSocket.pipe(socket)
    socket.pipe(upstreamSocket)
    const closeBoth = () => { socket.destroy(); upstreamSocket.destroy() }
    socket.on('error', closeBoth); upstreamSocket.on('error', closeBoth)
    socket.on('close', closeBoth); upstreamSocket.on('close', closeBoth)
  })
  upstreamReq.on('response', response => {
    socket.write(`HTTP/1.1 ${response.statusCode} upstream refused upgrade\r\nconnection: close\r\n\r\n`)
    socket.destroy()
  })
  upstreamReq.on('error', () => socket.destroy())
  if (head.length > 0) upstreamReq.write(head)
  upstreamReq.end()
})

server.listen(Number(GATE_PORT), GATE_BIND, () => {
  console.log(`gate: listening on ${GATE_BIND}:${GATE_PORT} -> 127.0.0.1:${UPSTREAM_PORT}`)
})
