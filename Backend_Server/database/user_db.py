"""
Facade over database/repositories/{users,houses}.py — kept as the single import
surface (`import database.user_db as user_db`) so callers don't need to know
which repository module actually owns a given function.
"""
from database.repositories.users import (
    get_user_by_id,
    get_user_by_email,
    get_user_by_username,
    create_user,
    update_user,
    add_house_to_user,
    remove_house_from_user,
    add_fcm_token,
    remove_fcm_token,
)

from database.repositories.houses import (
    create_house,
    get_house,
    get_house_by_invite_code,
    add_user_to_house,
    remove_user_from_house,
    activate_house,
    update_house_device_token,
    update_house_invite_code,
    get_house_fcm_tokens,
    get_admin_houses,
    delete_house,
    get_all_active_house_ids,
    validate_device_token,
)
