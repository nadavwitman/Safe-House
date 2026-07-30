from firebase_admin import messaging
import database.user_db as user_db


def _send_multicast(house_id, title, body, label):
    """Shared FCM sender: fetches the house's tokens, sends one multicast notification,
    and prunes any tokens the server reports as invalid. Returns True if >=1 delivered."""
    tokens = user_db.get_house_fcm_tokens(house_id)
    if not tokens:
        print(f'[FCM] No registered tokens for house {house_id} — {label} not sent.')
        return False
    message = messaging.MulticastMessage(
        notification=messaging.Notification(title=title, body=body),
        tokens=tokens,
    )
    try:
        response = messaging.send_each_for_multicast(message)
        print(f'[FCM] {label} sent to {response.success_count}/{len(tokens)} '
              f'devices for house {house_id}.')
        _cleanup_invalid_tokens(response, tokens, house_id)
        return response.success_count > 0
    except Exception as e:
        print(f'[FCM] Error sending {label} for house {house_id}: {e}')
        return False


def send_alert_push(house_id, title, body):
    """Sends a fully-composed Warning/Emergency alert. The title and body are built by
    app.core.alert_messages.compose_alert_message, so this layer stays presentation-free."""
    return _send_multicast(house_id, title, body, 'anomaly alert')


def trigger_device_offline_alert(house_id, resident_name, minutes_silent):
    """Push when the ESP32 master has not reported for too long (whole-device outage)."""
    title = "Sensor hasn't checked in"
    body = (
        f"No signal from {resident_name}'s home for the past {minutes_silent} minutes. "
        f"Please make sure the Safe House device is powered on and connected to the internet."
    )
    return _send_multicast(house_id, title, body, 'offline alert')


def trigger_sensor_fault_alert(house_id, sensor_name, hours_silent):
    """Push when a specific sensor has been silent for an unusually long time — a suspected
    faulty / disconnected / dead-battery sensor. Additional context, never a replacement
    for the anomaly alerts."""
    title = 'Possible sensor fault'
    body = (
        f"The {sensor_name} sensor hasn't reported any activity in over {hours_silent} hours. "
        f"It may be faulty, disconnected, or out of battery. Please check the device."
    )
    return _send_multicast(house_id, title, body, f'sensor fault alert ({sensor_name})')


def _cleanup_invalid_tokens(response, tokens, house_id):
    """Removes FCM tokens that the server reports as invalid from all user docs."""
    house = user_db.get_house(house_id)
    if not house:
        return

    invalid_tokens = set()
    for idx, result in enumerate(response.responses):
        if not result.success and result.exception:
            error_code = getattr(result.exception, 'code', None)
            if error_code in ('messaging/registration-token-not-registered',
                              'messaging/invalid-registration-token'):
                if idx < len(tokens):
                    invalid_tokens.add(tokens[idx])

    if not invalid_tokens:
        return

    for uid in house.get('user_ids', []):
        user = user_db.get_user_by_id(uid)
        if not user:
            continue
        for token in invalid_tokens:
            if token in user.get('fcm_tokens', []):
                user_db.remove_fcm_token(uid, token)
                print(f'[FCM] Removed stale token from user {uid}.')
