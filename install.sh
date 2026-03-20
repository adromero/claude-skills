#!/usr/bin/env bash
set -euo pipefail

# Claude Skills installer — copies skills and agents to ~/.claude/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"
AGENTS_DIR="${HOME}/.claude/agents"

echo "Installing Claude Skills..."
echo ""

# Skills
for skill_dir in "$SCRIPT_DIR"/skills/*/; do
  skill_name=$(basename "$skill_dir")
  echo "  Installing skill: $skill_name"
  mkdir -p "$SKILLS_DIR/$skill_name"
  cp -r "$skill_dir"* "$SKILLS_DIR/$skill_name/"
done

# Agents
if [ -d "$SCRIPT_DIR/agents" ]; then
  mkdir -p "$AGENTS_DIR"
  for agent_file in "$SCRIPT_DIR"/agents/*.md; do
    agent_name=$(basename "$agent_file")
    echo "  Installing agent: $agent_name"
    cp "$agent_file" "$AGENTS_DIR/$agent_name"
  done
fi

echo ""
echo "Done. Installed to:"
echo "  Skills: $SKILLS_DIR"
echo "  Agents: $AGENTS_DIR"
echo ""
echo "Optional: set CODEMAP_CMD in your Claude Code settings to enable"
echo "code map integration for /brainstorm and /conductor."
echo "See README.md for details."
