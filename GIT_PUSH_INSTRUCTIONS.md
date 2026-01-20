# Git Push Instructions

## Quick Push Commands

### Step 1: Check Status
```bash
cd /home/paperspace/kaldi_windows
git status
```

### Step 2: Add All Files
```bash
# Add all files (including the copied models and data)
git add .

# Or add specific directories:
git add kaldi/
git add *.md
git add *.sh
```

### Step 3: Commit
```bash
git commit -m "Add pronunciation assessment models and scripts for Windows

- TDNN model (final.mdl, cmvn_opts, tree)
- i-vector extractor
- Language models (lang, lang_nosp, lang_nosp_test_*)
- Lexicons (LibriSpeech and SpeechOcean762)
- Pronunciation model (pronunciation_model.pkl)
- Precomputed graphs cache
- Scoring scripts (.sh and .py)
- Utilities and steps
- Configuration files"
```

### Step 4: Push to Remote
```bash
# If remote is already configured:
git push origin main

# Or if using master branch:
git push origin master

# Or if remote is not set, add it first:
git remote add origin <your-repo-url>
git push -u origin main
```

## Important Notes

### Large Files Warning
Some files are large (models, language models, graphs):
- `final.mdl`: ~75 MB
- Language models: ~500 MB total
- Precomputed graphs: ~512 MB
- Total: ~1.2-1.5 GB

**GitHub**: Free accounts have 100 MB file size limit. You may need:
- **Git LFS** (Large File Storage) for files > 100 MB
- **Alternative**: Use Google Drive or other cloud storage for large files

### Using Git LFS (Recommended for Large Files)

```bash
# Install git-lfs (if not installed)
# On Ubuntu: sudo apt-get install git-lfs

# Initialize Git LFS
git lfs install

# Track large files
git lfs track "*.mdl"
git lfs track "*.fst"
git lfs track "*.pkl"
git lfs track "*.ie"
git lfs track "lang*/**"
git lfs track "pronunciation_cache/**"

# Add .gitattributes
git add .gitattributes

# Then add and commit as usual
git add .
git commit -m "Add models with Git LFS"
git push origin main
```

### Alternative: Exclude Large Files from Git

If you don't want to use Git LFS, you can exclude large files and store them separately:

```bash
# Create .gitignore
cat > .gitignore << 'EOF'
# Large model files (store separately)
kaldi/egs/librispeech/s5/exp/nnet3_cleaned/tdnn_sp/final.mdl
kaldi/egs/librispeech/s5/exp/nnet3_cleaned/extractor/10.ie
kaldi/egs/librispeech/s5/data/lang*/
kaldi/egs/gop_speechocean762/s5/exp/pronunciation_cache/
*.fst
*.mdl
*.ie
*.pkl
EOF

# Then commit only scripts and small files
git add .gitignore
git add kaldi/egs/gop_speechocean762/s5/local/
git add kaldi/egs/gop_speechocean762/s5/utils/
git add kaldi/egs/gop_speechocean762/s5/steps/
git add kaldi/egs/gop_speechocean762/s5/conf/
git add kaldi/egs/gop_speechocean762/s5/*.sh
git commit -m "Add pronunciation assessment scripts"
git push origin main
```

## Recommended Approach

**For GitHub** (with file size limits):
1. Use Git LFS for large files, OR
2. Store large files separately (Google Drive) and only commit scripts

**For Google Drive** (no size limits):
1. Just push everything directly
2. No need for Git LFS

## Check Before Pushing

```bash
# Check what will be pushed
git status
git log --oneline -5

# Check file sizes
find . -type f -size +50M -exec ls -lh {} \;

# Check total size
du -sh .
```
