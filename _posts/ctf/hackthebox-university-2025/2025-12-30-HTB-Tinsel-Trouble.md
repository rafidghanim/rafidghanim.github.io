---
layout: post
title: "HackTheBox University: Tinsel Trouble – CTF Writeup"
date: 2025-12-30
categories: [writeup, ctf, university]
tags: [ctf,hackthebox,international, pwn, crypto, reversing, web, forensics]
toc: true
---

# HackTheBox University: Tinsel Trouble – CTF Writeup

> Writeup from the **HackTheBox University: Tinsel Trouble** CTF event.

---

## 🔐 Crypto

### 🔹 Challenge: disguised
- **attachment**: [crypto_disguised.zip](/assets/files/htb-univ-2025/crypto/crypto_disguised.zip)
- **Solution Steps**:

```py
import string, re, random, hashlib
from secret import STARSHARD_SCROLL, FESTIVE_WHISPER_CLEAN, PEPPERMINT_KEYWORD
from Crypto.Util.Padding import pad
from Crypto.Cipher import AES

FESTIVE_WHISPER_CLEAN = re.sub(r'[^a-zA-Z0-9]', '', FESTIVE_WHISPER_CLEAN).upper()
CANDYCANE_ALPHABET = string.ascii_uppercase + string.digits
SZ = 6
L = SZ**2

def weave_peppermint_square():
    peppermint_square_flat = CANDYCANE_ALPHABET
    for c in PEPPERMINT_KEYWORD:
        peppermint_square_flat = peppermint_square_flat.replace(c, '')
    peppermint_square_flat = PEPPERMINT_KEYWORD + peppermint_square_flat
    return [list(peppermint_square_flat[i:i+SZ]) for i in range(0, len(peppermint_square_flat), SZ)]

peppermint_square = weave_peppermint_square()

BAUBLE_COORDS = {
    peppermint_square[i][j]: f'{i+1}{j+1}'
    for j in range(SZ)
    for i in range(SZ)
}

def swirl_encrypt(starstream_key, starlit_plaintext):
    twinkling_ct = []
    for i in range(len(starlit_plaintext)):
        key_off = int(BAUBLE_COORDS[starstream_key[i % len(starstream_key)]])
        pt_off = int(BAUBLE_COORDS[starlit_plaintext[i]])
        twinkling_ct.append(key_off + pt_off)
    return twinkling_ct

STARSTREAM_KEY = ''.join(random.sample(CANDYCANE_ALPHABET, k=L))
PEPPERMINT_CIPHERTEXT = swirl_encrypt(STARSTREAM_KEY, FESTIVE_WHISPER_CLEAN)

COCOA_AES_KEY = hashlib.sha256(FESTIVE_WHISPER_CLEAN.encode()).digest()
WRAPPED_STARSHARD = AES.new(COCOA_AES_KEY, AES.MODE_ECB).encrypt(pad(STARSHARD_SCROLL, 16)).hex()

open('output.txt', 'w').write(f'{PEPPERMINT_KEYWORD = }\n{PEPPERMINT_CIPHERTEXT = }\n{WRAPPED_STARSHARD = }')
```

analisis source code 

```py
FESTIVE_WHISPER_CLEAN = re.sub(r'[^a-zA-Z0-9]', '', FESTIVE_WHISPER_CLEAN).upper()
CANDYCANE_ALPHABET = string.ascii_uppercase + string.digits
SZ = 6
L = SZ**2
```

di awal kode terdapat beberapa deklarasi variabel yakni **FESTIVE_WHISPER_CLEAN**, **CANDYCANE_ALPHABET**, **SZ**, **L**, dst
dapat diuraikan kegunaan variabel tersebut:

* FESTIVE_WHISPER_CLEAN
  
  Variabel ini melakukan regex dari variabel yang diimport dari modul secret dengan nama yang sama kemudian mereplace semua non alfabet dan non number sehingga menyisakan string berupa alfabet upper dan number.

* CANDYCANE_ALPHABET
  
  Variabel ini membuat string berupa ascii uppercase digabung dengan angka, artinya memiliki length 26 + 10 = 36 karakter

* SZ dan L merupakan inisialisasi saja

* peppermint_square
  
  Variabel ini nantinya memanggil fungsi weave_peppermint_square() dan menyimpan return valuenya

* BAUBLE_COORDS

  Variabel ini membuat **dictionary comprehension** sepanjang SZ-1

