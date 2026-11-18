#!/usr/bin/env python3
"""
Test runner for Nexora VPN Linux CLI test suite.
"""

import sys
import unittest
from pathlib import Path

def main():
    test_dir = Path(__file__).resolve().parent
    suite = unittest.defaultTestLoader.discover(str(test_dir), pattern="test_*.py")

    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)

    print("\n" + "=" * 50)
    print(f"Total Tests Run : {result.testsRun}")
    print(f"Failures        : {len(result.failures)}")
    print(f"Errors          : {len(result.errors)}")
    print(f"Skipped         : {len(result.skipped)}")
    print("=" * 50)

    if result.wasSuccessful():
        print("✓ ALL TESTS PASSED SUCCESSFULLY!")
        return 0
    else:
        print("✗ SOME TESTS FAILED")
        return 1

if __name__ == "__main__":
    sys.exit(main())
