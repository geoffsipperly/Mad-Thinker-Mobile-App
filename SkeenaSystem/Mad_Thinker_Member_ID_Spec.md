# Mad Thinker — Member ID Specification

**Version 1.0** | April 2026

---

## 1. Overview

This document defines the standard format for Mad Thinker member identifiers. The ID system is designed to generate unique, human-readable identifiers that are easy to communicate verbally, visually distinct, and resistant to transcription errors.

The format is based on Crockford's Base32 encoding, a well-established standard that deliberately excludes characters commonly confused with one another (such as O and 0, or I and 1).

## 2. ID Format

Each Mad Thinker member ID follows the format below. The total length is 9 characters: a 3-character prefix followed by a 6-character unique code.

```
MAD4ZQ7H9
───┬───┬──
   │   └── Unique Code (6 characters)
   └────── Prefix
```

| Component   | Value    | Description                                                  |
|-------------|----------|--------------------------------------------------------------|
| Prefix      | `MAD`    | Fixed identifier for Mad Thinker                             |
| Unique Code | `XXXXXX` | 6 random characters from the Crockford Base32 alphabet       |
| Total Length | `9`      | Compact enough for verbal communication and printed materials |

## 3. Character Set

The unique code portion uses Crockford's Base32 alphabet, which consists of 32 characters chosen to minimize transcription errors. The following characters are excluded to prevent confusion:

| Excluded | Reason                                  |
|----------|-----------------------------------------|
| `I`      | Confused with 1 (one) or L (el)         |
| `L`      | Confused with 1 (one) or I (eye)        |
| `O`      | Confused with 0 (zero)                  |
| `U`      | Excluded to avoid accidental profanity  |

**Permitted characters (32 total):**

```
0 1 2 3 4 5 6 7 8 9 A B C D E F G H J K M N P Q R S T V W X Y Z
```

### 3.1 Capacity

With 6 characters from a 32-symbol alphabet, the system supports 32⁶ = 1,073,741,824 (over 1 billion) unique member IDs. This provides substantial headroom for growth.

## 4. Generation Rules

1. Use a cryptographically secure random number generator (e.g., `crypto.getRandomValues` or `os.urandom`) to select each character from the 32-character alphabet.
2. Prepend the fixed prefix `MAD` to form the complete ID.
3. Check the generated ID against the existing member database to confirm uniqueness.
4. If a collision is detected, regenerate. At this capacity, collisions are statistically negligible until millions of IDs are issued.

## 5. Display and Input Guidelines

### 5.1 Storage

Store the ID as a single uppercase string with no separators: `MAD4ZQ7H9`

### 5.2 Display

Display the ID exactly as stored, as a single continuous string: `MAD4ZQ7H9`. Use a monospaced font for IDs whenever possible to improve legibility.

### 5.3 Input Normalization

When accepting member IDs as input, systems should apply the following normalizations:

- Convert all characters to uppercase.
- Strip any spaces, hyphens, or other separators.
- Apply Crockford's error correction: automatically substitute commonly confused characters (e.g., lowercase l → 1, lowercase o → 0).

## 6. Examples

| Stored Value  | Spoken As                                      |
|---------------|-------------------------------------------------|
| `MAD4ZQ7H9`  | MAD four-zulu-quebec-seven-hotel-niner          |
| `MADR3KW5N`  | MAD romeo-three-kilo-whiskey-five-november      |
| `MAD8BTXG2`  | MAD eight-bravo-tango-xray-golf-two             |

## 7. Reference

This specification is based on **Crockford's Base32 Encoding**, originally defined by Douglas Crockford. For the full specification, see: www.crockford.com/base32.html
