# app/auth

Shared authentication/authorization building blocks used across [app/api](../api/README.md)'s route blueprints. Two roles exist: `admin` (the company installer) and `user` (a resident's family member) — role and `house_ids` are carried as JWT claims (set in `auth_routes._make_tokens`) so these decorators can check them without a DB read.

## Files

- **[decorators.py](decorators.py)** — route-guarding decorators, both built on `flask_jwt_extended.jwt_required()`:
  - `admin_required` — 403s unless the JWT's `role` claim is `'admin'`.
  - `house_member_required` — 403s unless the `house_id` (from the URL kwargs or JSON body) is in the JWT's `house_ids` claim. Used on any route scoped to a specific house.
- **[utils.py](utils.py)** — stateless helpers:
  - `generate_user_id()` — UUID4 string.
  - `generate_invite_code()` — random 6-char uppercase alphanumeric code (collision-checked by the caller, e.g. `admin_routes._unique_invite_code`).
  - `generate_device_token()` — random 64-char hex token for ESP32 device auth (`X-Device-Token` header, validated in `analyze_routes.py`).
  - `hash_password()` / `verify_password()` — bcrypt wrappers (`flask_bcrypt`).
