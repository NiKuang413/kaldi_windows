#!/usr/bin/env bash
# Train regression model to convert GOP features to human expert scores
# This implements the Medium article method: train a model on all phonemes from all voices/scores

set -e

[ -f ./path.sh ] && . ./path.sh
[ -f ./cmd.sh ] && . ./cmd.sh

# Default paths
data_dir=${1:-data/train}
human_scoring_json=${2:-data/local/scores.json}
model_output=${3:-exp/pronunciation_model.pkl}
feature_scp=${4:-exp/gop_train/feat.scp}
phone_symbol_table=${5:-data/lang_nosp/phones-pure.txt}

echo "=== Training Pronunciation Assessment Model (Medium Article Method) ==="
echo ""
echo "This trains a regression model (Random Forest) to convert GOP features"
echo "to human expert scores, as described in the Medium article."
echo ""
echo "Inputs:"
echo "  Training data: $data_dir"
echo "  Human scores: $human_scoring_json"
echo "  GOP features: $feature_scoring_json"
echo "  Model output: $model_output"
echo ""

# Check if human scoring JSON exists
if [ ! -f "$human_scoring_json" ]; then
  echo "Error: Human scoring JSON file not found: $human_scoring_json"
  echo ""
  echo "This file should contain human expert scores in JSON format."
  echo "Format:"
  echo '  {'
  echo '    "utterance_id": {'
  echo '      "words": ['
  echo '        {'
  echo '          "phones": ["P", "AH", "L", "IY", "Z"],'
  echo '          "phones-accuracy": [2.0, 2.0, 1.0, 2.0, 2.0]'
  echo '        }'
  echo '      ]'
  echo '    }'
  echo '  }'
  echo ""
  echo "If you have SpeechOcean762 dataset, the file should be at:"
  echo "  data/local/scores.json"
  echo ""
  echo "To download SpeechOcean762:"
  echo "  cd ~/ASRProject/kaldi/egs/gop_speechocean762/s5"
  echo "  local/download_and_untar.sh www.openslr.org/resources/101 /path/to/data"
  exit 1
fi

# Check if feature SCP exists
if [ ! -f "$feature_scp" ]; then
  echo "Error: GOP feature file not found: $feature_scp"
  echo ""
  echo "You need to run the GOP pipeline first to generate features:"
  echo "  1. Run: ./run.sh (stages 1-8 to compute GOP features)"
  echo "  2. Features will be at: exp/gop_train/feat.scp"
  echo ""
  echo "Or if you already have features, specify the path:"
  echo "  $0 $data_dir $human_scoring_json $model_output /path/to/feat.scp"
  exit 1
fi

# Check if training script exists
train_script=local/tuning/feat_to_score_train_1a.py
if [ ! -f "$train_script" ]; then
  echo "Error: Training script not found: $train_script"
  exit 1
fi

echo "Training model..."
echo "  Method: Random Forest Regressor"
echo "  Features: GOP-based features from $feature_scp"
echo "  Labels: Human expert scores from $human_scoring_json"
echo ""

# Train the model
python3 $train_script \
  --phone-symbol-table "$phone_symbol_table" \
  --nj $(nproc) \
  "$feature_scp" \
  "$human_scoring_json" \
  "$model_output" || {
  echo "Error: Model training failed"
  exit 1
}

if [ -f "$model_output" ]; then
  echo ""
  echo "=== Model Training Complete ==="
  echo "Model saved to: $model_output"
  echo ""
  echo "You can now use this model in score_single_audio.sh:"
  echo "  export PRONUNCIATION_MODEL=$model_output"
  echo "  ./local/score_single_audio.sh <audio_file> <text>"
  echo ""
  echo "Or the script will automatically use it if placed at:"
  echo "  exp/pronunciation_model.pkl"
else
  echo "Error: Model file not created"
  exit 1
fi