* STARSTREAM_KEY

  Variabel ini membuat key untuk enkripsi dari random sample variabel CANDYCANE_ALPHABET sepanjang L (6^2 = 36)

* PEPPERMINT_CIPHERTEXT

  Variabel ini melakukan enkripsi dengan memanggil swirl_encrypt menggunakan STARSTREAM_KEY, FESTIVE_WHISPER_CLEAN sebagai parameternya

* COCOA_AES_KEY

  Variabel ini membuat aes key dengan melakukan hash sha256 ke variabel FESTIVE_WHISPER_CLEAN yang kemudian aes key ini bisa digunakan untuk melakukan enkripsi dan dekripsi

* WRAPPED_STARSHARD 

  Variabel ini melakukan enkripsi ke variabel STARSHARD_SCROLL dan menyimpannya dengan format hexadecimal

```py
def weave_peppermint_square():
    peppermint_square_flat = CANDYCANE_ALPHABET
    for c in PEPPERMINT_KEYWORD:
        peppermint_square_flat = peppermint_square_flat.replace(c, '')
    peppermint_square_flat = PEPPERMINT_KEYWORD + peppermint_square_flat
    return [list(peppermint_square_flat[i:i+SZ]) for i in range(0, len(peppermint_square_flat), SZ)]

def swirl_encrypt(starstream_key, starlit_plaintext):
    twinkling_ct = []
    for i in range(len(starlit_plaintext)):
        key_off = int(BAUBLE_COORDS[starstream_key[i % len(starstream_key)]])
        pt_off = int(BAUBLE_COORDS[starlit_plaintext[i]])
        twinkling_ct.append(key_off + pt_off)
    return twinkling_ct
```

kemudian analisis fungsi, di sini terdapat dua fungsi: 
 
* weave_peppermint_square
  
  Fungsi ini akan me-return list 2 dimesi (matrix) yang berisi karakter, dengan jumlah total karakter sebanyak 36

* swirl_encrypt

  Fungsi ini menghasilkan ciphertext dengan cara mengiterasi setiap karakter pada starlit_plaintext. Karena panjang starlit_plaintext dan starstream_key sudah ditetapkan sebesar 36 karakter, proses iterasi dan operasi modulo akan berjalan dari 0 hingga 35 tanpa pengulangan indeks kunci.

  Pada setiap iterasi, karakter dari starstream_key diambil berdasarkan posisi iterasi, lalu dipetakan ke posisi koordinatnya menggunakan dictionary BAUBLE_COORDS. Nilai koordinat tersebut kemudian dikonversi menjadi integer dan disimpan sebagai key_off.

  Proses yang sama dilakukan pada karakter starlit_plaintext, di mana karakter tersebut dipetakan ke posisi koordinatnya dan disimpan sebagai pt_off.

  Nilai key_off dan pt_off kemudian dijumlahkan pada setiap iterasi untuk membentuk elemen ciphertext yang akhirnya dikembalikan oleh fungsi.

- **Solver Script**:

