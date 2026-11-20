#!/usr/bin/env bash
# Design-token ratchet (UI_REDESIGN.md, section 5): feature code may not add
# raw colours or inline font sizes. Counts may only go down; when a screen
# moves to theme tokens, lower the numbers in tool/design_token_baseline.txt.
set -euo pipefail
cd "$(dirname "$0")/.."

# `(^|[^A-Za-z_])` so the AppColors.of(context) token isn't counted as a raw
# Colors.* use.
colors=$(grep -rhoE '(^|[^A-Za-z_])Colors\.[a-zA-Z]+|Color\(0x[0-9A-Fa-f]{8}\)' lib/features --include='*.dart' | wc -l)
fonts=$(grep -rhoE 'fontSize:' lib/features --include='*.dart' | wc -l)

read -r max_colors max_fonts < tool/design_token_baseline.txt

echo "raw colours: $colors (baseline $max_colors), inline font sizes: $fonts (baseline $max_fonts)"
status=0
if [ "$colors" -gt "$max_colors" ]; then
  echo "::error::New raw colours in lib/features. Use AppColors / ColorScheme instead."
  status=1
fi
if [ "$fonts" -gt "$max_fonts" ]; then
  echo "::error::New inline fontSize in lib/features. Use Theme.of(context).textTheme instead."
  status=1
fi
exit $status
