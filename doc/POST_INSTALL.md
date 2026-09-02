{% if enable_dashboard == '1' %}
## Admin dashboard

The admin dashboard is enabled at `<your Blossom URL>/admin`.

It has no relation to YunoHost users or SSO - it's Blossom's own separate HTTP Basic Auth:

- **Username:** `__ADMIN__`
- **Password:** `__DASHBOARD_PASSWORD__`

You can change this password later from the app's config panel (Main > Features > Dashboard password). Save it somewhere first - the panel won't show you the current one.
{% endif %}
