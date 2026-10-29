#!/usr/bin/env bash
# Обёртка для запуска статических проверок проекта Vanks OS.
set -euo pipefail
PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "${PROJECT_DIR}/tools/validate.py" --root "${PROJECT_DIR}" "$@"
