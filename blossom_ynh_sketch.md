# blossom_ynh — package sketch

Target: `imattau/nostr_catalog_ynh` (custom catalog).
Upstream: `github.com/hzrd149/blossom-server` (Deno 2, Hono, LibSQL).

Much simpler shape than gittr_ynh: one service, one runtime, one config file,
no dedicated SSH port, no dual-service split. Closer to packaging something
like Miniflux than Gitea.

---

## 1. Repo layout

```
blossom_ynh/
├── manifest.toml
├── conf/
│   ├── nginx.conf
│   ├── systemd.service
│   └── config.yml.j2
├── scripts/
│   ├── install
│   ├── remove
│   ├── upgrade
│   ├── backup
│   ├── restore
│   └── change_url
└── doc/
    └── DESCRIPTION.md
```

---

## 2. manifest.toml (skeleton)

```toml
packaging_format = 2

id = "blossom"
name = "Blossom Server"
description.en = "Self-hosted content-addressed blob storage server implementing the Blossom protocol for Nostr"

version = "0.1~ynh1"

maintainers = ["imattau"]

[upstream]
license = "MIT"
website = "https://github.com/hzrd149/blossom-server"
code = "https://github.com/hzrd149/blossom-server"

[integration]
yunohost = ">= 11.2"
architectures = "all"
multi_instance = true
ldap = false
sso = false
disk = "1G"
ram.build = "512M"
ram.runtime = "256M"

[install]
    [install.domain]
    type = "domain"

    [install.path]
    type = "path"
    default = "/"

    [install.admin]
    type = "user"

    [install.public_domain]
    type = "string"
    help.en = "Bare hostname this server is publicly reachable at (used in blob URLs, no https://). Usually same as the app domain."

    [install.enable_dashboard]
    type = "boolean"
    default = false
    help.en = "Enable the /admin dashboard. Password is auto-generated and logged on first start if left blank."

    [install.storage_backend]
    type = "select"
    choices = ["local", "s3"]
    default = "local"

    [install.max_upload_size]
    type = "number"
    default = 2147483648
    help.en = "Maximum upload size in bytes (default 2 GB)."

[resources]
    [resources.system_user]

    [resources.install_dir]

    [resources.ports]
        [resources.ports.main]
        default = 3000

    [resources.apt]
        packages = "ffmpeg"
        # ffmpeg needed for BUD-05 media transcode; sharp (image) ships via
        # deno.lock/npm deps, no separate apt package needed for that part

    [resources.data_dir]
        # holds blobs/ and sqlite.db — kept separate from install_dir so
        # backup/restore and upgrades don't churn user data
```

Notes vs gittr_ynh:
- `multi_instance = true` is realistic here — nothing about this app assumes
  it's the only one on the box, unlike gittr's SSH-port/authorized_keys
  entanglement.
- No `git_ssh_port` resource — pure HTTP service, nginx handles all routing.
- `ffmpeg` can go straight into `resources.apt` since it's a normal Debian
  package, unlike gittr's Go/Node build chain.

---

## 3. scripts/install (skeleton, abbreviated)

```bash
#!/bin/bash
source _common.sh
source /usr/share/yunohost/helpers

ynh_script_progression "Validating installation parameters"
# domain, path, admin, public_domain, enable_dashboard,
# storage_backend, max_upload_size resolved into env vars already

ynh_script_progression "Setting up source files"
ynh_setup_source --dest_dir="$install_dir"
# pin to a tagged release, not master — check releases page before first
# real packaging pass; repo shows tags but confirm a stable one exists

ynh_script_progression "Installing Deno runtime (pinned)"
DENO_VERSION="2.1.4"   # placeholder — verify current stable before use
ynh_setup_source --source_id="deno" --dest_dir="$install_dir/.deno"
# Deno ships as a single static binary per release on GitHub — this is
# simpler than gittr's Go+Node combo, one download, no toolchain build

ynh_script_progression "Building the landing page client bundle"
pushd "$install_dir"
  export DENO_DIR="$install_dir/.deno-cache"
  export PATH="$install_dir/.deno/bin:$PATH"
  deno task build
popd

ynh_script_progression "Writing configuration"
mkdir -p "$data_dir/blobs"
ynh_add_config --template="config.yml.j2" \
  --destination="$install_dir/config.yml"

if [ "$enable_dashboard" == "1" ]; then
  # password left blank on purpose — upstream auto-generates and logs it
  # to stdout on first start; capture that into the systemd journal and
  # surface it via `yunohost app info` or similar post-install note
  ynh_script_progression "Dashboard enabled — password will be in the service log on first start"
fi

ynh_script_progression "Configuring systemd service"
ynh_add_systemd_config --service="$app" --template="systemd.service"

ynh_script_progression "Configuring NGINX"
ynh_add_nginx_config

ynh_script_progression "Setting permissions"
chown -R "$app:$app" "$install_dir" "$data_dir"

ynh_script_progression "Enabling and starting service"
yunohost service add "$app" --description="Blossom blob storage server" \
  --log="/var/log/$app/$app.log"
ynh_systemd_action --service_name="$app" --action="start" \
  --log_path="systemd" --line_match="Listening"
```

