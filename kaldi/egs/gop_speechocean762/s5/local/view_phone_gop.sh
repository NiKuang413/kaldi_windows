#!/usr/bin/env bash

# View phone-level GOP scores with phone names
# Usage: ./local/view_phone_gop.sh <gop_scp_file>

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

# Get ark path from scp file (remove offset like :21)
ark_path=$(head -1 $gop_scp | awk '{print $2}' | sed 's|ark:||' | sed 's|:.*||')

echo "=== Phone-Level GOP Scores ==="
echo ""
echo "Format: [Phone_ID Phone_Name GOP_Score Quality]"
echo "GOP Interpretation:"
echo "  > 0:  Excellent"
echo "  ≈ 0:  Good"
echo "  < 0:  Mispronounced (lower = worse)"
echo ""

# Get GOP data
gop_data=$(copy-post "ark:$ark_path" ark,t:- 2>&1 | grep -E "\[.*\]" | grep -v "LOG\|Done\|WARNING\|ERROR\|copy-post")

if [ -z "$gop_data" ]; then
  echo "Error: Could not extract GOP data"
  exit 1
fi

# Process with Python
export PHONE_TABLE="$phone_table"
echo "$gop_data" | python3 << 'PYEOF'
import re
import sys

# Load phone symbol table from environment
import os
phone_table = os.environ.get('PHONE_TABLE', '')

phone_map = {}
if phone_table and os.path.exists(phone_table):
    try:
        with open(phone_table, 'r') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 2:
                    phone_map[parts[1]] = parts[0]
    except:
        pass

# Parse input
for line in sys.stdin:
    line = line.strip()
    if not line or '[' not in line or ']' not in line:
        continue
    
    parts = line.split()
    if len(parts) < 2:
        continue
    
    utt_id = parts[0]
    print(f"\n{'='*70}")
    print(f"Utterance: {utt_id}")
    print(f"{'='*70}")
    print(f"{'Phone ID':<12} {'Phone Name':<20} {'GOP Score':<15} {'Quality':<15}")
    print(f"{'-'*70}")
    
    # Extract [phone_id gop_score] pairs
    matches = re.findall(r'\[\s*(\d+)\s+([-\d.]+)\s*\]', line)
    
    if not matches:
        print("No GOP scores found in line")
        continue
    
    for phone_id_str, gop_str in matches:
        phone_id_int = int(phone_id_str)
        gop_score = float(gop_str)
        phone_name = phone_map.get(str(phone_id_int), "UNK")
        
        if gop_score > 0:
            quality = "Excellent"
        elif gop_score > -1:
            quality = "Good"
        elif gop_score > -3:
            quality = "Fair"
        elif gop_score > -5:
            quality = "Poor"
        else:
            quality = "Very Poor"
        
        print(f"{phone_id_int:<12} {phone_name:<20} {gop_score:<15.3f} {quality:<15}")
    
    print(f"{'='*70}\n")
    
    # Summary
    gop_scores = [float(gop) for _, gop in matches]
    print("Summary:")
    print(f"  Total phones: {len(matches)}")
    print(f"  Average GOP: {sum(gop_scores)/len(gop_scores):.3f}")
    print(f"  Best phone GOP: {max(gop_scores):.3f}")
    print(f"  Worst phone GOP: {min(gop_scores):.3f}")
    print(f"  Phones with GOP < -3: {sum(1 for g in gop_scores if g < -3)}")
    print(f"  Phones with GOP < -1: {sum(1 for g in gop_scores if g < -1)}")
    print()
    break
PYEOF
