from flask import Flask

def create_app():
    # Initialize the main Flask application object
    app = Flask(__name__)
    
    # Import blueprints locally to avoid circular dependencies
    from app.routes import api_bp
    
    # Register the API routes under the app instance
    app.register_blueprint(api_bp)
    
    return app