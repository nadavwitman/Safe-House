def send_buffer_to_AI(buffer):
    """
    TODO: Implement this function which will send the buffer to the PyTorch LSTM model for processing.
    The model expects a sequence of preprocessed events to analyze the routine.
    """
    pass

def recieve_AI_decision() -> tuple[str, str]:
    """
    TODO: Implement this function which will recieve the conclusion of the AI model.
    It will decide if everything is normal, there is a moderate warning, or an emergency.
    
    Returns:
        tuple: (sensor_id, decision) 
               decision indicates "Normal" / "Warning" / "Emergency" status.
    """
    # Currently returning a mock response
    return ("unknown", "Normal")