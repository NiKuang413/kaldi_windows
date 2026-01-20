#!/usr/bin/env bash

# Simple script to view phone-level GOP scores
# Usage: ./local/view_gop_simple.sh <gop_scp_file>

[ -f ./path.sh ] && . ./path.sh

gop_scp=$1
lang_dir=$(dirname $(dirname $gop_scp))/lang_nosp
phone_table="$lang_dir/phones-pure.txt"

# Get ark path
ark_path=$(head -1 $gop_scp | awk '{print $2}' | sed 's|ark:||' | sed 's|:.*||')

echo "=== Phone-Level GOP Scores ==="
echo ""

# Get GOP data and process (redirect stderr to filter errors)
copy-post "ark:$ark_path" ark,t:- 2>/dev/null | \
python3 -c "
import re
import sys

# Load phone map
phone_map = {}
try:
    with open('$phone_table', 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2:
                phone_map[parts[1]] = parts[0]
except:
    pass

# Find data line
for line in sys.stdin:
    line = line.strip()
    if not line or 'copy-post' in line.lower():
        continue
    if '[' in line and ']' in line:
        # Find utterance ID (first word before brackets)
        parts = line.split()
        if len(parts) < 2:
            continue
        # Utterance ID is the first token
        utt_id = parts[0]
        print('Utterance: ' + utt_id)
        print('='*70)
        print('{:<12} {:<20} {:<15} {:<15}'.format('Phone ID', 'Phone Name', 'GOP Score', 'Quality'))
        print('-'*70)
        
        # Extract [phone_id gop_score] pairs - handle format: [ 38 0 ] or [38 0]
        matches = re.findall(r'\[\s*(\d+)\s+([-\d.]+)\s*\]', line)
        
        if not matches:
            print('No GOP scores found')
            continue
        
        for pid, gop in matches:
            pid_int = int(pid)
            gop_val = float(gop)
            pname = phone_map.get(str(pid_int), 'UNK')
            if gop_val > 0:
                qual = 'Excellent'
            elif gop_val > -1:
                qual = 'Good'
            elif gop_val > -3:
                qual = 'Fair'
            elif gop_val > -5:
                qual = 'Poor'
            else:
                qual = 'Very Poor'
            print('{:<12} {:<20} {:<15.3f} {:<15}'.format(pid_int, pname, gop_val, qual))
        
        print('='*70)
        if matches:
            gops = [float(g) for _, g in matches]
            print('Summary: {} phones, Avg GOP: {:.3f}, Worst: {:.3f}'.format(len(matches), sum(gops)/len(gops), min(gops)))
        break
"
