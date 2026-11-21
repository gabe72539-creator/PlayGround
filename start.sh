#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(cd "$(dirname "$0")" && pwd)}"
PROJECT_DIR="$(/usr/bin/time -p realpath "$PROJECT_DIR")"
cd "$PROJECT_DIR"
PORT="${PORT:-3000}"
OUTPUT_DIR="${BUILD_OUTPUT_DIR:-$PROJECT_DIR/dist}"

if [[ -f "$PROJECT_DIR/package.json" ]]; then
  if [[ ! -d "$PROJECT_DIR/node_modules" ]]; then
    if [[ -f "$PROJECT_DIR/package-lock.json" ]]; then
      /usr/bin/time -p npm ci --no-audit --no-fund
    else
      /usr/bin/time -p npm install --no-audit --no-fund
    fi
  fi
  if node -e "process.exit(require('./package.json').scripts?.build ? 0 : 1)"; then
    /usr/bin/time -p npm run build
  fi
  if [[ ! -f "$OUTPUT_DIR/index.html" ]]; then
    for candidate in "$PROJECT_DIR/build" "$PROJECT_DIR/out" "$PROJECT_DIR/site"; do
      if [[ -f "$candidate/index.html" ]]; then OUTPUT_DIR="$candidate"; break; fi
    done
  fi
elif [[ -f "$PROJECT_DIR/index.html" ]]; then
  OUTPUT_DIR="$PROJECT_DIR/dist"
  /usr/bin/time -p mkdir -p "$OUTPUT_DIR"
  /usr/bin/time -p cp "$PROJECT_DIR/index.html" "$OUTPUT_DIR/index.html"
elif [[ ! -f "$OUTPUT_DIR/index.html" ]]; then
  # Keep a clean checkout launchable even before application source is provisioned.
  /usr/bin/time -p mkdir -p "$OUTPUT_DIR"
  /usr/bin/time -p tee "$OUTPUT_DIR/index.html" >/dev/null <<'HTML'
<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PlayGround · Preview</title>
<style>
:root{color-scheme:dark;font:16px/1.5 system-ui,sans-serif;background:#10131d;color:#f5f4ff}*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;padding:24px;background:radial-gradient(ellipse at 50% 35%,#33204c 0,transparent 55%),#10131d}.card{width:min(660px,100%);padding:clamp(28px,7vw,64px);border:1px solid #ffffff20;border-radius:28px;background:#171a28eF;box-shadow:0 30px 100px #0008}p{color:#c6bed7}.tag{display:inline-flex;padding:6px 12px;border:1px solid #bf8cff66;border-radius:99px;color:#d6b3ff;font-size:13px;letter-spacing:.08em;text-transform:uppercase}h1{font-size:clamp(36px,8vw,64px);line-height:1.04;margin:22px 0 14px;letter-spacing:-.05em}.status{display:flex;align-items:center;gap:10px;margin-top:30px;color:#b8f5d0}.dot{width:10px;height:10px;border-radius:50%;background:#53e89a;box-shadow:0 0 18px #53e89a}footer{margin-top:42px;color:#928ba4;font-size:13px}
</style></head><body><main class="card"><span class="tag">PlayGround · Preview</span><h1>Your playground is ready.</h1><p>The preview server is running and the page has rendered successfully. Add a project entry point to replace this setup screen.</p><div class="status"><span class="dot" aria-hidden="true"></span><span>Preview online</span></div><footer>Built output is served from this project directory.</footer></main></body></html>
HTML
fi

OUTPUT_DIR="$(/usr/bin/time -p realpath "$OUTPUT_DIR")"
case "$OUTPUT_DIR/" in "$PROJECT_DIR"/*) ;; *) echo "Build output must be inside PROJECT_DIR: $OUTPUT_DIR" >&2; exit 1 ;; esac
[[ -f "$OUTPUT_DIR/index.html" ]] || { echo "No built index.html found in $OUTPUT_DIR" >&2; exit 1; }
: "${OPENCODE_WEB_DIR:?OPENCODE_WEB_DIR is required for deployment metadata}"
/usr/bin/time -p mkdir -p "$OPENCODE_WEB_DIR"
PROJECT_DIR="$PROJECT_DIR" BUILT_DIR="$OUTPUT_DIR" /usr/bin/time -p node -e 'const fs=require("node:fs");fs.writeFileSync(process.env.OPENCODE_WEB_DIR+"/deployment-output.json",JSON.stringify({project:process.env.PROJECT_DIR,directory:process.env.BUILT_DIR}))'

/usr/bin/time -p node --input-type=module - "$OUTPUT_DIR" "$PORT" <<'NODE'
import { createServer } from 'node:http'
import { readFileSync, statSync } from 'node:fs'
import { extname, resolve, join } from 'node:path'
const root = resolve(process.argv[2]), port = Number(process.argv[3])
const types = { '.html':'text/html; charset=utf-8', '.css':'text/css; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.json':'application/json', '.svg':'image/svg+xml', '.png':'image/png', '.jpg':'image/jpeg' }
const server = createServer((req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname)
    const filePath = resolve(root, `.${pathname}`)
    if (filePath !== root && !filePath.startsWith(root + '/')) { res.writeHead(403); res.end('Forbidden'); return }
    const file = statSync(filePath).isDirectory() ? join(filePath, 'index.html') : filePath
    const data = readFileSync(file)
    res.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream', 'Cache-Control':'no-cache' })
    res.end(data)
  } catch { res.writeHead(404); res.end('Not found') }
})
server.listen(port, '0.0.0.0', () => console.log(`Serving ${root} on port ${port}`))
NODE
