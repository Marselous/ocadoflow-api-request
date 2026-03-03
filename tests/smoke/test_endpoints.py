import pytest, requests

def test_products_requires_auth(base_url):
    assert requests.get(f"{base_url}/api/v1/products").status_code == 401

def test_orders_requires_auth(base_url):
    assert requests.get(f"{base_url}/api/v1/orders").status_code == 401

def test_iam_requires_auth(base_url):
    assert requests.get(f"{base_url}/api/v1/iam/users").status_code == 401
