import uuid
import secrets
import string
from flask_bcrypt import generate_password_hash, check_password_hash


def generate_user_id():
    return str(uuid.uuid4())


def generate_invite_code():
    chars = string.ascii_uppercase + string.digits
    return ''.join(secrets.choice(chars) for _ in range(6))


def generate_device_token():
    return secrets.token_hex(32)


def hash_password(password):
    return generate_password_hash(password).decode('utf-8')


def verify_password(password, hashed):
    return check_password_hash(hashed, password)
