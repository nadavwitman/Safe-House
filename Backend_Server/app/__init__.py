from flask import Flask

def create_app():
    # Initialize the main Flask application object
    app = Flask(__name__)
    
    # Import blueprints locally to avoid circular dependencies
    from app.api.analyze_routes import analyze_bp
    from app.api.config_routes import config_bp
    
    # Register the API routes under the app instance
    app.register_blueprint(analyze_bp)
    app.register_blueprint(config_bp)
    
    return app