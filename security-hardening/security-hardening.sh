#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_NAME="security-hardening"
LOG_FILE="${LOG_FILE:-/var/log/security-hardening.log}"
BACKUP_ROOT="${BACKUP_ROOT:-/var/backups/security-hardening}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_BACKUP_DIR="${BACKUP_ROOT}/${RUN_ID}"
TOTAL=12
CURRENT=0
APPLIED=0
ALREADY=0
SKIPPED=0
FAILED=0

if [[ ${EUID} -ne 0 ]]; then
  printf 'Run as root: sudo %s\n' "$0" >&2
  exit 1
fi

mkdir -p "$RUN_BACKUP_DIR"
touch "$LOG_FILE"
chmod 0600 "$LOG_FILE"
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'printf "\nERROR at line %s while running: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }
line() { printf '%*s\n' 72 '' | tr ' ' '='; }

prompt_yes_no() {
  local answer
  while true; do
    read -r -p "Apply this hardening? (Y/n) " answer || answer=n
    answer="${answer:-Y}"
    case "$answer" in
      [Yy]|[Yy][Ee][Ss]) return 0 ;;
      [Nn]|[Nn][Oo]) return 1 ;;
      *) printf 'Answer Y or n.\n' ;;
    esac
  done
}

section() {
  CURRENT=$((CURRENT + 1))
  printf '\n'
  line
  printf '[%d/%d] %s\n' "$CURRENT" "$TOTAL" "$1"
  line
}

mark_already() { printf 'PASS: already enforced.\n'; ALREADY=$((ALREADY + 1)); }
mark_applied() { printf 'PASS: applied and verified.\n'; APPLIED=$((APPLIED + 1)); }
mark_skipped() { printf 'SKIPPED: no changes made.\n'; SKIPPED=$((SKIPPED + 1)); }
mark_failed() { printf 'FAIL: %s\n' "$1"; FAILED=$((FAILED + 1)); }

backup_file() {
  local file="$1" target
  [[ -e "$file" ]] || return 0
  target="${RUN_BACKUP_DIR}${file}"
  mkdir -p "$(dirname "$target")"
  cp -a -- "$file" "$target"
  log "Backup: $file -> $target"
}

restore_file() {
  local file="$1" source="${RUN_BACKUP_DIR}${file}"
  [[ -e "$source" ]] || return 1
  cp -a -- "$source" "$file"
  log "Rollback: restored $file"
}

show_diff() {
  local before="$1" after="$2"
  diff -u --label before --label after "$before" "$after" || true
}

atomic_replace() {
  local target="$1" candidate="$2"
  backup_file "$target"
  install -o "$(stat -c %U "$target")" -g "$(stat -c %G "$target")" -m "$(stat -c %a "$target")" "$candidate" "$target"
}

check_plaintext_secrets() {
  section "Plaintext credentials and dangerous sudo helper scripts"
  local hits
  hits="$(grep -RIlE --exclude-dir=.git --exclude='*.log' --exclude='security-hardening.sh' '(sshpass[[:space:]]+-p|OPENAI_API_KEY[[:space:]]*=|ANTHROPIC_API_KEY[[:space:]]*=|AWS_SECRET_ACCESS_KEY[[:space:]]*=|GITHUB_TOKEN[[:space:]]*=)' /home /var/www 2>/dev/null || true)"
  if [[ -z "$hits" ]]; then mark_already; return; fi
  printf 'Potential secrets were found in:\n%s\n\n' "$hits"
  printf 'Risk: local compromise, source-code disclosure, or an application RCE may expose credentials and can turn a user compromise into root access.\n'
  printf 'Proposed change: lock each listed regular file to mode 0600. This does not rotate or delete secrets; rotation remains mandatory.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    chmod 0600 "$file"
  done <<< "$hits"
  mark_applied
}

