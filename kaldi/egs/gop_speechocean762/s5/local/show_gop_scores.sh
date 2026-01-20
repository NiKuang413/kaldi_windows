#!/usr/bin/env bash

# Show phone-level GOP scores
# Usage: ./local/show_gop_scores.sh <gop_scp_file>

[ -f ./path.sh ] && . ./path.sh

gop_scp=$1
lang_dir=$(dirname $(dirname $gop_scp))/lang_nosp
phone_table="$lang_dir/phones-pure.txt"
# Get ark path from scp file - format is "utt_id ark:path:offset"
# We need just the path part without "ark:" prefix and without offset
ark_path=$(head -1 $gop_scp | awk '{print $2}' | sed 's|^ark:||' | sed 's|:.*$||')

echo "=== Phone-Level GOP Scores ==="
echo ""

# Get GOP data to temp file
tmp_file=$(mktemp)
copy-post "ark:$ark_path" ark,t:- > "$tmp_file" 2>/dev/null

# Find the data line
gop_line=$(grep -E ".*\[.*\].*" "$tmp_file" | grep -v "LOG\|Done\|copy-post" | head -1)
rm -f "$tmp_file"

if [ -z "$gop_line" ]; then
  echo "Error: Could not extract GOP data"
  echo "Trying direct command..."
  copy-post "ark:$ark_path" ark,t:- 2>&1 | head -3
  exit 1
fi

# Process with Python
python3 << PYEOF
import re

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

# Process the GOP line
line = """$gop_line"""

parts = line.split()
if len(parts) < 2:
    print("Error: Invalid GOP data format")
    exit(1)

utt_id = parts[0]
print("="*70)
print(f"Utterance: {utt_id}")
print("="*70)
print(f"{'Phone ID':<12} {'Phone Name':<20} {'GOP Score':<15} {'Quality':<15}")
print("-"*70)

# Extract [phone_id gop_score] pairs
matches = re.findall(r'\[\s*(\d+)\s+([-\d.]+)\s*\]', line)

if not matches:
    print("No GOP scores found")
    exit(1)

for pid, gop in matches:
    pid_int = int(pid)
    gop_val = float(gop)
    pname = phone_map.get(str(pid_int), "UNK")
    
    if gop_val > 0:
        qual = "Excellent"
    elif gop_val > -1:
        qual = "Good"
    elif gop_val > -3:
        qual = "Fair"
    elif gop_val > -5:
        qual = "Poor"
    else:
        qual = "Very Poor"
    
    print(f"{pid_int:<12} {pname:<20} {gop_val:<15.3f} {qual:<15}")

print("="*70)

# Summary
gops = [float(g) for _, g in matches]
print(f"\nSummary:")
print(f"  Total phones: {len(matches)}")
print(f"  Average GOP: {sum(gops)/len(gops):.3f}")
print(f"  Best phone GOP: {max(gops):.3f}")
print(f"  Worst phone GOP: {min(gops):.3f}")
print(f"  Phones with GOP < -3 (Very Poor): {sum(1 for g in gops if g < -3)}")
print(f"  Phones with GOP < -1 (Fair or worse): {sum(1 for g in gops if g < -1)}")
print()
PYEOF
