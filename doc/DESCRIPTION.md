# Blossom Server for YunoHost

Blossom Server is a self-hosted, content-addressed blob store for Nostr. It
implements Blossom BUD-01, BUD-02, BUD-04, BUD-05, BUD-06, BUD-09, and BUD-11.

This package runs the upstream Deno application as a loopback-only service and
publishes it through YunoHost's NGINX reverse proxy. Local filesystem storage
and authenticated uploads/deletes are enabled by default; listing and the
admin dashboard are disabled by default.

The full install directory and application data under `data_dir` are included
in backups. `data_dir` is preserved when the app is removed; a YunoHost purge
is required to remove that data.

The package currently tracks upstream `v6.1.5`. Before publishing, fill in and
verify the source checksums in `manifest.toml`, then run the YunoHost package
lint and an install/upgrade/backup/restore test on supported architectures.
