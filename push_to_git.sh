#!/bin/bash
# Script to push files to git with Git LFS for large files

set -e

cd "$(dirname "$0")"

echo "=== Preparing Git Push ==="
echo ""

# Check if git-lfs is installed
if ! command -v git-lfs &> /dev/null; then
  echo "WARNING: git-lfs is not installed."
  echo "Install it with: sudo apt-get install git-lfs"
  echo ""
  echo "Without Git LFS, files >100MB will fail to push to GitHub."
  read -p "Continue anyway? (y/n) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
else
  echo "1. Initializing Git LFS..."
  git lfs install
fi

echo ""
echo "2. Tracking large file types with Git LFS..."
git lfs track "*.fst"
git lfs track "*.mdl"
git lfs track "*.ie"
git lfs track "*.pkl"
git lfs track "*.dubm"
git lfs track "*.mat"

echo ""
echo "3. Adding .gitattributes..."
git add .gitattributes

echo ""
echo "4. Adding all files..."
git add .

echo ""
echo "5. Checking what will be committed..."
echo "Files to commit:"
git status --short | head -20
echo "..."

echo ""
echo "6. Committing..."
git commit -m "Add pronunciation assessment models and scripts for Windows

- TDNN model (final.mdl, cmvn_opts, tree)
- i-vector extractor (all required files)
- Language models (lang, lang_nosp, lang_nosp_test_*)
- Lexicons (LibriSpeech and SpeechOcean762)
- Pronunciation model (pronunciation_model.pkl)
- Precomputed universal graph cache
- Scoring scripts (.sh and .py)
- Utilities and steps
- Configuration files

Note: Large files (>100MB) tracked with Git LFS"

echo ""
echo "7. Pushing to remote..."
echo "Remote: $(git remote get-url origin)"
read -p "Push to origin/main? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  git push origin main
  echo ""
  echo "✓ Push complete!"
else
  echo "Push cancelled. Run 'git push origin main' manually when ready."
fi