check_env_permissions() {
  section "Permissions on environment files"
  mapfile -t files < <(find /home /var/www -xdev -type f -name '.env' -perm /0077 2>/dev/null)
  if ((${#files[@]} == 0)); then mark_already; return; fi
  printf 'Environment files readable or writable by group/others:\n'
  stat -c '%a %U:%G %n' "${files[@]}"
  printf '\nProposed change: set mode 0600 while preserving owner and group.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  chmod 0600 "${files[@]}"
  if find "${files[@]}" -perm /0077 -print -quit | grep -q .; then mark_failed 'some .env permissions remain unsafe'; else mark_applied; fi
}

nginx_hidden_files() {
  section "Block hidden secret and repository files in nginx"
  command -v nginx >/dev/null 2>&1 || { printf 'nginx is not installed.\n'; mark_already; return; }
  local file='/etc/nginx/conf.d/00-security-hidden-files.conf'
  if [[ -f "$file" ]] && grep -q 'location ~ /\\\.' "$file"; then mark_already; return; fi
  printf 'Risk: a future or existing server block with an unsafe document root could expose .env, .git, keys, backups, or editor files.\n'
  printf 'Proposed change: add a global nginx include denying dotfiles, except ACME well-known paths.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  local candidate
  candidate="$(mktemp)"
  cat > "$candidate" <<'EOF'
# Managed by security-hardening.sh
location ~ /\.(?!well-known(?:/|$)) {
    deny all;
    access_log off;
    log_not_found off;
}
EOF
  backup_file "$file"
  install -o root -g root -m 0644 "$candidate" "$file"
  rm -f "$candidate"
  if nginx -t; then systemctl reload nginx; mark_applied; else restore_file "$file" || rm -f "$file"; nginx -t || true; mark_failed 'nginx validation failed; rolled back'; fi
}

nginx_tls() {
  section "Disable TLS 1.0 and TLS 1.1 in nginx"
  [[ -f /etc/nginx/nginx.conf ]] || { printf 'nginx.conf not found.\n'; mark_already; return; }
  if ! grep -RqsE 'ssl_protocols[^;]*(TLSv1[ ;]|TLSv1\.1)' /etc/nginx; then mark_already; return; fi
  printf 'Legacy TLS protocols are enabled in nginx configuration.\n'
  printf 'Proposed change: replace active ssl_protocols directives with TLSv1.2 TLSv1.3, after backups and nginx validation.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  mapfile -t files < <(grep -RlE 'ssl_protocols[^;]*(TLSv1[ ;]|TLSv1\.1)' /etc/nginx --include='*.conf' 2>/dev/null)
  local file temp failed=0
  for file in "${files[@]}"; do
    temp="$(mktemp)"
    perl -pe 'if (!/^\s*#/) { s/^([ \t]*ssl_protocols)[^;]*;/$1 TLSv1.2 TLSv1.3;/ }' "$file" > "$temp"
    cmp -s "$file" "$temp" && { rm -f "$temp"; continue; }
    backup_file "$file"
    show_diff "$file" "$temp"
    atomic_replace "$file" "$temp"
    rm -f "$temp"
  done
  if nginx -t; then systemctl reload nginx; mark_applied; else
    for file in "${files[@]}"; do restore_file "$file" || failed=1; done
    nginx -t || true
    mark_failed "nginx validation failed; rollback attempted (${failed})"
  fi
}

nginx_tokens() {
  section "Hide nginx version tokens"
  [[ -f /etc/nginx/nginx.conf ]] || { mark_already; return; }
  if nginx -T 2>/dev/null | grep -qE '^\s*server_tokens\s+off;'; then mark_already; return; fi
  printf 'Proposed change: add server_tokens off in the nginx http context.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  local file='/etc/nginx/conf.d/00-security-server-tokens.conf'
  backup_file "$file"
  printf '# Managed by security-hardening.sh\nserver_tokens off;\n' > "$file"
  chmod 0644 "$file"
  if nginx -t; then systemctl reload nginx; mark_applied; else restore_file "$file" || rm -f "$file"; mark_failed 'nginx validation failed; rolled back'; fi
}

certbot_timer() {
  section "Certificate renewal timer"
  command -v certbot >/dev/null 2>&1 || { printf 'certbot is not installed; no automatic installation will be attempted.\n'; mark_skipped; return; }
  if systemctl is-enabled --quiet certbot.timer && systemctl is-active --quiet certbot.timer; then mark_already; return; fi
  printf 'Proposed change: enable and start certbot.timer. No certificate will be force-renewed.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  systemctl enable --now certbot.timer
  systemctl is-active --quiet certbot.timer && mark_applied || mark_failed 'certbot.timer is not active'
}

certbot_dry_run() {
  section "Test certificate renewal"
  command -v certbot >/dev/null 2>&1 || { mark_skipped; return; }
  printf 'Proposed action: run certbot renew --dry-run. This performs a renewal simulation and should not replace certificates.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  if certbot renew --dry-run; then mark_applied; else mark_failed 'certbot dry-run failed; inspect output before forcing renewal'; fi
}

ssh_hardening() {
  section "SSH authentication hardening"
  command -v sshd >/dev/null 2>&1 || { mark_already; return; }
  local current
  current="$(sshd -T 2>/dev/null || true)"
  if grep -qx 'permitrootlogin no' <<< "$current" && grep -qx 'passwordauthentication no' <<< "$current" && grep -qx 'pubkeyauthentication yes' <<< "$current"; then mark_already; return; fi
  printf 'Proposed change: create an sshd drop-in enforcing root-login disabled, password authentication disabled, public-key authentication enabled, MaxAuthTries 4, LoginGraceTime 30.\n'
  printf 'Safety condition: at least one non-root authorized_keys file must exist before this option is offered.\n'
  if ! find /home -path '*/.ssh/authorized_keys' -type f -size +0c -print -quit | grep -q .; then mark_failed 'no non-root authorized_keys file detected; refusing to disable password authentication'; return; fi
  if ! prompt_yes_no; then mark_skipped; return; fi
  local file='/etc/ssh/sshd_config.d/90-security-hardening.conf'
  mkdir -p /etc/ssh/sshd_config.d
  backup_file "$file"
  cat > "$file" <<'EOF'
# Managed by security-hardening.sh
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 4
LoginGraceTime 30
EOF
  chmod 0644 "$file"
  if sshd -t; then systemctl reload ssh || systemctl reload sshd; mark_applied; else restore_file "$file" || rm -f "$file"; mark_failed 'sshd validation failed; rolled back'; fi
}

ufw_review() {
  section "Host firewall state"
  command -v ufw >/dev/null 2>&1 || { printf 'UFW is not installed. Automatic firewall installation is intentionally not performed.\n'; mark_skipped; return; }
  if ufw status | grep -q '^Status: active'; then printf 'UFW is active. Current policy:\n'; ufw status verbose; mark_already; return; fi
  printf 'UFW is inactive. Enabling a firewall remotely can lock out SSH.\n'
  printf 'Proposed change: detect the current SSH destination port, allow it, set deny incoming / allow outgoing, then enable UFW.\n'
  local ssh_port="${SSH_CONNECTION:+$(ss -tnp 2>/dev/null | awk -v peer="${SSH_CONNECTION%% *}" '$0 ~ peer {split($4,a,":"); print a[length(a)]; exit}')}"
  ssh_port="${ssh_port:-$(sshd -T 2>/dev/null | awk '$1=="port" {print $2; exit}')}"
  ssh_port="${ssh_port:-22}"
  printf 'Detected SSH port: %s\n' "$ssh_port"
  if ! prompt_yes_no; then mark_skipped; return; fi
  ufw allow "${ssh_port}/tcp"
  ufw default deny incoming
  ufw default allow outgoing
  ufw --force enable
  ufw status | grep -q '^Status: active' && mark_applied || mark_failed 'UFW did not become active'
}

fail2ban_install() {
  section "Fail2ban for SSH abuse"
  if command -v fail2ban-client >/dev/null 2>&1 && systemctl is-active --quiet fail2ban; then mark_already; return; fi
  printf 'Proposed change: install fail2ban from Ubuntu repositories and enable the sshd jail using systemd journal.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update
  apt-get install -y fail2ban
  backup_file /etc/fail2ban/jail.d/sshd.local
  cat > /etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled = true
backend = systemd
bantime = 1h
findtime = 10m
maxretry = 6
EOF
  fail2ban-client -t
  systemctl enable --now fail2ban
  fail2ban-client status sshd >/dev/null && mark_applied || mark_failed 'fail2ban sshd jail is unavailable'
}

kernel_hardening() {
  section "Conservative network kernel hardening"
  local file='/etc/sysctl.d/90-security-hardening.conf'
  local desired
  desired="$(cat <<'EOF'
# Managed by security-hardening.sh
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.tcp_syncookies = 1
kernel.randomize_va_space = 2
fs.suid_dumpable = 0
EOF
)"
  if [[ -f "$file" ]] && [[ "$(cat "$file")" == "$desired" ]]; then mark_already; return; fi
  printf 'Proposed change: disable ICMP redirects, enable SYN cookies and full ASLR, and disable setuid core dumps. IP forwarding and rp_filter are not changed because Docker/routing may depend on them.\n'
  if ! prompt_yes_no; then mark_skipped; return; fi
  backup_file "$file"
  printf '%s\n' "$desired" > "$file"
  chmod 0644 "$file"
  if sysctl --system; then mark_applied; else restore_file "$file" || rm -f "$file"; sysctl --system || true; mark_failed 'sysctl application failed; rolled back'; fi
}

docker_risk_report() {
  section "Docker privilege and host exposure review"
  command -v docker >/dev/null 2>&1 || { mark_already; return; }
  local report
  report="$(docker ps -q | xargs -r docker inspect --format '{{.Name}} privileged={{.HostConfig.Privileged}} network={{.HostConfig.NetworkMode}} pid={{.HostConfig.PidMode}} user={{.Config.User}} mounts={{range .Mounts}}{{.Source}}:{{.Destination}};{{end}}' 2>/dev/null || true)"
  if [[ -z "$report" ]]; then printf 'No running containers.\n'; mark_already; return; fi
  printf '%s\n' "$report"
  printf '\nThis step is report-only. Container hardening requires service-specific changes in Compose files; mutating running containers would not be persistent or safe.\n'
  mark_skipped
}

final_summary() {
  printf '\n'
  line
  printf 'SECURITY HARDENING SUMMARY\n'
  line
  printf 'Applied:          %d\n' "$APPLIED"
  printf 'Already correct:  %d\n' "$ALREADY"
  printf 'Skipped:          %d\n' "$SKIPPED"
  printf 'Failed:           %d\n' "$FAILED"
  printf 'Backups:          %s\n' "$RUN_BACKUP_DIR"
  printf 'Log:              %s\n' "$LOG_FILE"
  ((FAILED == 0))
}

main() {
  log "Starting $SCRIPT_NAME run $RUN_ID as ${SUDO_USER:-root}"
  check_plaintext_secrets
  check_env_permissions
  nginx_hidden_files
  nginx_tls
  nginx_tokens
  certbot_timer
  certbot_dry_run
  ssh_hardening
  ufw_review
  fail2ban_install
  kernel_hardening
  docker_risk_report
  final_summary
}

main "$@"
