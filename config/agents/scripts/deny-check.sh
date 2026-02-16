#!/bin/bash
input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command' 2>/dev/null || echo "")
tool_name=$(echo "$input" | jq -r '.tool_name' 2>/dev/null || echo "")
if [ "$tool_name" != "Bash" ]; then
  exit 0
fi

settings_file="$HOME/.claude/settings.json"
deny_patterns=$(jq -r '.permissions.deny[] | select(startswith("Bash(")) | gsub("^Bash\\("; "") | gsub("\\)$"; "")' "$settings_file" 2>/dev/null)
matches_deny_pattern() {
  local cmd="$1"
  local pattern="$2"
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  cmd="${cmd%"${cmd##*[![:space:]]}"}"
  [[ "$cmd" == $pattern ]]
}

while IFS= read -r pattern; do
  [ -z "$pattern" ] && continue
  if matches_deny_pattern "$command" "$pattern"; then
    echo "Error: Command rejected: '$command' (pattern: '$pattern')" >&2
    exit 2
  fi
done <<<"$deny_patterns"

temp_command="${command//;/$'\n'}"
temp_command="${temp_command//&&/$'\n'}"
temp_command="${temp_command//\|\|/$'\n'}"

IFS=$'\n'
for cmd_part in $temp_command; do
  [ -z "$(echo "$cmd_part" | tr -d '[:space:]')" ] && continue

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    if matches_deny_pattern "$cmd_part" "$pattern"; then
      echo "Error: Command rejected: '$cmd_part' (pattern: '$pattern')" >&2
      exit 2
    fi
  done <<<"$deny_patterns"
done

exit 0
