from firebase_admin import messaging
import database.user_db as user_db


def trigger_device_offline_alert(house_id, resident_name, minutes_silent):
    """
    Sends a push notification when the ESP32 has not reported for too long.
    """
    title = "Sensor hasn't checked in"
    body = (
        f"No signal from {resident_name}'s home for the past {minutes_silent} minutes. "
        f"Please make sure the Safe House device is powered on and connected to the internet."
    )
    tokens = user_db.get_house_fcm_tokens(house_id)
    if not tokens:
        print(f'[FCM] No registered tokens for house {house_id} — offline alert not sent.')
        return False
    notification = messaging.Notification(title=title, body=body)
    message = messaging.MulticastMessage(notification=notification, tokens=tokens)
    try:
        response = messaging.send_each_for_multicast(message)
        print(f'[FCM] Offline alert sent to {response.success_count}/{len(tokens)} devices for house {house_id}.')
        _cleanup_invalid_tokens(response, tokens, house_id)
        return response.success_count > 0
    except Exception as e:
        print(f'[FCM] Error sending offline alert for house {house_id}: {e}')
        return False


def trigger_fcm_alert(sensor_name, severity, house_id):
    """
    Sends a push notification to all users monitoring the given house.

    @sensor_name : The sensor that triggered the anomaly
    @severity    : "Warning" or "Emergency"
    @house_id    : The house to notify users of
    """
    match severity:
        case 'Warning':
            title = 'Moderate alarm'
            body = (f'Unusual lack of motion detected around the {sensor_name}. '
                    'Might want to keep an eye out and see if it continues.')
        case 'Emergency':
            title = 'Emergency ALERT'
            body = (f'High priority alert: Extended lack of motion detected in the '
                    f'{sensor_name} area. Please check immediately.')
        case _:
            return False

    tokens = user_db.get_house_fcm_tokens(house_id)
    if not tokens:
        print(f'[FCM] No registered tokens for house {house_id} — notification not sent.')
        return False

    notification = messaging.Notification(title=title, body=body)
    message = messaging.MulticastMessage(notification=notification, tokens=tokens)

    try:
        response = messaging.send_each_for_multicast(message)
        print(f'[FCM] Sent to {response.success_count}/{len(tokens)} devices for house {house_id}.')
        _cleanup_invalid_tokens(response, tokens, house_id)
        return response.success_count > 0
    except Exception as e:
        print(f'[FCM] Error sending notification for house {house_id}: {e}')
        return False


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
