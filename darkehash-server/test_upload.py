#!/usr/bin/env python3
"""
Test script for DarkeHash server endpoints
"""

import requests
import json
import sys
from datetime import datetime

# Configuration
SERVER_URL = "http://localhost:8800"
USERNAME = "darkepwn"
PASSWORD = "dh2akf5ksdai44ad0y"


def test_health():
    """Test health endpoint (no auth required)"""
    print("Testing health endpoint...")
    try:
        response = requests.get(f"{SERVER_URL}/health")
        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False


def test_handshake_upload():
    """Test handshake upload endpoint"""
    print("\nTesting handshake upload...")

    # Create a dummy pcap file for testing
    dummy_pcap = b'\xa1\xb2\xc3\xd4\x00\x02\x00\x04' + b'\x00' * 100

    try:
        files = {'handshake': ('test_handshake.pcap', dummy_pcap, 'application/vnd.tcpdump.pcap')}
        data = {
            'ssid': 'TestNetwork',
            'bssid': 'AA:BB:CC:DD:EE:FF',
            'device_name': 'test-device'
        }

        response = requests.post(
            f"{SERVER_URL}/api/upload/handshake",
            files=files,
            data=data,
            auth=(USERNAME, PASSWORD)
        )

        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False


def test_status_upload():
    """Test status upload endpoint"""
    print("\nTesting status upload...")

    status_data = {
        'device_name': 'test-device',
        'timestamp': datetime.now().isoformat(),
        'log_data': 'Test log line 1\nTest log line 2\nTest log line 3',
        'system_info': {
            'uptime': 86400,
            'version': '2.8.9',
            'handshakes_uploaded': 10,
            'handshakes_pending': 2
        }
    }

    try:
        response = requests.post(
            f"{SERVER_URL}/api/upload/status",
            json=status_data,
            auth=(USERNAME, PASSWORD)
        )

        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False


def test_stats():
    """Test stats endpoint"""
    print("\nTesting stats endpoint...")

    try:
        response = requests.get(
            f"{SERVER_URL}/api/stats",
            auth=(USERNAME, PASSWORD)
        )

        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 200
    except Exception as e:
        print(f"Error: {e}")
        return False


def test_auth_failure():
    """Test authentication failure"""
    print("\nTesting authentication failure...")

    try:
        response = requests.get(
            f"{SERVER_URL}/api/stats",
            auth=("wrong", "credentials")
        )

        print(f"Status: {response.status_code}")
        print(f"Response: {json.dumps(response.json(), indent=2)}")
        return response.status_code == 401
    except Exception as e:
        print(f"Error: {e}")
        return False


def main():
    """Run all tests"""
    print("=" * 60)
    print("DarkeHash Server Test Suite")
    print("=" * 60)
    print(f"Server: {SERVER_URL}")
    print(f"Username: {USERNAME}")
    print("=" * 60)

    tests = [
        ("Health Check", test_health),
        ("Handshake Upload", test_handshake_upload),
        ("Status Upload", test_status_upload),
        ("Stats Retrieval", test_stats),
        ("Auth Failure", test_auth_failure),
    ]

    results = []
    for name, test_func in tests:
        try:
            result = test_func()
            results.append((name, result))
        except Exception as e:
            print(f"\nUnexpected error in {name}: {e}")
            results.append((name, False))

    # Summary
    print("\n" + "=" * 60)
    print("Test Results Summary")
    print("=" * 60)
    for name, result in results:
        status = "✓ PASS" if result else "✗ FAIL"
        print(f"{status:10} - {name}")

    passed = sum(1 for _, r in results if r)
    total = len(results)
    print("=" * 60)
    print(f"Passed: {passed}/{total}")

    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
