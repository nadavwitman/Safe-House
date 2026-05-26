import os
import sys
from unittest.mock import MagicMock
from dotenv import load_dotenv

# Stub Firebase before any test module can import it.
# Tests that need real Firebase (test_database.py) are intended to be run as
# standalone scripts with credentials present — not as part of the pytest suite.
_fb = MagicMock()
for _mod in (
    'firebase_admin',
    'firebase_admin.credentials',
    'firebase_admin.firestore',
    'firebase_admin.storage',
    'firebase_admin.messaging',
    'firebase_admin.auth',
    'google',
    'google.cloud',
    'google.cloud.firestore',
    'google.cloud.firestore_v1',
    'google.genai',
    'google.genai.types',
    'google.generativeai',
    'google.generativeai.types',
    'google.api_core',
    'google.api_core.exceptions',
):
    sys.modules.setdefault(_mod, _fb)

# Stub heavy scientific packages so tests need only Flask + pytest.
# All database, AI, and preprocessing functions are patched per-test — these
# stubs only need to make module-level imports succeed without error.

# PyTorch (2 GB) — provide enough surface for class definitions to parse
_torch = MagicMock()
_torch.float32 = 'float32'
_torch.tensor = lambda *a, **kw: MagicMock()
_torch.nn = MagicMock()
_torch.nn.Module = object      # LSTMAutoencoder(nn.Module) becomes a plain class
_torch.nn.LSTM    = MagicMock
_torch.nn.Linear  = MagicMock
_torch.nn.Dropout = MagicMock
_torch.no_grad = MagicMock(return_value=MagicMock(
    __enter__=lambda s, *a: s,
    __exit__=lambda s, *a: False,
))
for _mod in (
    'torch', 'torch.nn', 'torch.nn.functional',
    'torch.optim', 'torch.utils', 'torch.utils.data',
):
    sys.modules.setdefault(_mod, _torch)

# pandas — used in database.database and data_preprocessing at import time
_pd = MagicMock()
_pd.DataFrame = MagicMock(return_value=MagicMock())
_pd.to_datetime = MagicMock(return_value=MagicMock())
_pd.Timestamp = MagicMock(return_value=MagicMock())
sys.modules.setdefault('pandas', _pd)

# numpy — used in data_preprocessing
_np = MagicMock()
_np.pi   = 3.141592653589793
_np.sin  = MagicMock(return_value=MagicMock())
_np.cos  = MagicMock(return_value=MagicMock())
_np.array = MagicMock(return_value=MagicMock())
for _mod in ('numpy', 'numpy.core', 'numpy.core.multiarray'):
    sys.modules.setdefault(_mod, _np)

# scikit-learn + joblib
_sklearn = MagicMock()
for _mod in ('sklearn', 'sklearn.preprocessing'):
    sys.modules.setdefault(_mod, _sklearn)
sys.modules.setdefault('joblib', MagicMock())

os.environ.setdefault('JWT_SECRET_KEY', 'pytest-insecure-test-secret')

load_dotenv(os.path.join(os.path.dirname(__file__), '..', '.env'))