```py
import string
from Crypto.Cipher import AES
from Crypto.Util.Padding import unpad
import hashlib
import ast
# ====== DATA DARI output.txt ======
data = {}
with open('output.txt','r'):
    for line in f:
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        data[key.strip()] = ast.literal_eval(value.strip())
# ====== KONSTRUKSI SQUARE ======
PEPPERMINT_KEYWORD = data["PEPPERMINT_KEWORD"]
PEPPERMINT_CIPHERTEXT = data["PEPPERMINT_CIPHERTEXT"]
WRAPPED_STARSHARD = data["WRAPPED_STARSHARD"]
# ===================== KONSTRUKSI PEPPERMINT SQUARE =====================
CANDYCANE_ALPHABET = string.ascii_uppercase + string.digits
SZ = 6
KEYLEN = 36

def weave_square():
    flat = CANDYCANE_ALPHABET
    for c in PEPPERMINT_KEYWORD:
        flat = flat.replace(c, "")
    flat = PEPPERMINT_KEYWORD + flat
    return [list(flat[i:i+SZ]) for i in range(0, len(flat), SZ)]

square = weave_square()

BAUBLE = {
    square[i][j]: f"{i+1}{j+1}"
    for j in range(SZ)
    for i in range(SZ)
}
INV_BAUBLE = {v: k for k, v in BAUBLE.items()}
VALID = set(int(x) for x in INV_BAUBLE.keys())  # 11..66


# ===================== STEP 1: RECOVER KEY (INTERSECTION) =====================
candidates = [set() for _ in range(KEYLEN)]

for i, ct in enumerate(PEPPERMINT_CIPHERTEXT):
    pos = i % KEYLEN
    valid_k = set()

    for pt in VALID:              # coba semua 36 kemungkinan plaintext
        k = ct - pt               # key = ct - pt
        if k in VALID:
            valid_k.add(k)

    if not candidates[pos]:
        candidates[pos] = valid_k
    else:
        candidates[pos] &= valid_k


# ===================== STEP 2: PROPAGASI PERMUTASI =====================
key_coords = [None] * KEYLEN
used = set()

while None in key_coords:
    progress = False
    for i in range(KEYLEN):
        if key_coords[i] is None:
            opts = candidates[i] - used
            if len(opts) == 1:
                key_coords[i] = opts.pop()
                used.add(key_coords[i])
                progress = True
    if not progress:
        raise Exception("Key recovery failed (should not happen)")


STARSTREAM_KEY = "".join(INV_BAUBLE[f"{k:02d}"] for k in key_coords)
print("[+] STARSTREAM_KEY =", STARSTREAM_KEY)


# ===================== STEP 3: DECRYPT FESTIVE WHISPER =====================
plaintext = []
for i, ct in enumerate(PEPPERMINT_CIPHERTEXT):
    pt = ct - key_coords[i % KEYLEN]
    plaintext.append(INV_BAUBLE[f"{pt:02d}"])

FESTIVE_WHISPER = "".join(plaintext)
print("[+] FESTIVE_WHISPER =", FESTIVE_WHISPER)


# ===================== STEP 4: AES DECRYPT =====================
aes_key = hashlib.sha256(FESTIVE_WHISPER.encode()).digest()
cipher = AES.new(aes_key, AES.MODE_ECB)
flag = unpad(cipher.decrypt(bytes.fromhex(WRAPPED_STARSHARD)), 16)

print("[+] FLAG =", flag.decode())
```

---

### 🔹 Challenge: one_trick_pony
- **attachment**: [crypto_one_trick_pony.zip](/assets/files/htb-univ-2025/crypto/crypto_one_trick_pony.zip)
- **Solution Steps**:
- **Flag**:

---
### 🔹 Challenge: optimistic
- **attachment**: [crypto_optimistic.zip](/assets/files/htb-univ-2025/crypto/crypto_optimistic.zip)
- **Solution Steps**:
- **Flag**:

---

## 💣 Pwn

### 🔹 Challenge: pwn_feel_my_terror
- **Description**:
- **Solution Steps**:
- **Flag**:

---

### 🔹 Challenge: pwn_shl33t
- **Description**:
- **Solution Steps**:
- **Flag**:

---

---

### 🔹 Challenge: pwn_starshard_core
- **Description**:
- **Solution Steps**:
- **Flag**:

---


## 🧬 Reversing

### 🔹 Challenge: rev_clock_work_memory
- **Description**:
- **Solution Steps**:
- **Flag**:

---

### 🔹 Challenge: rev_cloudy_core
- **Description**:
- **Solution Steps**:
- **Flag**:

---

---

### 🔹 Challenge: rev_starshard_reassembly
- **Description**:
- **Solution Steps**:
- **Flag**:

---

## 🌐 Web

### 🔹 Challenge: [Challenge Name Web 1] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

### 🔹 Challenge: [Challenge Name Web 2] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

## 🕵️ Forensics

### 🔹 Challenge: [Challenge Name Forensics 1] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

### 🔹 Challenge: [Challenge Name Forensics 2] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

## 🌍 OSINT

### 🔹 Challenge: [Challenge Name OSINT 1] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

## 🧪 Misc

### 🔹 Challenge: [Challenge Name Misc 1] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

### 🔹 Challenge: [Challenge Name Misc 2] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

## 🧰 Hardware (if applicable)

### 🔹 Challenge: [Challenge Name Hardware 1] (XX pts)
- **Description**:
- **Solution Steps**:
- **Flag**:

---

## 📌 Conclusion

General reflection and notes:

- Which challenge was the most interesting?
- Which category had the most solves?
- Key lessons or takeaways from the event?

---

> _"Capture The Flag is not just a game. It’s a journey to mastering cybersecurity."_  
> #HappyHacking 🔐
