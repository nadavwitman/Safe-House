from flask import Blueprint, request, jsonify
from flask_jwt_extended import (
    create_access_token, create_refresh_token,
    jwt_required, get_jwt_identity, get_jwt
)
import database.user_db as user_db
from app.auth.utils import generate_user_id, hash_password, verify_password

auth_bp = Blueprint('auth', __name__)


def _make_tokens(user):
    additional_claims = {'role': user['role'], 'house_ids': user.get('house_ids', [])}
    access_token = create_access_token(identity=user['user_id'], additional_claims=additional_claims)
    refresh_token = create_refresh_token(identity=user['user_id'])
    return access_token, refresh_token


@auth_bp.route('/api/auth/signup', methods=['POST'])
def signup():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    username = (data.get('username') or '').strip()
    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''

    if not username or not email or not password:
        return jsonify({'error': 'username, email, and password are required'}), 400
    if len(password) < 6:
        return jsonify({'error': 'Password must be at least 6 characters'}), 400

    if user_db.get_user_by_email(email):
        return jsonify({'error': 'Email already in use'}), 409
    if user_db.get_user_by_username(username):
        return jsonify({'error': 'Username already taken'}), 409

    user_id = generate_user_id()
    password_hash = hash_password(password)
    user_db.create_user(user_id, username, email, password_hash, role='user')

    user = user_db.get_user_by_id(user_id)
    access_token, refresh_token = _make_tokens(user)

    return jsonify({
        'user_id': user_id,
        'username': username,
        'email': email,
        'role': 'user',
        'access_token': access_token,
        'refresh_token': refresh_token,
    }), 201


@auth_bp.route('/api/auth/signin', methods=['POST'])
def signin():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    email = (data.get('email') or '').strip().lower()
    password = data.get('password') or ''

    user = user_db.get_user_by_email(email)
    if not user or not verify_password(password, user['password_hash']):
        return jsonify({'error': 'Invalid email or password'}), 401

    access_token, refresh_token = _make_tokens(user)

    return jsonify({
        'user_id': user['user_id'],
        'username': user['username'],
        'email': user['email'],
        'role': user['role'],
        'house_ids': user.get('house_ids', []),
        'access_token': access_token,
        'refresh_token': refresh_token,
    }), 200


@auth_bp.route('/api/auth/refresh', methods=['POST'])
@jwt_required(refresh=True)
def refresh():
    user_id = get_jwt_identity()
    user = user_db.get_user_by_id(user_id)
    if not user:
        return jsonify({'error': 'User not found'}), 404

    # Return both tokens — frontend replaces both to reset the 30-day rolling window
    additional_claims = {'role': user['role'], 'house_ids': user.get('house_ids', [])}
    access_token = create_access_token(identity=user_id, additional_claims=additional_claims)
    refresh_token = create_refresh_token(identity=user_id)
    return jsonify({'access_token': access_token, 'refresh_token': refresh_token}), 200


@auth_bp.route('/api/auth/signout', methods=['POST'])
@jwt_required()
def signout():
    return jsonify({'status': 'success'}), 200


@auth_bp.route('/api/auth/change-password', methods=['POST'])
@jwt_required()
def change_password():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    current_password = data.get('current_password') or ''
    new_password = data.get('new_password') or ''

    if not current_password or not new_password:
        return jsonify({'error': 'current_password and new_password are required'}), 400
    if len(new_password) < 6:
        return jsonify({'error': 'New password must be at least 6 characters'}), 400

    user_id = get_jwt_identity()
    user = user_db.get_user_by_id(user_id)
    if not verify_password(current_password, user['password_hash']):
        return jsonify({'error': 'Current password is incorrect'}), 401

    user_db.update_user(user_id, {'password_hash': hash_password(new_password)})
    return jsonify({'status': 'success'}), 200


@auth_bp.route('/api/auth/change-username', methods=['POST'])
@jwt_required()
def change_username():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'No data provided'}), 400

    new_username = (data.get('new_username') or '').strip()
    if not new_username:
        return jsonify({'error': 'new_username is required'}), 400

    if user_db.get_user_by_username(new_username):
        return jsonify({'error': 'Username already taken'}), 409

    user_id = get_jwt_identity()
    user_db.update_user(user_id, {'username': new_username})
    return jsonify({'status': 'success', 'username': new_username}), 200
