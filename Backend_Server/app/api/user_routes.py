from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
import database.user_db as user_db

user_bp = Blueprint('user', __name__)


@user_bp.route('/api/user/me', methods=['GET'])
@jwt_required()
def get_me():
    user_id = get_jwt_identity()
    user = user_db.get_user_by_id(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404

    houses = []
    for hid in user.get('house_ids', []):
        house = user_db.get_house(hid)
        if house:
            mask = house.get('sensor_mask')
            if not (isinstance(mask, list) and len(mask) == 7):
                mask = [1, 1, 1, 1, 1, 1, 1]
            houses.append({
                'house_id': hid,
                'resident_name': house.get('resident_name'),
                'address': house.get('address'),
                'is_active': house.get('is_active', False),
                'is_vacation': house.get('is_vacation', False),
                'vacation_schedule': house.get('vacation_schedule'),
                'sensor_mask': mask,
                # Dialled by the home screen's Call button during an Emergency. This is
                # the contact the installer registered for the house, not the resident's
                # own line — the UI labels it accordingly.
                'emergency_contact_phone': house.get('emergency_contact_phone'),
            })

    return jsonify({
        'user_id': user['user_id'],
        'username': user['username'],
        'email': user['email'],
        'role': user['role'],
        'houses': houses,
    }), 200


@user_bp.route('/api/user/house/join', methods=['POST'])
@jwt_required()
def join_house():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    invite_code = (data.get('invite_code') or '').strip().upper()
    if not invite_code:
        return jsonify({'error': 'invite_code is required'}), 400

    house_id, house = user_db.get_house_by_invite_code(invite_code)
    if not house_id:
        return jsonify({'error': 'Invalid invite code'}), 404

    user_id = get_jwt_identity()
    if user_id in house.get('user_ids', []):
        return jsonify({'error': 'Already a member of this house'}), 409

    user_db.add_user_to_house(house_id, user_id)
    user_db.add_house_to_user(user_id, house_id)

    return jsonify({
        'status': 'joined',
        'house_id': house_id,
        'resident_name': house.get('resident_name'),
    }), 200


@user_bp.route('/api/user/fcm-token', methods=['POST'])
@jwt_required()
def add_fcm_token():
    data = request.get_json()
    token = (data or {}).get('fcm_token', '').strip()
    if not token:
        return jsonify({'error': 'fcm_token is required'}), 400

    user_id = get_jwt_identity()
    user_db.add_fcm_token(user_id, token)
    return jsonify({'status': 'success'}), 200


@user_bp.route('/api/user/fcm-token', methods=['DELETE'])
@jwt_required()
def remove_fcm_token():
    data = request.get_json()
    token = (data or {}).get('fcm_token', '').strip()
    if not token:
        return jsonify({'error': 'fcm_token is required'}), 400

    user_id = get_jwt_identity()
    user_db.remove_fcm_token(user_id, token)
    return jsonify({'status': 'success'}), 200
