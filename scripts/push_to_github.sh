#!/usr/bin/env bash
# Clone worktree to /tmp, build milestone history, push to GitHub.
set -euo pipefail
SRC="/Users/divyanshbarodiya/Desktop/Aether-Decoders"
WORK="/tmp/aether-decoders-push-$$"
REMOTE="https://github.com/Divyansh151005/Aether-Decoders.git"

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

echo "Copying project to $WORK (excluding .git, target, .cursor)…"
mkdir -p "$WORK"
(cd "$SRC" && tar --exclude='.git' --exclude='target' --exclude='.cursor' \
  --exclude='rtl/obj_dir' --exclude='rtl/obj_dir_*' \
  --exclude='fpga/*/out' --exclude='fpga/*/out_*' \
  --exclude='__pycache__' --exclude='scripts/__pycache__' \
  --exclude='python/**/__pycache__' --exclude='rtl/tb_*_sim' \
  --exclude='rtl/tb_sim' --exclude='rtl/tb_decode_sim' \
  -cf - .) | (cd "$WORK" && tar -xf -)

cd "$WORK"
git init -b main
git config user.email "2023csb1119@iitrpr.ac.in"
git config user.name "Divyansh Barodiya"

python3 scripts/build_git_history.py

COUNT=$(git rev-list --count HEAD)
echo "Built $COUNT commits"

if ! gh repo view Divyansh151005/Aether-Decoders >/dev/null 2>&1; then
  echo "Creating GitHub repo…"
  gh repo create Divyansh151005/Aether-Decoders --public \
    --description "Real-time FTQC decoder: integer Union-Find + Relay-BP for surface codes and qLDPC (M1–M72)"
fi
git remote add origin "$REMOTE" 2>/dev/null || git remote set-url origin "$REMOTE"
git push -u origin main --force

echo "Pushed to $REMOTE ($COUNT commits)"

# Sync .git back to source repo
echo "Syncing git history back to source workspace…"
rm -rf "$SRC/.git"
cp -a "$WORK/.git" "$SRC/.git"

echo "Done."
