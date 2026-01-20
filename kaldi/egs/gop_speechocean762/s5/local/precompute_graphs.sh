#!/usr/bin/env bash
# Precompute alignment graphs for common words/phrases
# This allows instant scoring for frequently used text

set -e

[ -f ./path.sh ] && . ./path.sh
[ -f ./cmd.sh ] && . ./cmd.sh

cache_dir=${1:-exp/pronunciation_cache}
common_phrases_file=${2:-local/common_phrases.txt}

librispeech_eg=../../librispeech/s5
model=$librispeech_eg/exp/nnet3_cleaned/tdnn_sp
lang_dir=$cache_dir/lang_nosp

mkdir -p $cache_dir/graphs

# Ensure language model cache exists first
if [ ! -f "$lang_dir/L.fst" ]; then
  echo "=== Setting up language model cache (required first) ==="
  mkdir -p $lang_dir
  
  librispeech_lang=""
  if [ -f "$librispeech_eg/data/lang_nosp_test_tgsmall/G.fst" ]; then
    librispeech_lang="$librispeech_eg/data/lang_nosp_test_tgsmall"
  elif [ -f "$librispeech_eg/data/lang_nosp_test_tgmed/G.fst" ]; then
    librispeech_lang="$librispeech_eg/data/lang_nosp_test_tgmed"
  elif [ -d "$librispeech_eg/data/lang_nosp" ] && [ -f "$librispeech_eg/data/lang_nosp/L.fst" ]; then
    librispeech_lang="$librispeech_eg/data/lang_nosp"
  fi
  
  if [ -n "$librispeech_lang" ]; then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a $librispeech_lang/ $lang_dir/ || exit 1
    else
      cp -r $librispeech_lang/* $lang_dir/ || exit 1
    fi
    echo "Language model cached"
  else
    echo "Error: Could not find LibriSpeech language model"
    exit 1
  fi
  
  # Create universal G.fst if it doesn't exist
  if [ ! -f "$lang_dir/G.fst" ]; then
    echo "Creating universal G.fst..."
    g_fst_txt=$lang_dir/G.fst.txt
    {
      echo "0 1 <eps> <eps>"
      awk 'NR>1 {
        word = $1
        if (word != "<eps>" && word != "<s>" && word != "</s>" && word != "#0") {
          print "1 1", word, word, "0.0"
        }
      }' $lang_dir/words.txt
      echo "1"
    } > $g_fst_txt
    
    fstcompile --isymbols=$lang_dir/words.txt --osymbols=$lang_dir/words.txt \
      $g_fst_txt 2>/dev/null | \
      fstarcsort --sort_type=ilabel > $lang_dir/G.fst
    rm -f $g_fst_txt
    echo "Universal G.fst created"
  fi
  echo ""
fi

# Create common phrases file if it doesn't exist
if [ ! -f "$common_phrases_file" ]; then
  echo "Creating default common phrases file..."
  mkdir -p local
  cat > $common_phrases_file << 'EOF'
APPLE
HELLO
WORLD
GOOD MORNING
HOW ARE YOU
THANK YOU
PLEASE
YES
NO
EOF
  echo "Created: $common_phrases_file"
  echo "Edit this file to add your common phrases"
fi

echo "=== Creating single universal graph for all phrases ==="
echo ""
echo "Strategy: Create ONE shared graph that accepts any word sequence"
echo "This uses ~512MB total instead of 512MB per phrase"
echo ""

# Create a single universal graph that works for all phrases
shared_graph_dir=$cache_dir/graphs/universal

if [ -d "$shared_graph_dir" ] && [ -f "$shared_graph_dir/HCLG.fst" ]; then
  echo "✓ Universal graph already exists: $shared_graph_dir"
  echo "  Size: $(du -sh $shared_graph_dir | cut -f1)"
else
  echo "Creating universal alignment graph (one-time, ~3 minutes)..."
  echo "This graph will work for ALL phrases (any word sequence)"
  
  temp_graph_dir=exp/temp_universal_graph_$$
  mkdir -p $temp_graph_dir
  
  # Create the universal graph using the universal G.fst
  # The universal G.fst accepts any word sequence, so this graph works for all phrases
  $cmd $temp_graph_dir/log/mkgraph.log \
    utils/mkgraph.sh $lang_dir $model $temp_graph_dir/graph || {
    echo "Error: Failed to create universal graph"
    rm -rf $temp_graph_dir
    exit 1
  }
  
  if [ -f "$temp_graph_dir/graph/HCLG.fst" ]; then
    # Cache the universal graph
    mkdir -p $cache_dir/graphs
    cp -r $temp_graph_dir/graph $shared_graph_dir
    echo "✓ Universal graph created and cached: $shared_graph_dir"
    echo "  Size: $(du -sh $shared_graph_dir | cut -f1)"
  else
    echo "Error: Graph creation failed (HCLG.fst not found)"
    rm -rf $temp_graph_dir
    exit 1
  fi
  
  rm -rf $temp_graph_dir
fi

echo ""
echo "=== Verifying phrases are in vocabulary ==="
phrases_list=$(mktemp)
grep -v '^#' "$common_phrases_file" | grep -v '^$' > "$phrases_list"
total_phrases=$(wc -l < "$phrases_list")

if [ -f "$lang_dir/words.txt" ]; then
  missing_words=0
  while IFS= read -r phrase; do
    phrase=$(echo "$phrase" | tr '[:lower:]' '[:upper:]' | xargs)
    if [ -z "$phrase" ]; then continue; fi
    
    for word in $phrase; do
      if ! grep -q "^$word " "$lang_dir/words.txt"; then
        echo "  ⚠ Warning: '$word' not in vocabulary (from phrase: '$phrase')"
        missing_words=$((missing_words + 1))
      fi
    done
  done < "$phrases_list"
  
  if [ $missing_words -eq 0 ]; then
    echo "✓ All words in phrases are in vocabulary"
  else
    echo "⚠ $missing_words words not found in vocabulary"
    echo "  These words may cause alignment issues"
  fi
fi

rm -f "$phrases_list"

rm -f "$phrases_list"

echo ""
echo "=== Precomputation complete ==="
echo "Cached graphs: $(ls -1 $cache_dir/graphs | wc -l)"
echo "Cache directory: $cache_dir/graphs"
