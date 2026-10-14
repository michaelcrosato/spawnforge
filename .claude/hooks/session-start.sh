#!/bin/bash
# Prepares a Claude Code cloud session so `pnpm check`, renders and exports work: the workspace's
# dependencies from the lockfile, the pre-installed Chromium for headless renders, and Blender's
# `bpy` (at CI's pin) for the engine import test. Each step is idempotent, so resumes are quick.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(dirname "$0")/../..}"
env_file="${CLAUDE_ENV_FILE:-/dev/null}"

# Dependencies, as CI installs them. Progress goes to stderr, out of the session's context. A hook
# has no TTY, so pnpm may not ask before rebuilding node_modules (after a pnpm or store change).
command -v pnpm >/dev/null || corepack enable >&2
pnpm install --frozen-lockfile --config.confirm-modules-purge=false >&2

# Headless renders: the image's Chromium (packages/render tries $SPAWNFORGE_CHROMIUM first).
if [ -z "${SPAWNFORGE_CHROMIUM:-}" ] && [ -x /opt/pw-browsers/chromium ]; then
  echo 'export SPAWNFORGE_CHROMIUM=/opt/pw-browsers/chromium' >>"$env_file"
fi

# Blender as a Python module for packages/render/src/engines.test.ts, at the version CI pins.
# Best effort: without it that one test is skipped, as it is outside CI.
venv="$HOME/.venvs/bpy"
bpy_version=$(sed -n 's/.*bpy==\([0-9.]*\).*/\1/p' .github/workflows/ci.yml | head -n 1)
if [ -n "$bpy_version" ] && (
  ldconfig -p | grep -q 'libEGL.so.1' ||
    apt-get install -y --no-install-recommends libegl1 >&2 ||
    { apt-get update -qq >&2 && apt-get install -y --no-install-recommends libegl1 >&2; }
  if ! "$venv/bin/python" -c "import bpy, sys; sys.exit(bpy.app.version_string.split()[0] != '$bpy_version')" 2>/dev/null; then
    python3 -m venv "$venv" >&2 && "$venv/bin/pip" install -q "bpy==$bpy_version" >&2
  fi
  "$venv/bin/python" -c 'import bpy' 2>/dev/null
); then
  echo "export SPAWNFORGE_BPY_PYTHON=$venv/bin/python" >>"$env_file"
else
  echo "session-start: bpy unavailable; the Blender import test will be skipped" >&2
fi
