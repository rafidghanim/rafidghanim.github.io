#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_DIR="$ROOT_DIR/_templates/ctf"
POST_DIR="$ROOT_DIR/_posts"

categories=(
  crypto
  web
  reverse
  pwn
  forensics
  misc
  osint
  blockchain
  hardware
  mobile
)

slugify() {
  printf '%s' "$1" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'
}

replace_field() {
  local file="$1"
  local field="$2"
  local value="$3"

  python3 - "$file" "$field" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
field = sys.argv[2]
value = sys.argv[3].replace('"', '\\"')
text = path.read_text()
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith(f"{field}:"):
        lines[i] = f'{field}: "{value}"'
        break
path.write_text("\n".join(lines) + "\n")
PY
}

replace_scalar() {
  local file="$1"
  local field="$2"
  local value="$3"

  python3 - "$file" "$field" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
field = sys.argv[2]
value = sys.argv[3]
text = path.read_text()
lines = text.splitlines()
for i, line in enumerate(lines):
    if line.startswith(f"{field}:"):
        lines[i] = f"{field}: {value}"
        break
path.write_text("\n".join(lines) + "\n")
PY
}

echo "Select CTF category:"
select category in "${categories[@]}"; do
  if [[ -n "${category:-}" ]]; then
    break
  fi
  echo "Invalid category. Try again."
done

template="$TEMPLATE_DIR/$category.md"
if [[ ! -f "$template" ]]; then
  echo "Template not found: $template" >&2
  exit 1
fi

read -r -p "CTF name: " ctf_name
read -r -p "Challenge name: " challenge_name
read -r -p "Difficulty [Easy/Medium/Hard]: " difficulty
read -r -p "Points [0]: " points
read -r -p "Description [Short summary of the challenge and solution.]: " description

difficulty="${difficulty:-Easy/Medium/Hard}"
points="${points:-0}"
description="${description:-Short summary of the challenge and solution.}"

if [[ -z "$ctf_name" || -z "$challenge_name" ]]; then
  echo "CTF name and challenge name are required." >&2
  exit 1
fi

date_slug="$(date +%Y-%m-%d)"
date_full="$(date '+%Y-%m-%d %H:%M:%S %z')"
ctf_slug="$(slugify "$ctf_name")"
challenge_slug="$(slugify "$challenge_name")"
output="$POST_DIR/$date_slug-$ctf_slug-$challenge_slug.md"

if [[ -e "$output" ]]; then
  echo "Post already exists: $output" >&2
  exit 1
fi

cp "$template" "$output"

category_title="$(python3 - "$category" <<'PY'
import sys
name = sys.argv[1]
print({
    "crypto": "Crypto",
    "web": "Web",
    "reverse": "Reverse",
    "pwn": "Pwn",
    "forensics": "Forensics",
    "misc": "Misc",
    "osint": "OSINT",
    "blockchain": "Blockchain",
    "hardware": "Hardware",
    "mobile": "Mobile",
}[name])
PY
)"

replace_field "$output" "title" "$ctf_name - $challenge_name"
replace_field "$output" "description" "$description"
replace_scalar "$output" "date" "$date_full"
replace_field "$output" "ctf" "$ctf_name"
replace_field "$output" "challenge" "$challenge_name"
replace_field "$output" "category" "$category_title"
replace_field "$output" "difficulty" "$difficulty"
replace_scalar "$output" "points" "$points"

echo "Created: $output"
