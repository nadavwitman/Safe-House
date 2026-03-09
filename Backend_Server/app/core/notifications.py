from firebase_admin import messaging

def trigger_fcm_alert(sensor_name, severity):
    """
    This function will construct and send an emergency message to the user's via the mobile app in the case where
    an extreme anomaly has been detected

    @sensor_name : The sensor which has triggerred the anomaly
    @severity : How series is the situation
    """

    # Construct the message's content based on the severity of the alert
    match severity:
        case "Warning":
            title = "Moderate alarm"
            body = f"Unusual lack of motion detected around the {sensor_name}. Might want to keep an eye out and see if it continues."
            topic = "warning_alerts"

        case "Emergency":
            title = "Emergency ALERT"
            body = f"High priority alert : Extended lack of motion detected in the {sensor_name} area. Please check immediately"
            topic = "emergency_alerts"


    # Create the message object based on the fields constructed above
    notification = messaging.Notification(
        title=title,
        body=body
    )

    message = messaging.Message(
        notification=notification,
        topic='emergency_alerts'
    )

    # Send the notification via Firebase SDK
    try:
        response = messaging.send(message)
        print(f"Successfully sent FCM message: {response}")
        return True
    except Exception as e:
        print(f"Error sending FCM message: {e}")
        return False
