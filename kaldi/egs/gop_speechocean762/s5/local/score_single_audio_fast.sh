#!/usr/bin/env bash

# Copyright 2024
# Optimized version for live/real-time pronunciation assessment
# Precomputes and caches expensive operations
# Usage: ./local/score_single_audio_fast.sh <audio_file> <text_transcript> [output_dir] [cache_dir]

set -e

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
  echo "Usage: $0 <audio_file> <text_transcript> [output_dir] [cache_dir]"
  echo "  audio_file: WAV or MP3 file"
  echo "  text_transcript: Text transcription (e.g., 'HELLO WORLD')"
  echo "  output_dir: Optional output directory (default: exp/single_audio_$(date +%s))"
  echo "  cache_dir: Optional cache directory for precomputed graphs (default: exp/pronunciation_cache)"
  exit 1
fi

audio_file=$1
text_transcript=$2
output_dir=${3:-exp/single_audio_$(date +%s)}
cache_dir=${4:-exp/pronunciation_cache}

[ -f ./path.sh ] && . ./path.sh
[ -f ./cmd.sh ] && . ./cmd.sh

# Create cache directory for precomputed resources
mkdir -p $cache_dir

# Get paths to LibriSpeech model
librispeech_eg=../../librispeech/s5
model=$librispeech_eg/exp/nnet3_cleaned/tdnn_sp
ivector_extractor=$librispeech_eg/exp/nnet3_cleaned/extractor
lang=$librispeech_eg/data/lang
lang_nosp=$librispeech_eg/data/lang_nosp

# Check if audio file exists
if [ ! -f "$audio_file" ]; then
  echo "Error: Audio file not found: $audio_file"
  exit 1
fi

# Convert MP3 to WAV if needed
audio_ext="${audio_file##*.}"
if [ "${audio_ext,,}" = "mp3" ]; then
  echo "Converting MP3 to WAV..."
  wav_file="${audio_file%.*}.wav"
  if ! command -v ffmpeg &> /dev/null; then
    echo "Error: ffmpeg not found. Please install ffmpeg to convert MP3 files."
    exit 1
  fi
  ffmpeg -i "$audio_file" -ar 16000 -ac 1 -f wav "$wav_file" 2>/dev/null
  audio_file="$wav_file"
fi

# Create output directory
mkdir -p $output_dir
data_dir=$output_dir/data
mkdir -p $data_dir

# Generate utterance ID
utt_id="single_utt_$(basename "$audio_file" | sed 's/\.[^.]*$//' | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:]_')"

# Prepare Kaldi data directory
text_upper=$(echo "$text_transcript" | tr '[:lower:]' '[:upper:]')
echo "$utt_id $(realpath "$audio_file")" > $data_dir/wav.scp
echo "$utt_id $text_upper" > $data_dir/text
echo "$utt_id $utt_id" > $data_dir/utt2spk
echo "$utt_id $utt_id" > $data_dir/spk2utt

utils/validate_data_dir.sh --no-feats $data_dir || exit 1

echo "Prepared data directory: $data_dir"
echo "Utterance ID: $utt_id"
echo "Audio file: $audio_file"
echo "Text: $text_transcript (normalized to: $text_upper)"

