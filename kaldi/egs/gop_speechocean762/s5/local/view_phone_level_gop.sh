#!/usr/bin/env bash

# View phone-level GOP scores with phone names
# Usage: ./local/view_phone_level_gop.sh <gop_scp_file>

if [ $# -lt 1 ]; then
  echo "Usage: $0 <gop_scp_file>"
  echo "Example: $0 exp/pronunciation_assessment_1768844631/gop/gop.scp"
  exit 1
fi

gop_scp=$1
lang_dir=$(dirname $(dirname $gop_scp))/lang_nosp

[ -f ./path.sh ] && . ./path.sh

# Get phone symbol table
phone_table=""
if [ -f "$lang_dir/phones-pure.txt" ]; then
  phone_table="$lang_dir/phones-pure.txt"
elif [ -f "$lang_dir/phones.txt" ]; then
  phone_table="$lang_dir/phones.txt"
else
  echo "Error: Cannot find phone symbol table"
  exit 1
fi

echo "=== Phone-Level GOP Scores ==="
echo ""
echo "Format: [Phone_ID Phone_Name GOP_Score]"
echo "GOP Interpretation:"
echo "  > 0: Excellent"
echo "  ≈ 0: Good"
echo "  < 0: Mispronounced (lower = worse)"
echo ""

# Extract GOP scores and map to phone names
copy-post "ark:$(head -1 $gop_scp | awk '{print $2}' | sed 's|ark:||')" ark,t:- 2>/dev/null | \
  grep -v "LOG\|Done" | while read line; do
    utt_id=$(echo "$line" | awk '{print $1}')
    echo "Utterance: $utt_id"
    echo ""
    
    # Extract phone IDs and GOP scores
    echo "$line" | sed 's/\[//g' | sed 's/\]//g' | awk '{
      for (i=2; i<=NF; i+=2) {
        phone_id = $i
        gop_score = $(i+1)
        if (phone_id != "" && gop_score != "") {
          # Get phone name from symbol table
          phone_name = "UNK"
          while ((getline phone_line < "'"$phone_table"'") > 0) {
            split(phone_line, parts, " ")
            if (parts[2] == phone_id) {
              phone_name = parts[1]
              break
            }
          }
          close("'"$phone_table"'")
          
          # Determine quality
          quality = "Poor"
          if (gop_score > 0) quality = "Excellent"
          else if (gop_score > -1) quality = "Good"
          else if (gop_score > -3) quality = "Fair"
          else if (gop_score > -5) quality = "Poor"
          else quality = "Very Poor"
          
          printf "  Phone %2d (%4s): GOP=%7.3f  [%s]\n", phone_id, phone_name, gop_score, quality
        }
      }
    }'
    echo ""
done
