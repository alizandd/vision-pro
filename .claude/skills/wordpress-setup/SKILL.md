---
name: wordpress-setup
description: The team's standard approach to setting up, developing, and maintaining WordPress — custom plugin/theme, REST API, hooks, security, and project structure. Always use this skill whenever the conversation involves WordPress, a custom plugin, theme development, the WP REST API, or integrating with WordPress.
---

# WordPress Setup and Development

## Stack (current baseline — verify with `tech-research`)
- **WordPress 7.0+** (April 2026). Core's hard minimum is now PHP 7.4 (7.2/7.3 dropped), but the team's floor is **PHP 8.3+** — run 8.4 where the host allows.
- Keep core, plugins, and themes on auto-updating minor releases; an unmaintained plugin is the most common WordPress compromise path.

## Project structure
- Composer-based (manage core/plugin/theme via composer + `wpackagist`).
- `wp-config.php` reads from env (use `vlucas/phpdotenv` or environment constants).
- Custom code lives in dedicated plugins/themes, never modify core.

## Custom plugin / theme
- Each independent feature = a separate plugin.
- PHP namespacing to avoid conflicts.
- Use hooks (`add_action` / `add_filter`), not direct core edits.
- Enqueue assets with `wp_enqueue_script/style`, not manual echo.

## REST API
- Custom endpoints with `register_rest_route` under a dedicated namespace: `myapp/v1/...`
- Always set a `permission_callback` (never `__return_true` for anything sensitive).
- Output should match the team API conventions (refer to the api-conventions skill).

## Security
- Sanitize input (`sanitize_text_field`, etc.), escape output (`esc_html`, `esc_attr`).
- Nonces for forms and actions.
- Prepared statements with `$wpdb->prepare` — never string-concatenated queries.
- Capability checks (`current_user_can`) for admin actions.

## Performance
- Transient API for caching heavy queries.
- Object cache (Redis) if available.
- Use `WP_Query` efficiently; avoid `posts_per_page => -1`.

## Deploy
- Keep the DB and `wp-content/uploads` out of the repo (gitignore).
- Migrate content with `wp-cli` or a migration plugin, not manual export/import in production.
- Refer to the DevOps DEPLOY.md for container/Nginx.
