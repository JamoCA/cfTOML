# cfTOML Conformance Suite

This directory contains the TOML 1.0.0 conformance runner that exercises the BurntSushi/toml-test corpus against cfTOML.

## Pinned corpus version

cfTOML targets BurntSushi/toml-test at tag `v1.5.0` (or the latest tag that ships TOML 1.0.0 cases; refresh by re-running fetch-corpus.ps1).

## Fetching the corpus

The corpus is not committed to this repository (it would balloon the diff and may need refreshing for spec updates). To fetch:

```
powershell tests/conformance/fetch-corpus.ps1
```

This clones the toml-test repo at the pinned tag into `tests/conformance/corpus/`. The directory is .gitignored.

## Running conformance

After fetching the corpus, browse:

```
http://localhost:8128/tests/conformance/run-conformance.cfm
```

The runner walks `corpus/valid/` and `corpus/invalid/` subdirectories. Output is a PASS/FAIL summary per file plus an aggregate count.

Conformance is run separately from the main unit-test runner (`tests/runner.cfm`) because the corpus has 400+ test cases and the run takes 30-60 seconds.

## Typed JSON format

Valid corpus tests pair a `.toml` file with a `.json` file that uses the toml-test "typed JSON" format - leaf values are wrapped in `{"type": "...", "value": "..."}` to encode TOML's distinct types in JSON. The conformance runner converts cfTOML's parsed output to this format before comparing against the expected JSON.

See `typed-json.cfm` for the converter implementation.

## Current conformance status

Last run: 2026-05-11

- Valid tests: 132 passed / 187 total (~71%)
- Invalid tests: 258 passed / 371 total (~70%)
- Errors: 63 (39 valid-test parse errors + 24 invalid-test wrong error type)

Known systematic gaps:

- **Bare keys that look like numbers or floats** - keys like `1234`, `3.14`, `1e100` are rejected; TOML 1.0 allows any bare-key token shape. Affects `valid/key/numeric*`, `valid/key/zero*`, `valid/spec/keys-*`, `valid/comment/tricky` (~15 cases).
- **Dotted keys / multi-segment key paths** - `a.b = 1` and quoted dotted keys fail with "Unexpected token 'STRING_BASIC'" at line 2. Affects `valid/key/dotted-*`, `valid/key/quoted-*`, `valid/key/space`, `valid/key/escapes`, `valid/key/special-*` (~12 cases).
- **Inline table trailing content** - `{a = 1}` inside arrays or multi-key inline tables throws "Unexpected token in inline table". Affects `valid/inline-table/*` (~6 cases).
- **Datetime edge cases** - negative-year dates (e.g. `-0000`), times without seconds (`HH:MM`), and leap-year dates at parse time. Affects `valid/datetime/leap-year`, `valid/datetime/no-seconds`, `valid/datetime/edge` (~3 cases).
- **\e and \x escape sequences** - TOML 1.1 draft escapes not yet recognized; corpus uses them in a few valid string tests.
- **Unicode bare keys** - keys containing non-ASCII chars (e.g. `EUR`) fail with "Unexpected character". Affects `valid/key/unicode`.
- **Float formatting** - `toString()` on Java Double does not always match the corpus expected string (e.g. `1.0` vs `1`). Affects `valid/float/long`, `valid/float/max-int`, `valid/spec/float-1`.
- **Invalid-pass gaps (89 cases)** - control characters in strings/comments, leading zeros on integers and floats, case-insensitive bool literals (`True`/`False`), inline-table separator errors, and some duplicate-key/table-redefine scenarios are accepted rather than rejected.
