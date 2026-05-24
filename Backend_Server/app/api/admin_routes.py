import os
from flask import Blueprint, request, jsonify
from flask_jwt_extended import jwt_required, get_jwt_identity
import database.user_db as user_db
from app.auth.decorators import admin_required
from app.auth.utils import generate_user_id, generate_invite_code, generate_device_token, hash_password
from app.core.house_mask_store import house_mask_store

admin_bp = Blueprint('admin', __name__)


@admin_bp.route('/api/admin/create-admin', methods=['POST'])
def create_admin():
    """Protected by ADMIN_CREATION_KEY header — used by dev team only, not public API."""
    key = request.headers.get('X-Admin-Creation-Key', '')
    if key != os.environ.get('ADMIN_CREATION_KEY', ''):
        return jsonify({'error': 'Unauthorized'}), 401

    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    username = (data.get('username') or '').strip()
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''

    if not username or not email or not password:
        return jsonify({'error': 'username, email, and password are required'}), 400

    if user_db.get_user_by_email(email):
        return jsonify({'error': 'Email already in use'}), 409
    if user_db.get_user_by_username(username):
        return jsonify({'error': 'Username already taken'}), 409

    user_id = generate_user_id()
    user_db.create_user(user_id, username, email, hash_password(password), role='admin')

    return jsonify({
        'user_id': user_id,
        'username': username,
        'email': email,
        'role': 'admin',
    }), 201


@admin_bp.route('/api/admin/house/create', methods=['POST'])
@admin_required
def create_house():
    data = request.get_json() or {}
    resident_name = (data.get('resident_name') or '').strip()
    address = (data.get('address') or '').strip()
    emergency_contact_phone = (data.get('emergency_contact_phone') or '').strip()

    if not resident_name:
        return jsonify({'error': 'resident_name is required'}), 400

    admin_user_id = get_jwt_identity()
    house_id = generate_user_id()
    invite_code = _unique_invite_code()
    device_token = generate_device_token()

    user_db.create_house(
        house_id=house_id,
        resident_name=resident_name,
        address=address,
        emergency_contact_phone=emergency_contact_phone,
        invite_code=invite_code,
        device_token=device_token,
        admin_user_id=admin_user_id,
    )

    return jsonify({
        'house_id': house_id,
        'invite_code': invite_code,
        'device_token': device_token,
    }), 201


@admin_bp.route('/api/admin/houses', methods=['GET'])
@admin_required
def list_houses():
    admin_user_id = get_jwt_identity()
    houses = user_db.get_admin_houses(admin_user_id)
    result = [{
        'house_id': h.get('house_id'),
        'resident_name': h.get('resident_name'),
        'address': h.get('address'),
        'is_active': h.get('is_active', False),
        'user_count': len(h.get('user_ids', [])),
    } for h in houses]
    return jsonify({'houses': result}), 200


@admin_bp.route('/api/admin/house/<house_id>', methods=['GET'])
@admin_required
def get_house(house_id):
    house = user_db.get_house(house_id)
    if not house:
        return jsonify({'error': 'House not found'}), 404

    users = []
    for uid in house.get('user_ids', []):
        u = user_db.get_user_by_id(uid)
        if u:
            users.append({
                'user_id': uid,
                'username': u.get('username'),
                'email': u.get('email'),
                'role': u.get('role', 'user'),
            })

    return jsonify({
        'house_id': house_id,
        'resident_name': house.get('resident_name'),
        'address': house.get('address'),
        'emergency_contact_phone': house.get('emergency_contact_phone'),
        'is_active': house.get('is_active', False),
        'invite_code': house.get('invite_code'),
        'sensor_mask': house_mask_store.get_mask(house_id),
        'users': users,
    }), 200


@admin_bp.route('/api/admin/house/<house_id>/user/<user_id>', methods=['DELETE'])
@admin_required
def remove_user_from_house(house_id, user_id):
    house = user_db.get_house(house_id)
    if not house:
        return jsonify({'error': 'House not found'}), 404

    user_db.remove_user_from_house(house_id, user_id)
    user_db.remove_house_from_user(user_id, house_id)
    return jsonify({'status': 'success'}), 200


@admin_bp.route('/api/admin/house/<house_id>/regenerate-invite', methods=['POST'])
@admin_required
def regenerate_invite(house_id):
    house = user_db.get_house(house_id)
    if not house:
        return jsonify({'error': 'House not found'}), 404

    new_code = _unique_invite_code()
    user_db.update_house_invite_code(house_id, new_code)
    return jsonify({'invite_code': new_code}), 200


@admin_bp.route('/api/admin/house/<house_id>/rotate-device-token', methods=['POST'])
@admin_required
def rotate_device_token(house_id):
    house = user_db.get_house(house_id)
    if not house:
        return jsonify({'error': 'House not found'}), 404

    new_token = generate_device_token()
    user_db.update_house_device_token(house_id, new_token)
    return jsonify({'device_token': new_token}), 200


def _unique_invite_code():
    """Generates an invite code guaranteed not to collide with existing codes."""
    for _ in range(10):
        code = generate_invite_code()
        existing_id, _ = user_db.get_house_by_invite_code(code)
        if not existing_id:
            return code
    return generate_invite_code()
