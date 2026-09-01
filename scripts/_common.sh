#!/bin/bash

app="${YNH_APP_ID:-blossom}"
service_name="$app"

ynh_app_setting_get_or_default() {
	local key="$1" default="$2" value
	value="$(ynh_app_setting_get --app="$app" --key="$key" 2>/dev/null || true)"
	printf '%s' "${value:-$default}"
}
