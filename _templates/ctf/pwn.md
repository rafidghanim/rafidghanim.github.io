---
layout: post
title: "[CTF Name] - [Challenge Name]"
description: "Short summary of the challenge and solution."
date: YYYY-MM-DD HH:MM:SS +0700
categories: [writeup, ctf]
tags: [ctf, pwn]
ctf: "CTF Name"
challenge: "Challenge Name"
category: "Pwn"
difficulty: "Easy/Medium/Hard"
points: 0
author: "gr3yr4t"
toc: true
comments: true
image: /assets/img/avatar.jpg
---

# {{ page.title }}

## TL;DR

Brief summary of the bug, vulnerability, trick, or core idea.

## Challenge Information

| Field | Value |
|---|---|
| CTF | {{ page.ctf }} |
| Challenge | {{ page.challenge }} |
| Category | {{ page.category }} |
| Difficulty | {{ page.difficulty }} |
| Points | {{ page.points }} |

## Description

Paste the original challenge description here.

## Files

List provided files, URLs, binaries, attachments, or source code.

## Initial Analysis

Explain first observations and assumptions.

## Checksec

```text
checksec --file ./chall
```

## Binary Protections

Summarize NX, PIE, RELRO, stack canary, libc, and architecture details.

## Vulnerability

Explain the memory corruption, logic bug, format string, heap issue, or sandbox escape.

## Exploit Strategy

Describe the primitives and exploit chain.

## Solution

Explain the solving process step by step.

## Final Exploit

```python
# exploit.py
```

## Exploit / Solver

```python
# solver.py
```

## Flag

```text
flag{example}
```

## Lessons Learned

Write what you learned from this challenge.

## References

*
