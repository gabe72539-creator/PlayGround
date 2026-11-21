#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
PROJECT_DIR="$(/usr/bin/time -p realpath "$PROJECT_DIR")"
: "${CAPTURE_URL:?Set CAPTURE_URL to the exact preview URL}"
: "${CAPTURE_DIR:?Set CAPTURE_DIR to an evidence directory outside the project}"
/usr/bin/time -p mkdir -p "$CAPTURE_DIR"
CAPTURE_DIR="$(/usr/bin/time -p realpath "$CAPTURE_DIR")"
case "$CAPTURE_DIR/" in "$PROJECT_DIR/"*) echo 'CAPTURE_DIR must be outside PROJECT_DIR.' >&2; exit 1 ;; esac

/usr/bin/time -p node --input-type=module - "$CAPTURE_URL" "$CAPTURE_DIR" <<'NODE'
import { createRequire } from 'node:module'
import { readFileSync } from 'node:fs'
import { join } from 'node:path'
const [url, output] = process.argv.slice(2)
try {
  const parsed = new URL(url)
  if (!['http:', 'https:'].includes(parsed.protocol)) throw new Error('CAPTURE_URL must use HTTP or HTTPS.')
} catch (error) { console.error(error.message); process.exit(1) }
const runtime = join(process.env.HOME, '.local/share/omgithub-playwright')
let browser
let exitCode = 0
const temporary = error => Object.assign(error instanceof Error ? error : new Error(String(error)), { exitCode: 75 })
try {
  const require = createRequire(join(runtime, 'package.json'))
  const { chromium } = require('playwright')
  const configPath = join(runtime, process.platform === 'darwin' ? 'metal.json' : 'linux.json')
  const config = JSON.parse(readFileSync(configPath, 'utf8'))
  if (process.platform === 'linux') process.env.DISPLAY ||= ':' + readFileSync(join(runtime, 'display'), 'utf8').trim()
  console.time('browser-launch')
  try { browser = await chromium.launch({ ...config.browser.launchOptions, timeout: 30000 }) }
  catch (error) { throw temporary(error) }
  finally { console.timeEnd('browser-launch') }

  for (const [name, width, height] of [['desktop', 1280, 800], ['mobile', 390, 844]]) {
    console.time(`capture-${name}`)
    let page
    try {
      page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: 1 })
      page.setDefaultTimeout(20000)
      const pageErrors = []
      page.on('pageerror', error => pageErrors.push(error.message))
      console.time(`navigation-${name}`)
      let response
      try { response = await page.goto(url, { waitUntil: 'load', timeout: 45000 }) }
      catch (error) { throw temporary(error) }
      finally { console.timeEnd(`navigation-${name}`) }
      if (!response) throw temporary(new Error(`No response while opening ${url}`))
      if (!response.ok()) {
        const status = response.status()
        const error = new Error(`Preview returned HTTP ${status}: ${url}`)
        throw Object.assign(error, { exitCode: status >= 500 || [408, 429].includes(status) ? 75 : 1 })
      }
      try {
        await page.locator(process.env.CAPTURE_READY_SELECTOR || 'body').waitFor({ state: 'visible', timeout: 20000 })
        await page.waitForFunction(() => {
          const body = document.body
          if (!body || !body.getBoundingClientRect().width || !body.getBoundingClientRect().height) return false
          const text = (body.innerText || '').trim()
          const visual = [...body.querySelectorAll('canvas,svg,img,video,[role="main"]')].some(element => {
            const rect = element.getBoundingClientRect(), style = getComputedStyle(element)
            return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none'
          })
          return text.length > 0 || visual
        }, { timeout: 20000 })
        await page.waitForFunction(() => document.fonts.status === 'loaded', { timeout: 10000 }).catch(() => {})
      } catch (error) { throw Object.assign(new Error(`Rendered content was not ready in ${name} view: ${error.message}`), { exitCode: 1 }) }
      await page.waitForTimeout(500)
      const destination = join(output, `final-${name}.png`)
      try { await page.screenshot({ path: destination, timeout: 30000 }) }
      catch (error) { throw Object.assign(error, { exitCode: error.name === 'TimeoutError' || !browser.isConnected() ? 75 : 1 }) }
      console.log(`Saved ${destination} (${width}x${height})`)
      if (pageErrors.length) throw new Error(`Page rendering errors: ${pageErrors.join('; ')}`)
    } catch (error) {
      console.error(error)
      exitCode = error.exitCode || 1
      break
    } finally {
      await page?.close().catch(error => { console.error(error); exitCode ||= 75 })
      console.timeEnd(`capture-${name}`)
    }
  }
} catch (error) {
  console.error(error)
  exitCode = error.exitCode || (error.code === 'ENOENT' ? 75 : 1)
} finally {
  await browser?.close().catch(error => { console.error(error); exitCode ||= 75 })
}
process.exitCode = exitCode
NODE
