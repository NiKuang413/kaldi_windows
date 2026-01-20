#!/usr/bin/env bash

# Copyright 2024
# Score a single audio file with text transcript for pronunciation assessment
# Usage: ./local/score_single_audio.sh <audio_file> <text_transcript> [output_dir]

set -e

# Support AUDIO_FILE and TEXT environment variables if arguments not provided
if [ $# -lt 2 ] || [ $# -gt 3 ]; then
  # Check if environment variables are set
  if [ -n "$AUDIO_FILE" ] && [ -n "$TEXT" ]; then
    echo "Using AUDIO_FILE and TEXT environment variables"
    audio_file="$AUDIO_FILE"
    text_transcript="$TEXT"
    output_dir=${OUTPUT_DIR:-exp/single_audio_$(date +%s)}
  else
    echo "Usage: $0 <audio_file> <text_transcript> [output_dir]"
    echo "  audio_file: WAV or MP3 file"
    echo "  text_transcript: Text transcription (e.g., 'HELLO WORLD')"
    echo "  output_dir: Optional output directory (default: exp/single_audio_$(date +%s))"
    echo ""
    echo "Alternatively, set environment variables:"
    echo "  export AUDIO_FILE=\"/path/to/audio.wav\""
    echo "  export TEXT=\"TRANSCRIPT\""
    echo "  $0"
    exit 1
  fi
else
  audio_file=$1
  text_transcript=$2
  output_dir=${3:-exp/single_audio_$(date +%s)}
  
  # If output_dir already exists, clean it (since we're processing one file at a time)
  if [ -d "$output_dir" ]; then
    echo "Output directory $output_dir already exists."
    echo "Cleaning previous data to avoid conflicts..."
    rm -rf "$output_dir"
    echo "Previous data removed. Starting fresh..."
    echo ""
  fi
fi

[ -f ./path.sh ] && . ./path.sh
[ -f ./cmd.sh ] && . ./cmd.sh

# Debug: Print the audio file variable and environment
echo "=========================================="
echo "DEBUG: Audio file variable check"
echo "=========================================="
echo "Script argument \$1 (audio_file): '$audio_file'"
echo "Environment variable AUDIO_FILE: '${AUDIO_FILE:-NOT SET}'"
echo "Full resolved path: $(realpath "$audio_file" 2>/dev/null || echo "Cannot resolve - may not exist")"
echo "Is regular file: $([ -f "$audio_file" ] && echo "YES" || echo "NO")"
echo "Is directory: $([ -d "$audio_file" ] && echo "YES" || echo "NO")"
echo "File size (if exists): $([ -f "$audio_file" ] && ls -lh "$audio_file" | awk '{print $5}' || echo "N/A")"
echo "=========================================="
echo ""

# Check if audio file exists (try case-insensitive if original not found)
# First, check if it's a directory (common mistake)
if [ -d "$audio_file" ]; then
  echo "Error: The provided path is a directory, not a file: $audio_file"
  echo "Please provide the full path to a WAV or MP3 audio file."
  exit 1
fi

if [ ! -f "$audio_file" ]; then
  # Try with different case extensions (only on the exact same path)
  base_file="${audio_file%.*}"
  echo "DEBUG: Original file not found, trying case variations..."
  echo "DEBUG: Base file path: $base_file"
  found_file=""
  for ext in wav WAV mp3 MP3; do
    candidate="${base_file}.${ext}"
    echo "DEBUG: Checking: $candidate"
    if [ -f "$candidate" ]; then
      echo "Found file with different case extension: $candidate"
      found_file="$candidate"
      break
    fi
  done
  
  if [ -n "$found_file" ]; then
    audio_file="$found_file"
  else
    # Final check - file doesn't exist
    echo "Error: Audio file not found: $audio_file"
    echo "Tried variations with .wav, .WAV, .mp3, .MP3 extensions"
    echo ""
    echo "Please verify:"
    echo "  1. The file path is correct"
    echo "  2. The file exists and is readable"
    echo "  3. You have permission to access the file"
    echo ""
    echo "Current working directory: $(pwd)"
    echo "Provided path: $audio_file"
    if [ -d "$(dirname "$audio_file")" ]; then
      echo "Directory exists: $(dirname "$audio_file")"
      echo "Files in directory:"
      ls -lh "$(dirname "$audio_file")" 2>/dev/null | head -10 || echo "  (cannot list directory)"
    else
      echo "Directory does not exist: $(dirname "$audio_file")"
    fi
    exit 1
  fi
fi

# Verify it's actually a file (not a directory that passed the check)
if [ ! -f "$audio_file" ]; then
  echo "Error: $audio_file is not a regular file"
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
# Convert text to uppercase for Kaldi dictionary matching
text_upper=$(echo "$text_transcript" | tr '[:lower:]' '[:upper:]')
echo "$utt_id $(realpath "$audio_file")" > $data_dir/wav.scp
echo "$utt_id $text_upper" > $data_dir/text
echo "$utt_id $utt_id" > $data_dir/utt2spk
echo "$utt_id $utt_id" > $data_dir/spk2utt

# Validate data directory
utils/validate_data_dir.sh --no-feats $data_dir || exit 1

echo "Prepared data directory: $data_dir"
echo "Utterance ID: $utt_id"
echo "Audio file: $audio_file"
echo "Audio file size: $(ls -lh "$audio_file" | awk '{print $5}')"
echo "Audio file exists: YES"
echo "Text: $text_transcript (normalized to: $text_upper)"

# Get paths to LibriSpeech model
librispeech_eg=../../librispeech/s5
model=$librispeech_eg/exp/nnet3_cleaned/tdnn_sp
ivector_extractor=$librispeech_eg/exp/nnet3_cleaned/extractor
lang=$librispeech_eg/data/lang
lang_nosp=$librispeech_eg/data/lang_nosp

# Check if model exists
if [ ! -f "$model/final.mdl" ]; then
  echo "Error: Model not found at $model/final.mdl"
  echo "Please train the LibriSpeech nnet3 TDNN model first."
  exit 1
fi

# Stage 1: Extract high-resolution MFCC features
echo "=== Stage 1: Extracting MFCC features ==="
steps/make_mfcc.sh --nj 1 --mfcc-config conf/mfcc_hires.conf \
  --cmd "$cmd" $data_dir $output_dir/make_mfcc $output_dir/mfcc || exit 1
steps/compute_cmvn_stats.sh $data_dir $output_dir/make_mfcc $output_dir/mfcc || exit 1
utils/fix_data_dir.sh $data_dir || exit 1

# Stage 2: Extract i-vectors
echo "=== Stage 2: Extracting i-vectors ==="
if [ ! -d "$ivector_extractor" ]; then
  echo "Error: i-vector extractor not found at $ivector_extractor"
  exit 1
fi
steps/online/nnet2/extract_ivectors_online.sh --cmd "$cmd" --nj 1 \
  $data_dir $ivector_extractor $data_dir/ivectors || exit 1

# Stage 3: Compute neural network output probabilities
echo "=== Stage 3: Computing neural network outputs ==="
steps/nnet3/compute_output.sh --cmd "$cmd" --nj 1 \
  --online-ivector-dir $data_dir/ivectors \
  $data_dir $model $output_dir/probs || exit 1

# Stage 4: Prepare language model (if not exists)
lang_dir=$output_dir/lang_nosp
if [ ! -f "$lang_dir/L.fst" ] && [ ! -f "$lang_dir/G.fst" ]; then
  echo "=== Stage 4: Preparing language model ==="
  
  # Use LibriSpeech language model if available (preferred)
  # Try to find one with G.fst first (needed for alignment), then lang_nosp, then lang
  librispeech_lang=""
  if [ -f "$librispeech_eg/data/lang_nosp_test_tgsmall/G.fst" ]; then
    librispeech_lang="$librispeech_eg/data/lang_nosp_test_tgsmall"
    echo "Using LibriSpeech language model from lang_nosp_test_tgsmall (has G.fst)"
  elif [ -f "$librispeech_eg/data/lang_nosp_test_tgmed/G.fst" ]; then
    librispeech_lang="$librispeech_eg/data/lang_nosp_test_tgmed"
    echo "Using LibriSpeech language model from lang_nosp_test_tgmed (has G.fst)"
  elif [ -d "$lang_nosp" ] && [ -f "$lang_nosp/L.fst" ]; then
    librispeech_lang="$lang_nosp"
    echo "Using LibriSpeech language model from lang_nosp"
  elif [ -d "$lang" ] && [ -f "$lang/L.fst" ]; then
    librispeech_lang="$lang"
    echo "Using LibriSpeech language model from lang"
  fi
  
  if [ -n "$librispeech_lang" ]; then
    mkdir -p $lang_dir
    # Copy all files and directories, including phones directory
    # Use rsync if available for more reliable copying, otherwise use cp
    if command -v rsync >/dev/null 2>&1; then
      rsync -a $librispeech_lang/ $lang_dir/ || exit 1
    else
      cp -r $librispeech_lang/* $lang_dir/ || exit 1
      # Ensure phones directory was copied (sometimes cp -r * misses it)
      if [ ! -d "$lang_dir/phones" ] && [ -d "$librispeech_lang/phones" ]; then
        cp -r $librispeech_lang/phones $lang_dir/ || exit 1
      fi
    fi
    echo "Successfully copied LibriSpeech language model"
    # Verify copy was successful
    if [ -f "$lang_dir/L.fst" ]; then
      echo "Language model verified, skipping dictionary preparation"
      # Create trivial G.fst for alignment if it doesn't exist
      if [ ! -f "$lang_dir/G.fst" ]; then
        echo "Creating trivial grammar FST (G.fst) for alignment"
        # Create a trivial unigram grammar that allows any word sequence
        # This is sufficient for force alignment
        # Use make_unigram_lm.sh if available, otherwise create minimal G.fst
        if [ -f utils/make_unigram_lm.sh ]; then
          # Create a unigram LM from the words in the transcript (use uppercase)
          echo "$text_upper" | utils/make_unigram_lm.sh $lang_dir $lang_dir/G.fst 2>/dev/null || {
            echo "make_unigram_lm.sh failed, creating minimal G.fst"
            # Fall through to minimal creation
          }
        fi
        
        # If G.fst still doesn't exist, create a minimal one
        if [ ! -f "$lang_dir/G.fst" ]; then
          # Create minimal grammar: state 0 accepts any word and loops
          # Format: from_state to_state input_word output_word [weight]
          {
            echo "0 0 <eps> <eps>"
            # Add transitions for all words (self-loop)
            awk 'NR>1 && $1 != "<eps>" && $1 != "<s>" && $1 != "</s>" && $1 != "#0" {
              print "0 0", $1, $1, "0.0"
            }' $lang_dir/words.txt
            echo "0"
          } | fstcompile --isymbols=$lang_dir/words.txt --osymbols=$lang_dir/words.txt 2>/dev/null | \
            fstarcsort --sort_type=ilabel > $lang_dir/G.fst || {
            # Last resort: create absolute minimal G.fst
            echo "0 0 <eps> <eps>" > $lang_dir/G.fst.txt
            echo "0" >> $lang_dir/G.fst.txt
            fstcompile --isymbols=$lang_dir/words.txt --osymbols=$lang_dir/words.txt \
              $lang_dir/G.fst.txt 2>/dev/null | fstarcsort --sort_type=ilabel > $lang_dir/G.fst
            rm -f $lang_dir/G.fst.txt
          }
        fi
        echo "Created trivial G.fst for alignment"
      fi
    else
      echo "Warning: Language model copy may have failed, will prepare from scratch"
      # Fall through to preparation
    fi
  fi
  
  # Prepare from scratch if language model doesn't exist
  if [ ! -f "$lang_dir/L.fst" ] && [ ! -f "$lang_dir/G.fst" ]; then
    # Otherwise, prepare from scratch
    mkdir -p $output_dir/local/dict_nosp
    
    # Copy lexicon from LibriSpeech if available
    if [ -f "$librispeech_eg/data/local/dict/lexicon.txt" ]; then
      cp $librispeech_eg/data/local/dict/lexicon.txt $output_dir/local/dict_nosp/lexicon.txt
    elif [ -f "$librispeech_eg/data/local/dict_nosp/lexicon.txt" ]; then
      cp $librispeech_eg/data/local/dict_nosp/lexicon.txt $output_dir/local/dict_nosp/lexicon.txt
    else
      echo "Warning: Using default lexicon. For better results, use LibriSpeech lexicon."
      # Create minimal lexicon - use LibriSpeech phone set if available
      if [ -f "$librispeech_eg/data/local/dict_nosp/lexicon.txt" ]; then
        # Use LibriSpeech lexicon as base and filter for words we need
        # Use uppercase text for dictionary lookup
        grep -E "^($(echo $text_upper | tr ' ' '|')) " $librispeech_eg/data/local/dict_nosp/lexicon.txt > $output_dir/local/dict_nosp/lexicon.txt 2>/dev/null || {
          # If grep fails, create minimal
          echo "!SIL SIL" > $output_dir/local/dict_nosp/lexicon.txt
          echo "<SPOKEN_NOISE> SPN" >> $output_dir/local/dict_nosp/lexicon.txt
          echo "<UNK> SPN" >> $output_dir/local/dict_nosp/lexicon.txt
          for word in $text_upper; do
            # Try to find word in LibriSpeech lexicon
            grep "^$word " $librispeech_eg/data/local/dict_nosp/lexicon.txt >> $output_dir/local/dict_nosp/lexicon.txt 2>/dev/null || echo "$word SPN" >> $output_dir/local/dict_nosp/lexicon.txt
          done
        }
      else
        # Create minimal lexicon (you may need to expand this)
        echo "!SIL SIL" > $output_dir/local/dict_nosp/lexicon.txt
        echo "<SPOKEN_NOISE> SPN" >> $output_dir/local/dict_nosp/lexicon.txt
        echo "<UNK> SPN" >> $output_dir/local/dict_nosp/lexicon.txt
        # Add words from transcript (use uppercase)
        for word in $text_upper; do
          echo "$word SPN" >> $output_dir/local/dict_nosp/lexicon.txt
        done
      fi
    fi
    
    # Prepare dictionary
    if [ -f local/prepare_dict.sh ]; then
      local/prepare_dict.sh $output_dir/local/dict_nosp/lexicon.txt $output_dir/local/dict_nosp || exit 1
    else
      # Use LibriSpeech dictionary preparation
      $librispeech_eg/local/prepare_dict.sh $output_dir/local/dict_nosp/lexicon.txt $output_dir/local/dict_nosp || exit 1
    fi
    
    # Prepare language
    utils/prepare_lang.sh --phone-symbol-table $lang/phones.txt \
      $output_dir/local/dict_nosp "<UNK>" $output_dir/local/lang_tmp_nosp $lang_dir || exit 1
  fi
fi

# Ensure G.fst exists (needed for alignment graph)
if [ -f "$lang_dir/L.fst" ] && [ ! -f "$lang_dir/G.fst" ]; then
  echo "=== Creating G.fst for alignment ==="
  # Create trivial G.fst for alignment - a grammar that accepts any word sequence
  # This is sufficient for force alignment
  g_fst_txt=$lang_dir/G.fst.txt
  {
    # Start state with epsilon transition to loop state
    echo "0 1 <eps> <eps>"
    # Loop state: self-loop for all words (allows any word sequence)
    # Skip special symbols: <eps>, <s>, </s>, #0
    awk 'NR>1 {
      word = $1
      if (word != "<eps>" && word != "<s>" && word != "</s>" && word != "#0") {
        print "1 1", word, word, "0.0"
      }
    }' $lang_dir/words.txt
    # Loop state is final
    echo "1"
  } > $g_fst_txt
  
  # Compile the FST
  fstcompile --isymbols=$lang_dir/words.txt --osymbols=$lang_dir/words.txt \
    $g_fst_txt 2>/dev/null | \
    fstarcsort --sort_type=ilabel > $lang_dir/G.fst || {
    echo "Warning: Failed to create G.fst with word loop, trying minimal grammar"
    # Fallback: minimal grammar (just accepts empty string)
    {
      echo "0 0 <eps> <eps>"
      echo "0"
    } > $g_fst_txt
    fstcompile --isymbols=$lang_dir/words.txt --osymbols=$lang_dir/words.txt \
      $g_fst_txt 2>/dev/null | \
      fstarcsort --sort_type=ilabel > $lang_dir/G.fst
  }
  rm -f $g_fst_txt
  
  if [ -f "$lang_dir/G.fst" ]; then
    echo "Successfully created G.fst for alignment"
  else
    echo "Error: Failed to create G.fst. Cannot proceed with alignment."
    exit 1
  fi
fi

# Stage 5: Force alignment
echo "=== Stage 5: Force alignment ==="
ali_dir=$output_dir/ali
mkdir -p $ali_dir

# OPTIMIZATION: Use shared universal graph (works for all phrases)
# This reduces Stage 5 from ~3 minutes to ~2 seconds
# Storage: ONE 512MB file instead of 512MB per phrase
cache_dir=${PRONUNCIATION_CACHE_DIR:-exp/pronunciation_cache}
shared_graph=$cache_dir/graphs/universal

if [ -d "$shared_graph" ] && [ -f "$shared_graph/HCLG.fst" ]; then
  echo "Using shared universal graph (works for all phrases, instant)."
  cp -r "$shared_graph" "$ali_dir/graph"
else
  echo "Shared universal graph not found. Creating it (one-time, ~3 minutes)..."
  echo "This graph will work for ALL future phrases."
  # Create alignment graph using universal G.fst
  $cmd $ali_dir/log/mkgraph.log \
    utils/mkgraph.sh $lang_dir $model $ali_dir/graph || exit 1
  
  # Cache as universal graph for future use
  mkdir -p $cache_dir/graphs
  cp -r "$ali_dir/graph" "$shared_graph"
  echo "Universal graph created and cached. Future runs will be instant."
fi

# Force align
# Use GPU if available (much faster), fallback to CPU if GPU not available
if command -v nvidia-smi >/dev/null 2>&1 && cuda-compiled 2>/dev/null; then
  echo "Using GPU for alignment (faster)"
  gpu_opt="--use-gpu true"
else
  echo "Using CPU for alignment (GPU not available or Kaldi not CUDA-compiled)"
  gpu_opt="--use-gpu false"
fi

$cmd $ali_dir/log/align.log \
  steps/nnet3/align.sh --nj 1 $gpu_opt \
  --online-ivector-dir $data_dir/ivectors \
  $data_dir $lang_dir $model $ali_dir || exit 1

# Stage 6: Convert alignments to phone IDs
echo "=== Stage 6: Converting alignments to phone IDs ==="
ali_phone_dir=$output_dir/ali_phone
mkdir -p $ali_phone_dir

ali-to-phones --per-frame=true $model/final.mdl \
  "ark:gunzip -c $ali_dir/ali.1.gz|" \
  "ark:|gzip -c > $ali_phone_dir/ali-phone.1.gz" || exit 1

# Stage 7: Prepare phone mapping (remove stress markers)
echo "=== Stage 7: Preparing phone mapping ==="
phone_map=$lang_dir/phone-to-pure-phone.int
if [ ! -f "$phone_map" ]; then
  if [ -f local/remove_phone_markers.pl ]; then
    local/remove_phone_markers.pl $lang_dir/phones.txt \
      $lang_dir/phones-pure.txt $phone_map || exit 1
  else
    # Create identity mapping if script not available
    awk '{print $1, $1}' $lang_dir/phones.txt > $phone_map
  fi
fi

# Stage 8: Compute GOP scores
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

echo ""
echo "=== GOP Computation Complete ==="
echo "GOP scores saved to: $gop_dir/gop.scp"
echo "Features saved to: $gop_dir/feat.scp"

# Stage 9: Compute utterance-level score
# Use Medium article method (ML-based) if model available, otherwise use simple aggregation
echo ""
echo "=== Stage 9: Computing utterance-level score ==="

# Check if trained model is available (Medium article method)
pronunciation_model=${PRONUNCIATION_MODEL:-exp/pronunciation_model.pkl}
use_ml_method=false

if [ -f "$pronunciation_model" ] && [ -f local/feat_to_score_eval.py ]; then
  echo "Using Medium article method (ML-based regression model)"
  echo "Model: $pronunciation_model"
  use_ml_method=true
  
  # Use trained model to predict scores from GOP features
  # Note: feat.scp contains GOP-based features (not just GOP scores)
  if [ -f "$gop_dir/feat.scp" ]; then
    python3 local/feat_to_score_eval.py \
      "$pronunciation_model" \
      "$gop_dir/feat.scp" \
      "$output_dir/phone_scores_ml.txt" || {
      echo "Warning: ML-based scoring failed, falling back to simple method"
      use_ml_method=false
    }
    
    if [ "$use_ml_method" = true ] && [ -f "$output_dir/phone_scores_ml.txt" ]; then
      # Aggregate phone-level ML scores to utterance level
      if [ -f local/aggregate_ml_scores.py ]; then
        python3 local/aggregate_ml_scores.py \
          "$output_dir/phone_scores_ml.txt" \
          "$output_dir/utterance_score.txt" || use_ml_method=false
      else
        # Simple aggregation: average of phone scores
        awk '{sum+=$2; count++} END {if(count>0) print "single_utt", sum/count, count}' \
          "$output_dir/phone_scores_ml.txt" > "$output_dir/utterance_score.txt" || use_ml_method=false
      fi
      
      if [ "$use_ml_method" = true ]; then
        echo "ML-based utterance score saved to: $output_dir/utterance_score.txt"
        echo "Phone-level ML scores saved to: $output_dir/phone_scores_ml.txt"
      fi
    fi
  else
    echo "Warning: feat.scp not found, falling back to simple method"
    use_ml_method=false
  fi
fi

# Fallback to simple aggregation method
if [ "$use_ml_method" = false ]; then
  echo "Using simple aggregation method (mean/median of GOP scores)"
  if [ -f local/aggregate_utterance_scores.py ]; then
    python3 local/aggregate_utterance_scores.py \
      $gop_dir/gop.scp \
      $output_dir/utterance_score.txt || exit 1
    echo "Utterance score saved to: $output_dir/utterance_score.txt"
  else
    echo "Warning: aggregate_utterance_scores.py not found, skipping utterance score"
  fi
fi

# Stage 10: Convert to pronunciation score (0-100)
echo ""
echo "=== Stage 10: Converting to pronunciation score (0-100) ==="
if [ -f local/compute_pronunciation_score.py ] && [ -f $output_dir/utterance_score.txt ]; then
  # For ML method, scores are already in 0-2 range (human expert scale)
  # For simple method, convert from GOP scale
  if [ "$use_ml_method" = true ]; then
    # ML scores are already in human expert scale (0-2), convert to 0-100
    python3 -c "
import sys
with open('$output_dir/utterance_score.txt', 'r') as f:
    line = f.readline().strip()
    if line:
        parts = line.split()
        if len(parts) >= 2:
            score = float(parts[1])
            # Convert 0-2 scale to 0-100
            score_100 = (score / 2.0) * 100
            print(f'{parts[0]}\t{score:.2f}\t{score_100:.1f}/100')
" > "$output_dir/pronunciation_score.txt" || {
      # Fallback to standard conversion
      python3 local/compute_pronunciation_score.py \
        $output_dir/utterance_score.txt \
        --output $output_dir/pronunciation_score.txt || exit 1
    }
  else
    # Simple method: use standard GOP to 0-100 conversion
    python3 local/compute_pronunciation_score.py \
      $output_dir/utterance_score.txt \
      --output $output_dir/pronunciation_score.txt || exit 1
  fi
  echo "Pronunciation score saved to: $output_dir/pronunciation_score.txt"
else
  echo "Warning: compute_pronunciation_score.py not found or utterance_score.txt missing"
fi

# Display results
echo ""
echo "======================================================================"
echo "=== PRONUNCIATION ASSESSMENT RESULTS ==="
echo "======================================================================"
echo ""

# Display phone-level GOP scores
if [ -f local/show_gop_scores.sh ]; then
  echo "--- Phone-Level GOP Scores ---"
  ./local/show_gop_scores.sh $gop_dir/gop.scp
  echo ""
fi

# Display utterance-level score
if [ -f $output_dir/utterance_score.txt ]; then
  echo "--- Utterance-Level Score ---"
  cat $output_dir/utterance_score.txt | awk '{
    if (NF >= 2 && $1 !~ /^#/) {
      printf "Utterance: %s\n", $1
      printf "  GOP Score: %.4f\n", $2
      if (NF >= 3) printf "  Number of phones: %s\n", $3
      if (NF >= 4) printf "  Worst phone GOP: %.4f\n", $4
      if (NF >= 5) printf "  Best phone GOP: %.4f\n", $5
      if (NF >= 6) printf "  Standard deviation: %.4f\n", $6
    }
  }'
  echo ""
fi

# Display pronunciation score (0-100)
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
  
  # Show average if available
  avg_score=$(grep "Average Pronunciation Score" $output_dir/pronunciation_score.txt | awk '{print $NF}' | sed 's|/100||')
  if [ -n "$avg_score" ]; then
    echo "Average Pronunciation Score: ${avg_score}/100"
    echo ""
  fi
fi

echo "======================================================================"
echo "Results saved in: $output_dir"
echo "======================================================================"
