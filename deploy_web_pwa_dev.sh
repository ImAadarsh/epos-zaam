#!/usr/bin/env bash
# Build + deploy Zaam EPOS Flutter web/PWA DEV to the Zaam VPS.
#
# Site: https://epos-dev.zaamaitech.co.uk
# Edge: Traefik → static Express server on 127.0.0.1:4021 (PM2 zaam-epos-dev)
# API:  https://erp-api-dev.zaamaitech.co.uk (no /api suffix; the app adds /api/...)
#       Does NOT touch production zaam-epos / :4017 / epos.zaamaitech.co.uk
#
# Usage (from epos/):
#   ./deploy_web_pwa_dev.sh            build + deploy
#   SKIP_BUILD=1 ./deploy_web_pwa_dev.sh   redeploy the existing build/web
#
# SSH_HOST (required) and optional SSH_USER / SSH_KEY / overrides come from the
# environment or from a gitignored .deploy.env next to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# shellcheck disable=SC1091
[[ -f "$SCRIPT_DIR/.deploy.env" ]] && source "$SCRIPT_DIR/.deploy.env"

ssh_user="${SSH_USER:-root}"
ssh_host="${SSH_HOST:-}"
ssh_key="${SSH_KEY:-}"
app_dir="${APP_DIR:-/var/www/zaam-epos-dev}"
process_name="${PROCESS_NAME:-zaam-epos-dev}"
web_port="${PORT:-4021}"
domain="${WEB_DOMAIN:-epos-dev.zaamaitech.co.uk}"
traefik_dir="${TRAEFIK_DIR:-/docker/traefik-xtyj}"
api_base="${API_BASE_URL:-https://erp-api-dev.zaamaitech.co.uk}"
traefik_file="zaam-epos-dev.yml"

ssh_target="${ssh_user}@${ssh_host}"
ssh_base_opts=(-o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 -i "$ssh_key" -o IdentitiesOnly=yes -o BatchMode=yes)

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

[[ -n "$ssh_host" ]] || die "SSH_HOST not set (export it or add it to .deploy.env)"
[[ -n "$ssh_key" ]] || die "SSH_KEY not set (export it or add it to .deploy.env)"
[[ -f "$ssh_key" ]] || die "SSH key not found: ${ssh_key}"

remote() {
  ssh "${ssh_base_opts[@]}" "$ssh_target" "$@"
}

build_web() {
  command -v flutter >/dev/null 2>&1 || die "flutter not found on PATH"
  log "Building Flutter web DEV (API_BASE_URL=${api_base})…"
  flutter pub get
  flutter build web --release \
    --dart-define=API_BASE_URL="${api_base}" \
    --no-wasm-dry-run
  test -f build/web/index.html || die "build/web/index.html missing"
}

