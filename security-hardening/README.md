# Interactive security hardening wizard

Interactive, idempotent Bash hardening for Ubuntu servers. Every mutable step verifies the current state, describes the risk and proposed change, asks `Apply this hardening? (Y/n)`, creates backups, validates the affected service, and rolls back configuration files when validation fails.

## Covered checks

- Plaintext credential locations and unsafe `.env` permissions
- Global nginx blocking of hidden files such as `.env` and `.git`
- nginx TLS 1.0/1.1 removal and `server_tokens off`
- Certbot timer and renewal dry-run
- SSH key-only authentication safeguards
- UFW state with current SSH-port preservation
- Fail2ban SSH jail
- Conservative sysctl hardening compatible with Docker networking
- Report-only Docker privilege, host-network, PID-mode, user and mount review

The script does not rotate credentials, delete files, force-renew certificates, remove PHP versions, rewrite Compose projects, or automatically add application-specific headers such as CSP/HSTS. Those require project-specific validation.

## Recommended execution

Downloading and reviewing before execution is safer than piping mutable remote code directly into a root shell:

```bash
curl -fsSLo /tmp/security-hardening.sh \
  https://raw.githubusercontent.com/mnofresno/scripting-tools/master/security-hardening/security-hardening.sh
less /tmp/security-hardening.sh
sudo bash /tmp/security-hardening.sh
```

## Direct execution

After reviewing the exact immutable commit, it can be executed with:

```bash
curl -fsSL https://raw.githubusercontent.com/mnofresno/scripting-tools/COMMIT_SHA/security-hardening/security-hardening.sh | sudo bash
```

Replace `COMMIT_SHA` with a reviewed commit SHA. Do not use a moving branch such as `master` in a `curl | sudo bash` command.

## Files written

- Log: `/var/log/security-hardening.log`
- Backups: `/var/backups/security-hardening/<UTC-run-id>/`
- Optional managed configuration:
  - `/etc/nginx/conf.d/00-security-hidden-files.conf`
  - `/etc/nginx/conf.d/00-security-server-tokens.conf`
  - `/etc/ssh/sshd_config.d/90-security-hardening.conf`
  - `/etc/fail2ban/jail.d/sshd.local`
  - `/etc/sysctl.d/90-security-hardening.conf`
