"""Shared setup for the user-story tests in this folder — keeps each test file
to just the scenario + assertion, not the Flask/mocking boilerplate."""
import os
import sys
from contextlib import contextmanager
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', '..'))

from flask import Flask
from app.api.analyze_routes import analyze_bp, analyze_data
from app.api.house_routes import house_bp


def default_house(**overrides):
    house = {
        'is_active': True,
        'is_vacation': False,
        'model_metadata': {'fine_tune_count': 0},
        'resident_name': 'Ruth',
    }
    house.update(overrides)
    return house


@contextmanager
def run_analyze(house, ai_decision=None, ai_meta=None):
    """Runs the real analyze_data() view with everything around the LSTM
    call mocked out. ai_decision=None means "don't let inference run at all"
    is NOT forced — has_enough_data still returns True, evaluate_buffer_with_AI
    is only skipped if analyze_data's own is_vacation check skips it."""
    app = Flask(__name__)
    app.register_blueprint(analyze_bp)

    with app.test_request_context(
        '/api/analyze', method='POST',
        json={'house_id': 'house_1', 'sensor_vector': [0] * 7},
        headers={'X-Device-Token': 'valid-token'},
    ), \
        patch('app.api.analyze_routes._validate_device_token', return_value=True), \
        patch('app.api.analyze_routes.user_db') as mock_user_db, \
        patch('app.api.analyze_routes.database') as mock_db, \
        patch('app.api.analyze_routes.sensor_buffer') as mock_buffer, \
        patch('app.api.analyze_routes.evaluate_buffer_with_AI',
              return_value=('sensor_5', ai_decision or 'Normal', ai_meta or {})) as mock_ai, \
        patch('app.api.analyze_routes.notifications') as mock_notifications, \
        patch('app.api.analyze_routes.device_health') as mock_health:

        mock_user_db.get_house.return_value = house
        mock_buffer.get_all_readings.return_value = [{}] * 360
        mock_buffer.has_enough_data.return_value = True
        mock_buffer.get_last_reading.return_value = None
        mock_health.FAULTY_SENSORS_CACHE = {}
        mock_health.SENSOR_NAMES = {}

        response = analyze_data()

        yield {
            'response': response,
            'database': mock_db,
            'notifications': mock_notifications,
            'evaluate_buffer_with_AI': mock_ai,
        }


@contextmanager
def run_house_status(meta):
    from flask_jwt_extended import JWTManager, create_access_token

    app = Flask(__name__)
    app.config['JWT_SECRET_KEY'] = 'pytest-insecure-test-secret'
    JWTManager(app)
    app.register_blueprint(house_bp)

    with patch('app.api.house_routes.database') as mock_db, \
         patch('app.api.house_routes.maybe_catch_up'):
        mock_db.get_house_activity_meta.return_value = meta
        client = app.test_client()
        with app.app_context():
            token = create_access_token(identity='user_1', additional_claims={'house_ids': ['house_1']})
        response = client.get('/api/house/house_1/status', headers={'Authorization': f'Bearer {token}'})
        yield response


def make_health_state(**overrides):
    from datetime import datetime, timezone
    state = {
        'is_vacation': False,
        'last_reading_at': datetime.now(timezone.utc),
        'sensor_mask': [1] * 7,
        'last_sensor_activity': {},
        'faulty_sensor_alert_sent': {},
        'activated_at': datetime.now(timezone.utc),
    }
    state.update(overrides)
    return state
