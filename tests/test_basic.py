import sys
import pathlib

def test_smoke():
    assert True

def test_project_has_python_files():
    root = pathlib.Path(__file__).resolve().parents[1]
    py_files = list(root.rglob("*.py"))
    assert len(py_files) > 0

def test_python_version():
    assert sys.version_info >= (3, 10)