Key differences from gittr's install script:
- One runtime to fetch (Deno static binary) instead of vendoring Go + Node
  and running two separate build steps.
- No `make` step, no `npm ci`, no separate Node install via
  `ynh_install_nodejs` — `deno task build` is the only build command.
- No SSH-specific permission dance (`chmod 700 .ssh`, dedicated non-login
  user warnings) — this app never touches `authorized_keys`.

---

## 4. conf/systemd.service (skeleton)

```ini
[Unit]
Description=Blossom Server — content-addressed blob storage for Nostr
After=network.target

[Service]
Type=simple
User=__APP__
Group=__APP__
WorkingDirectory=__INSTALL_DIR__
Environment=DENO_DIR=__INSTALL_DIR__/.deno-cache
ExecStart=__INSTALL_DIR__/.deno/bin/deno task start __INSTALL_DIR__/config.yml
Restart=on-failure
RestartSec=5

# hardening — this app has no reason to touch most of the filesystem
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=__DATA_DIR__
ProtectHome=true

[Install]
WantedBy=multi-user.target
```

Worth trying the `ProtectSystem=strict` + `ReadWritePaths` hardening here
since the app's own upstream NixOS module already runs it as a "hardened
systemd service" — good sign this app is well-behaved under sandboxing,
unlike anything needing broad filesystem or `authorized_keys` access.

---

## 5. conf/nginx.conf (skeleton)

```nginx
location __PATH__/ {
    proxy_pass http://127.0.0.1:__PORT__/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;

    # blob uploads can be large — match max_upload_size setting
    client_max_body_size __MAX_UPLOAD_SIZE_MB__m;

    # streaming uploads/downloads — avoid buffering large blobs
    proxy_request_buffering off;
    proxy_buffering off;
}
```

No separate SSH-port block needed, unlike gittr — this is the whole nginx
config.

---

## 6. conf/config.yml.j2 (skeleton)

```yaml
port: __PORT__
host: 127.0.0.1
publicDomain: __PUBLIC_DOMAIN__

database:
  path: __DATA_DIR__/sqlite.db

storage:
  backend: __STORAGE_BACKEND__
  local:
    dir: __DATA_DIR__/blobs

upload:
  enabled: true
  requireAuth: true
  maxSize: __MAX_UPLOAD_SIZE__
  workers: 0

mirror:
  enabled: true

delete:
  requireAuth: true

list:
  enabled: false

media:
  enabled: false   # flip on in config_panel later if ffmpeg present + wanted

report:
  enabled: true

landing:
  enabled: true
  title: "__APP_LABEL__"

dashboard:
  enabled: __ENABLE_DASHBOARD__
  username: __ADMIN_USERNAME__
  password: ""
  lookupRelays:
    - wss://purplepag.es
    - wss://index.hzrd149.com
```

If `storage_backend` is `s3`, a second template branch (or a post-install
`ynh_add_config` conditional block) would need to inject the `storage.s3`
section with endpoint/bucket/keys — probably worth exposing those as
`config_panel` fields post-install rather than at initial install time,
since S3 credentials are exactly the kind of thing better added via a
settings page than an install wizard prompt.

---

## 7. What's genuinely simpler here than gittr_ynh

- One language runtime, one build command, one systemd unit.
- No dedicated SSH-handling user, no `authorized_keys` risk.
- Sensible secure-by-default config already: `list.enabled: false`,
  `dashboard.enabled: false`, auth required on upload/delete.
- Retention rules (`storage.rules` with MIME-type globs and per-pubkey
  scoping) could become a nice `config_panel` section later, but aren't
  required for a first working package — sensible to leave unconfigured
  (unlimited retention) initially and add as a v2.

## Open questions before this is buildable for real

1. **Pin a release tag**, not `master` — check the repo's tags/releases
   page for the current stable version before writing the real
   `ynh_setup_source` manifest entry.
2. **Deno binary provenance.** Deno's official releases are GitHub release
   assets — check whether your network egress config allows fetching from
   `github.com`/`release-assets.githubusercontent.com` for the Deno binary
   itself (separate from your repo clone), since some sandboxed build
   environments restrict this.
3. **Dashboard password handoff.** Since the password is auto-generated and
   only logged to stdout, decide how the install script surfaces this to
   you post-install — reading it out of the systemd journal is workable,
   but worth deciding whether to script that into the install output
   directly (`journalctl -u $app -n 50 | grep -i password` sort of thing).
4. **S3 config UX.** Decide whether to support S3 backend in the initial
   `config_panel` or leave it local-only for v1 and add S3 as a later
   config_panel addition — avoids exposing secret fields in the install
   wizard.
5. **media.enabled toggle.** Since `ffmpeg` is now an apt dependency
   either way (needed for BUD-05), consider defaulting `media.enabled` to
   true rather than false, since the dependency cost is already paid.

Overall this is a much shorter path to a working package than gittr_ynh —
worth doing this one first, both because it's simpler and because it'd give
you a working Blossom server to pair with gittr's optional Blossom-backed
app blobs later, if you do end up packaging both.
