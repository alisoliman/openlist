#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -B -m unittest discover -s Tools/SigningChecks -p 'test_*.py'