ensure_traefik_proxy() {
  # Only route hostnames whose DNS already points here, or Let's Encrypt fails the cert.
  local resolved
  resolved="$(dig +short "${domain}" A @8.8.8.8 | tail -1)"
  local target_dir="${traefik_dir}/dynamic"
  if [[ "${resolved}" != "${ssh_host}" ]]; then
    log "WARN: ${domain} resolves to '${resolved:-nothing}', not ${ssh_host} — staging the route only."
    target_dir="${traefik_dir}/dynamic-staged"
  fi
  log "Writing Traefik route ${target_dir}/${traefik_file} (https://${domain} → 127.0.0.1:${web_port})…"
  remote "set -euo pipefail
mkdir -p '${target_dir}'
cat > '${target_dir}/${traefik_file}' <<'YAML'
http:
  routers:
    zaam-epos-dev:
      rule: Host(\`${domain}\`)
      entryPoints:
        - websecure
      tls:
        certResolver: letsencrypt
      service: zaam-epos-dev
      priority: 10
    zaam-epos-dev-http:
      rule: Host(\`${domain}\`)
      entryPoints:
        - web
      middlewares:
        - zaam-epos-dev-https-redirect
      service: zaam-epos-dev
      priority: 10
  middlewares:
    zaam-epos-dev-https-redirect:
      redirectScheme:
        scheme: https
        permanent: true
  services:
    zaam-epos-dev:
      loadBalancer:
        servers:
          - url: http://127.0.0.1:${web_port}
YAML
grep -q 'Host(\`${domain}\`)' '${target_dir}/${traefik_file}' || { echo 'Host() rule is empty — heredoc expansion broke' >&2; exit 1; }
"
}

sync_files() {
  log "Syncing build/web → ${ssh_target}:${app_dir}/public/ …"
  remote "mkdir -p '${app_dir}/public'"
  rsync -az --delete \
    -e "ssh ${ssh_base_opts[*]}" \
    ./build/web/ "${ssh_target}:${app_dir}/public/"
}

ensure_static_server() {
  log "Writing static server + PM2 config on server (DEV)…"
  remote "set -euo pipefail
mkdir -p '${app_dir}'
cat > '${app_dir}/package.json' <<'EOF'
{
  \"name\": \"zaam-epos-dev\",
  \"private\": true,
  \"version\": \"1.0.0\",
  \"scripts\": {
    \"start\": \"node server.js\"
  },
  \"dependencies\": {
    \"express\": \"^4.21.2\"
  }
}
EOF
cat > '${app_dir}/server.js' <<'EOF'
const path = require('path');
const express = require('express');

const port = Number(process.env.PORT || 4021);
const host = process.env.HOST || '127.0.0.1';
const root = path.join(__dirname, 'public');
const app = express();

app.disable('x-powered-by');
app.use((req, res, next) => {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'strict-origin-when-cross-origin');
  next();
});

app.get('/healthz', (_req, res) => res.json({ status: 'ok' }));

app.use(express.static(root, {
  index: false,
  maxAge: '7d',
  setHeaders(res, filePath) {
    if (
      filePath.endsWith('index.html') ||
      filePath.endsWith('flutter_service_worker.js') ||
      filePath.endsWith('flutter_bootstrap.js') ||
      filePath.endsWith('version.json') ||
      filePath.endsWith('manifest.json')
    ) {
      res.setHeader('Cache-Control', 'no-cache');
    }
  },
}));

app.get('*', (_req, res) => {
  res.setHeader('Cache-Control', 'no-cache');
  res.sendFile(path.join(root, 'index.html'));
});

app.listen(port, host, () => {
  console.log('zaam-epos-dev listening on ' + host + ':' + port);
});
EOF
cat > '${app_dir}/ecosystem.config.cjs' <<EOF
module.exports = {
  apps: [{
    name: '${process_name}',
    cwd: '${app_dir}',
    script: 'server.js',
    instances: 1,
    exec_mode: 'fork',
    autorestart: true,
    max_memory_restart: '300M',
    time: true,
    env: {
      NODE_ENV: 'production',
      HOST: '127.0.0.1',
      PORT: '${web_port}',
    },
  }],
};
EOF
cd '${app_dir}'
npm install --omit=dev --no-audit --no-fund
if pm2 describe '${process_name}' >/dev/null 2>&1; then
  pm2 restart '${process_name}' --update-env
else
  pm2 start ecosystem.config.cjs
fi
pm2 save
"
}

health_checks() {
  log "Waiting for local static server on 127.0.0.1:${web_port}…"
  remote "set -e
for i in \$(seq 1 30); do
  code=\$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 'http://127.0.0.1:${web_port}/healthz' || echo 000)
  case \"\$code\" in
    200) echo \"Local healthz OK (HTTP \$code)\"; exit 0 ;;
  esac
  sleep 1
done
echo 'Local app failed to become ready' >&2
pm2 logs '${process_name}' --lines 40 --nostream || true
exit 1
"
  log "Checking public HTTPS https://${domain}/healthz …"
  local code=000
  for _ in $(seq 1 18); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 25 "https://${domain}/healthz" || echo 000)"
    [[ "$code" == "200" ]] && break
    sleep 5
  done
  if [[ "$code" == "200" ]]; then
    log "Public HTTPS OK (HTTP ${code})."
  else
    log "WARN: public HTTPS returned HTTP ${code} (cert may still be issuing, or DNS not yet pointed here)."
  fi
  log "PWA DEV deploy complete: https://${domain}"
  log "API base baked in: ${api_base}"
}

[[ "${1:-}" == "--help" ]] && { sed -n '2,14p' "$0"; exit 0; }

[[ "${SKIP_BUILD:-}" == "1" ]] || build_web
sync_files
ensure_static_server
ensure_traefik_proxy
health_checks
