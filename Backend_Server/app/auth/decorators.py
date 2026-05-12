from functools import wraps
from flask import jsonify, request
from flask_jwt_extended import jwt_required, get_jwt


def admin_required(fn):
    @wraps(fn)
    @jwt_required()
    def wrapper(*args, **kwargs):
        if get_jwt().get('role') != 'admin':
            return jsonify({'error': 'Admin access required'}), 403
        return fn(*args, **kwargs)
    return wrapper


def house_member_required(fn):
    @wraps(fn)
    @jwt_required()
    def wrapper(*args, **kwargs):
        claims = get_jwt()
        data = request.get_json(silent=True) or {}
        house_id = kwargs.get('house_id') or data.get('house_id')
        if not house_id or house_id not in claims.get('house_ids', []):
            return jsonify({'error': 'Access to this house is not authorized'}), 403
        return fn(*args, **kwargs)
    return wrapper
