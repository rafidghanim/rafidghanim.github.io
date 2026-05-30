# CTF Writeup Templates

Use these templates when drafting new CTF challenge writeups. All templates keep English headings and include bilingual-ready placeholders, so the explanation can be written in English, Indonesian, or mixed notes before final editing.

## Template Guide

| Template | Use When |
|---|---|
| `crypto.md` | The challenge is about cryptography, math, weak randomness, bad parameters, or custom encryption. |
| `web.md` | The challenge involves HTTP, APIs, browser behavior, server-side bugs, auth bypass, injection, upload, or SSRF. |
| `reverse.md` | The challenge requires reversing a binary, bytecode, VM, obfuscation, license check, or custom algorithm. |
| `pwn.md` | The challenge targets memory corruption, binary exploitation, shellcode, ROP, heap, format string, or sandbox escape. |
| `forensics.md` | The challenge involves file carving, metadata, logs, memory/disk artifacts, packet captures, images, or recovery. |
| `misc.md` | The challenge does not fit a specific category or involves puzzles, encoding chains, scripting, parsing, or automation. |
| `osint.md` | The challenge requires public-source investigation, geolocation, identity pivots, archives, screenshots, or verification. |
| `blockchain.md` | The challenge involves smart contracts, EVM, Web3, Foundry, on-chain state, transaction crafting, or DeFi logic. |
| `hardware.md` | The challenge involves signals, protocols, firmware dumps, datasheets, UART/I2C/SPI, logic analyzer traces, or decoding. |
| `mobile.md` | The challenge involves APK/IPA analysis, decompilation, Smali, native libraries, root checks, hooks, or app patching. |

## Creating A Post

Run the helper from the repository root:

```bash
./new-ctf-post.sh
```

The script prompts for category, CTF name, challenge name, difficulty, points, and description, then creates:

```text
_posts/YYYY-MM-DD-ctf-name-challenge-name.md
```

After generation, edit the new post and fill the placeholders. The script does not modify old posts, permalinks, layouts, or theme files.

## SEO Fields

Each CTF template already includes the SEO-safe front matter used by the site:

```yaml
description: "Short summary of the challenge and solution."
author: "gr3yr4t"
image: /assets/img/avatar.jpg
toc: true
comments: true
```

Update `description` and `image` per writeup when a challenge has a better summary or cover image. Keep `title`, `date`, `categories`, and `tags` filled so `jekyll-seo-tag`, `jekyll-feed`, and `jekyll-sitemap` can generate clean metadata.
