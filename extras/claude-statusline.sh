#!/usr/bin/env bash
# Claude Code status line: a permanent headline for each session.
#   ▌ <session name>   <project> ⎇ <branch> · <model> · <ctx%>
# The name comes from `claude -n`, /rename, or Claude's auto title.
input=$(cat)

j() { jq -r "$1 // empty" <<<"$input"; }

name=$(j '.session_name')
cwd=$(j '.workspace.current_dir')
[ -z "$cwd" ] && cwd=$(j '.cwd')
model=$(j '.model.display_name')
ctx=$(j '.context_window.used_percentage')

project=$(basename "${cwd:-?}")
[ "$cwd" = "$HOME" ] && project="~"
branch=$(git --no-optional-locks -C "$cwd" branch --show-current 2>/dev/null)

bold=$'\e[1m'; dim=$'\e[2m'; cyan=$'\e[36m'; mag=$'\e[35m'; yel=$'\e[33m'; red=$'\e[31m'; off=$'\e[0m'

if [ -n "$name" ]; then
  head="${bold}${cyan}▌ ${name}${off}"
else
  head="${bold}${cyan}▌ ${off}${dim}untitled · /rename to set a headline${off}"
fi

meta="${mag}${project}${off}"
[ -n "$branch" ] && meta+=" ${dim}⎇${off} ${branch}"
[ -n "$model" ] && meta+=" ${dim}·${off} ${model}"
if [ -n "$ctx" ]; then
  c=$dim; [ "$ctx" -ge 50 ] && c=$yel; [ "$ctx" -ge 80 ] && c=$red
  meta+=" ${dim}·${off} ${c}${ctx}% ctx${off}"
fi

printf '%s   %s' "$head" "$meta"
