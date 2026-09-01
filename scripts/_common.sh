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
