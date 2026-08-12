import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Let __init__.py start the weekly-insights + nightly-fine-tuning + vacation-checker
# scheduler — this is the only scheduler in the production (gunicorn) process.
os.environ.setdefault('ENABLE_SCHEDULER', 'true')

from app import create_app

application = create_app()
