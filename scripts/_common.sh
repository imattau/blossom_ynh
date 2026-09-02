#!/bin/bash

app="${YNH_APP_ID:-blossom}"
service_name="$app"

ynh_app_setting_get_or_default() {
	local key="$1" default="$2" value
	value="$(ynh_app_setting_get --app="$app" --key="$key" 2>/dev/null || true)"
	printf '%s' "${value:-$default}"
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
