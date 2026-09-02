#!/bin/bash

app="${YNH_APP_ID:-blossom}"
service_name="$app"

ynh_app_setting_get_or_default() {
	local key="$1" default="$2" value
	value="$(ynh_app_setting_get --app="$app" --key="$key" 2>/dev/null || true)"
	printf '%s' "${value:-$default}"
}

# Reads a scalar key out of the app's live config.yml, scoped strictly to
# the block between the $2 and $3 line patterns (both matched with
# extended regex; $3 empty means "to end of file"), falling back to $4 if
# the file doesn't exist yet (fresh install), the block doesn't exist yet
# (an upgrade from a package version older than the one that introduced
# it - the start pattern just never matches, so the block is empty), or
# the key isn't present within that block.
#
# Deliberately does NOT use ynh_read_var_in_file's own --after, which only
# bounds the start of its search and not the end: for a key genuinely
# absent from a section (e.g. old config.yml's "list:" had no
# requireAuth), it happily keeps scanning into later sections and returns
# an unrelated key's value instead of "not found" - which silently
# resurrects the wrong value instead of falling back to the default.
#
# Config-panel-bound fields are only ever persisted to config.yml, never
# to app settings, so this is the only way to read back an admin's
# existing customization before re-rendering the template - skipping this
# on upgrade would silently reset such fields to defaults every time a
# new field is added to the template.
blossom_config_get_or_default() {
	local key="$1" start="$2" end="$3" default="$4" val="" block
	if [ -f "$install_dir/config.yml" ]; then
		if [ -n "$start" ] && [ -n "$end" ]; then
			block="$(sed -n "/$start/,/$end/p" "$install_dir/config.yml")"
		elif [ -n "$start" ]; then
			block="$(sed -n "/$start/,\$p" "$install_dir/config.yml")"
		else
			block="$(cat "$install_dir/config.yml")"
		fi
		val="$(printf '%s\n' "$block" | grep -m1 -oP "^\s*${key}:\s*\K.*" || true)"
		val="${val%\"}"
		val="${val#\"}"
	fi
	if [ -z "$val" ]; then
		printf '%s' "$default"
	else
		printf '%s' "$val"
	fi
}

# Normalizes any of the truthy/falsy string forms YunoHost boolean
# questions may carry ("1"/"0", "true"/"false", "yes"/"no", ...) into the
# literal YAML boolean word config.yml.j2 needs. Config-panel boolean
# fields default to "1"/"0" (BooleanOption's yes=1/no=0), which is not
# valid YAML for Blossom's z.boolean() schema fields - rendering that
# raw would crash-loop the service on the next restart.
ynh_bool_to_yaml() {
	case "$1" in
		1|true|True|TRUE|yes|Yes|YES|on|On|ON|t|T) printf 'true' ;;
		*) printf 'false' ;;
	esac
}

ynh_upload_size_to_bytes() {
	case "$1" in
		"100 MiB") printf '104857600' ;;
		"500 MiB") printf '524288000' ;;
		"1 GiB") printf '1073741824' ;;
		"2 GiB") printf '2147483648' ;;
		"5 GiB") printf '5368709120' ;;
		*[!0-9]*|"") ynh_die "Invalid maximum upload size: $1" ;;
		*) printf '%s' "$1" ;;
	esac
}

# Reverse of ynh_upload_size_to_bytes. config.yml stores maxSize as a raw
# byte count, but the config panel's max_upload_size/media_max_upload_size
# fields are "select" questions whose choices are the human-readable
# presets ("2 GiB", ...) - the generic bind reader returns the byte count
# as-is, which matches none of those choices, so the dropdown shows
# nothing selected. Custom get__<setting> functions (see scripts/config)
# use this to show the matching preset instead. Falls back to the closest
# fixed preset for a value that was hand-edited outside the panel and
# doesn't exactly match one.
ynh_bytes_to_upload_size_choice() {
	case "$1" in
		104857600) printf '100 MiB' ;;
		524288000) printf '500 MiB' ;;
		1073741824) printf '1 GiB' ;;
		2147483648) printf '2 GiB' ;;
		5368709120) printf '5 GiB' ;;
		*) printf '2 GiB' ;;
	esac
}

# Maps a single video_profile setting to Blossom's three coupled
# media.video fields (format/videoCodec/audioCodec must be a valid
# combination or Blossom refuses to start).
ynh_video_profile_to_format() {
	case "$1" in
		mp4_h264_aac) printf 'mp4' ;;
		mp4_h265_aac) printf 'mp4' ;;
		webm_vp9_opus) printf 'webm' ;;
		mkv_h264_aac) printf 'mkv' ;;
		*) ynh_die "Unknown video profile: $1" ;;
	esac
}

ynh_video_profile_to_video_codec() {
	case "$1" in
		mp4_h264_aac) printf 'libx264' ;;
		mp4_h265_aac) printf 'libx265' ;;
		webm_vp9_opus) printf 'vp9' ;;
		mkv_h264_aac) printf 'libx264' ;;
		*) ynh_die "Unknown video profile: $1" ;;
	esac
}

ynh_video_profile_to_audio_codec() {
	case "$1" in
		mp4_h264_aac) printf 'aac' ;;
		mp4_h265_aac) printf 'aac' ;;
		webm_vp9_opus) printf 'opus' ;;
		mkv_h264_aac) printf 'aac' ;;
		*) ynh_die "Unknown video profile: $1" ;;
	esac
}