# ============================================
# OPTIMIZATION 1: Use shared/cached language model
# ============================================
lang_dir=$cache_dir/lang_nosp
if [ ! -f "$lang_dir/L.fst" ]; then
  echo "=== Setting up cached language model (one-time setup) ==="
  mkdir -p $lang_dir
  
  # Use LibriSpeech language model
  librispeech_lang=""
  if [ -f "$librispeech_eg/data/lang_nosp_test_tgsmall/G.fst" ]; then
    librispeech_lang="$librispeech_eg/data/lang_nosp_test_tgsmall"
  elif [ -f "$librispeech_eg/data/lang_nosp_test_tgmed/G.fst" ]; then
    librispeech_lang="$librispeech_eg/data/lang_nosp_test_tgmed"
  elif [ -d "$lang_nosp" ] && [ -f "$lang_nosp/L.fst" ]; then
    librispeech_lang="$lang_nosp"
  fi
  
  if [ -n "$librispeech_lang" ]; then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a $librispeech_lang/ $lang_dir/ || exit 1
    else
      cp -r $librispeech_lang/* $lang_dir/ || exit 1
    fi
    echo "Language model cached in: $lang_dir"
  fi
  
  # Create universal G.fst (accepts any word sequence) - done once
  if [ ! -f "$lang_dir/G.fst" ]; then
    echo "Creating universal G.fst (one-time setup)..."
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
    echo "Universal G.fst created and cached"
  fi
fi

# ============================================
# OPTIMIZATION 2: Cache alignment graphs by text
# ============================================
# Create a hash of the text for cache lookup
text_hash=$(echo -n "$text_upper" | md5sum | cut -d' ' -f1)
graph_cache=$cache_dir/graphs/$text_hash

if [ -d "$graph_cache" ] && [ -f "$graph_cache/HCLG.fst" ]; then
  echo "=== Using cached alignment graph for this text ==="
  ali_dir=$output_dir/ali
  mkdir -p $ali_dir
  cp -r $graph_cache $ali_dir/graph
  echo "Graph loaded from cache (saved ~3 minutes)"
else
  echo "=== Creating alignment graph (will be cached for future use) ==="
  ali_dir=$output_dir/ali
  mkdir -p $ali_dir
  
  # Create graph
  $cmd $ali_dir/log/mkgraph.log \
    utils/mkgraph.sh $lang_dir $model $ali_dir/graph || exit 1
  
  # Cache the graph for future use
  mkdir -p $cache_dir/graphs
  cp -r $ali_dir/graph $graph_cache
  echo "Graph cached for future use: $graph_cache"
fi

# ============================================
# Fast stages (already optimized)
# ============================================
echo "=== Stage 1: Extracting MFCC features ==="
steps/make_mfcc.sh --nj 1 --mfcc-config conf/mfcc_hires.conf \
  --cmd "$cmd" $data_dir $output_dir/make_mfcc $output_dir/mfcc || exit 1
steps/compute_cmvn_stats.sh $data_dir $output_dir/make_mfcc $output_dir/mfcc || exit 1
utils/fix_data_dir.sh $data_dir || exit 1

echo "=== Stage 2: Extracting i-vectors ==="
steps/online/nnet2/extract_ivectors_online.sh --cmd "$cmd" --nj 1 \
  $data_dir $ivector_extractor $data_dir/ivectors || exit 1

echo "=== Stage 3: Computing neural network outputs ==="
steps/nnet3/compute_output.sh --cmd "$cmd" --nj 1 \
  --online-ivector-dir $data_dir/ivectors \
  $data_dir $model $output_dir/probs || exit 1

echo "=== Stage 5: Force alignment (using cached graph) ==="
# Use GPU if available
if command -v nvidia-smi >/dev/null 2>&1 && cuda-compiled 2>/dev/null; then
  echo "Using GPU for alignment (faster)"
  gpu_opt="--use-gpu true"
else
  echo "Using CPU for alignment"
  gpu_opt="--use-gpu false"
fi

$cmd $ali_dir/log/align.log \
  steps/nnet3/align.sh --nj 1 $gpu_opt \
  --online-ivector-dir $data_dir/ivectors \
  $data_dir $lang_dir $model $ali_dir || exit 1

echo "=== Stage 6: Converting alignments to phone IDs ==="
ali_phone_dir=$output_dir/ali_phone
mkdir -p $ali_phone_dir

ali-to-phones --per-frame=true $model/final.mdl \
  "ark:gunzip -c $ali_dir/ali.1.gz|" \
  "ark:|gzip -c > $ali_phone_dir/ali-phone.1.gz" || exit 1

echo "=== Stage 7: Preparing phone mapping ==="
phone_map=$lang_dir/phone-to-pure-phone.int
if [ ! -f "$phone_map" ]; then
  if [ -f local/remove_phone_markers.pl ]; then
    local/remove_phone_markers.pl $lang_dir/phones.txt \
      $lang_dir/phones-pure.txt $phone_map || exit 1
  else
    awk '{print $1, $1}' $lang_dir/phones.txt > $phone_map
  fi
fi

echo "=== Stage 8: Computing GOP scores ==="
gop_dir=$output_dir/gop
mkdir -p $gop_dir

compute-gop --phone-map=$phone_map \
  --skip-phones-string=0:1:2 \
  $model/final.mdl \
  "ark:gunzip -c $ali_dir/ali.1.gz|" \
  "ark:gunzip -c $ali_phone_dir/ali-phone.1.gz|" \
  "ark:$output_dir/probs/output.1.ark" \
  "ark,scp:$gop_dir/gop.1.ark,$gop_dir/gop.1.scp" \
  "ark,scp:$gop_dir/feat.1.ark,$gop_dir/feat.1.scp" || exit 1

cat $gop_dir/gop.*.scp > $gop_dir/gop.scp
cat $gop_dir/feat.*.scp > $gop_dir/feat.scp

echo "=== Stage 9: Computing utterance-level score ==="
if [ -f local/aggregate_utterance_scores.py ]; then
  python3 local/aggregate_utterance_scores.py \
    $gop_dir/gop.scp \
    $output_dir/utterance_score.txt || exit 1
fi

echo "=== Stage 10: Converting to pronunciation score (0-100) ==="
if [ -f local/compute_pronunciation_score.py ] && [ -f $output_dir/utterance_score.txt ]; then
  python3 local/compute_pronunciation_score.py \
    $output_dir/utterance_score.txt \
    --output $output_dir/pronunciation_score.txt || exit 1
fi

# Display results
echo ""
echo "======================================================================"
echo "=== PRONUNCIATION ASSESSMENT RESULTS ==="
echo "======================================================================"
echo ""

if [ -f $output_dir/pronunciation_score.txt ]; then
  echo "--- Pronunciation Score (0-100) ---"
  cat $output_dir/pronunciation_score.txt | grep -v "^#" | grep -v "^$" | head -1 | awk '{
    if (NF >= 3) {
      printf "Utterance: %s\n", $1
      printf "  GOP Score: %s\n", $2
      printf "  Pronunciation Score: %s/100\n", $3
      if (NF >= 5) printf "  Grade: %s\n", $5
    }
  }'
  echo ""
fi

echo "======================================================================"
echo "Results saved in: $output_dir"
echo "Cache directory: $cache_dir"
echo "======================================================================"
