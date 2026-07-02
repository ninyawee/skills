---
name: commit
allowed-tools: Bash(git add:*), Bash(git status:*), Bash(git commit:*)
description: Create a git commit
disable-model-invocation: true
---

## Context

- Current git status: !`git status`
- Current git diff (staged and unstaged changes): !`git diff HEAD`
- Current branch: !`git branch --show-current`
- Recent commits: !`git log --oneline -10`

## Your task

Based on the above changes, create a single git commit that includes ONLY the changes you made during this session. Do not blindly stage everything — review the diff and only stage files you remember modifying. If you're unsure whether a change is yours, ask the user.

You have the capability to call multiple tools in a single response. Stage only your files and create the commit using a single message. Do not use any other tools or do anything else. Do not send any other text or messages besides these tool calls.
