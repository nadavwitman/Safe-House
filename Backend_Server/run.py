from app import create_app

# Initialize the app using the factory function
app = create_app()

if __name__ == '__main__':
    # Run server: accessible externally, on port 5000, with debug mode on
    app.run(host='0.0.0.0', port=5000, debug=True)