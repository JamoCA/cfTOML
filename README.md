# cfTOML

Pure CFML library for parsing and emitting [TOML 1.0.0](https://toml.io/en/v1.0.0). Cross-engine compatible across Adobe ColdFusion 2016+, Lucee 5+, and BoxLang 1+.

[![ForgeBox Version](https://www.forgebox.io/api/v1/entry/toml/badges/version)](https://www.forgebox.io/view/toml)
[![ForgeBox Downloads](https://www.forgebox.io/api/v1/entry/toml/badges/downloads)](https://www.forgebox.io/view/toml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Install

cfTOML is a single CFC file. Drop `cfTOML.cfc` into your project and use it. No external dependencies, no Java JARs, nothing to compile.

### Manual install from GitHub (recommended)

Source: https://github.com/JamoCA/cfTOML

**Option 1: Download a release ZIP**

Go to https://github.com/JamoCA/cfTOML/releases, download the latest release, and unzip it anywhere on your CFML path. Only `cfTOML.cfc` is required at runtime; the rest of the files are tests, examples, and tooling.

**Option 2: Clone the repository**

```
git clone https://github.com/JamoCA/cfTOML.git
```

Then copy `cfTOML.cfc` to your project, or add a CFML mapping pointing at the clone directory. In your `Application.cfc`:

```cfml
this.mappings["/cftoml"] = expandPath("./lib/cfTOML");
```

Then instantiate:

```cfml
parser = new cftoml.cfTOML();
```

**Option 3: Git submodule**

If your project is in git, add cfTOML as a submodule:

```
git submodule add https://github.com/JamoCA/cfTOML.git lib/cfTOML
git submodule update --init --recursive
```

Pin to a specific release tag for reproducible builds:

```
cd lib/cfTOML
git checkout v1.2.0
cd ../..
git add lib/cfTOML
git commit -m "pin cfTOML to v1.2.0"
```

### Install via ForgeBox (CommandBox users)

If you already use CommandBox / ForgeBox:

```
box install cftoml
```

Or in your `box.json`:

```json
"dependencies": {
    "cftoml": "^1.2.0"
}
```

## Quick start

```cfml
parser = new cfTOML();

// Parse from string
data = parser.tomlDeserialize(fileRead("config.toml"));

// Or read directly from file
data = parser.tomlReadFile("config.toml");

writeOutput(data.server.host);  // "10.0.0.1"

// Emit
toml = parser.tomlSerialize(["server": ["host": "10.0.0.1", "port": 8080]]);

// Or write directly to file
parser.tomlWriteFile("config.toml", data);
```

## TOML version support

cfTOML supports both TOML 1.0.0 (default) and TOML 1.1.0 (opt-in). Pass `spec = "1.1.0"` to parse a 1.1.0 document:

```cfml
var data = tomlDeserialize(content, ["spec": "1.1.0"]);
```

By default, the emitter produces 1.0.0-compatible output even when the parser is in 1.1.0 mode. This means you can safely parse 1.1.0 inputs and re-emit them for consumers that only support 1.0.0. To emit 1.1.0-only constructs, set the corresponding option:

| Construct | Option |
|---|---|
| Multi-line inline tables | `inlineMultiline = true` (switches when single-line exceeds 80 characters or contains multi-line strings) |
| `\e` and `\xHH` escapes | `useExtendedEscapes = true` |
| Omit `:00` seconds in datetimes | `omitZeroSeconds = true` |
| All-digit bare keys (e.g. `1234 = "value"`) | `useBareDigitKeys = true` |

Setting any of these knobs while `spec = "1.0.0"` throws `cfTOML.ConfigError`.

### Conformance

cfTOML is tested against the BurntSushi/toml-test corpus (pinned at toml-test v1.5.0, manifest-filtered per spec) for both spec versions. On engines with native case-sensitive struct support (Adobe ColdFusion 2021, 2023, 2025):

- TOML 1.0.0: 182/182 valid (100%) + 371/371 invalid (100%), zero runtime errors
- TOML 1.1.0: 187/187 valid (100%) + 361/361 invalid (100%), zero runtime errors

On engines where case-sensitive ordered structs are not available or whose dot-notation accessor uppercases (Adobe CF 2016, Lucee 5/6/7, BoxLang 1.13), the conformance numbers are 180/182 + 371/371 (1.0.0) and 185/187 + 361/361 (1.1.0). The 2-test difference is the BurntSushi case-sensitive test (`valid/key/case-sensitive.toml`) and `valid/inline-table/key-dotted-4.toml`, which require keys differing only in case to round-trip distinctly. See the "Known limitations" section for context.

The unit suite passes 634/634 on every supported engine. Every valid TOML input parses into the correct typed structure, and every invalid input is rejected with a `cfTOML.*`-prefixed exception. Strict-mode coverage includes control characters in strings, leading-zero integers, case-sensitive `true`/`false`/`inf`/`nan`, separator state machines for arrays and inline tables, trailing-token rejection after statements, datetime offset range validation, multiline-string line-continuation rules, bare-key segment validation in table headers, table-conflict tracking for dotted-key intermediates and array-of-tables, inline-table immutability, and strict UTF-8 byte-level validation.

(Run `tests/conformance/run-conformance.cfm?spec=1.0.0` or `?spec=1.1.0` to reproduce.)

### Parser features added in 1.1.0

- Multi-line inline tables - newlines and trailing commas inside `{ ... }`.
- `\e` escape - decodes to U+001B (ESC).
- `\xHH` escape - exactly two hex digits, decodes to U+00HH.
- Optional seconds in datetimes - `1979-05-27T07:32` is equivalent to `1979-05-27T07:32:00`.
- All-digit bare keys - `1234 = "value"` is permitted; the key is always a string.

## Public API

### `tomlDeserialize(toml, options)`

Parse a TOML string and return an ordered struct.

- `toml` (required string): TOML source.
- `options` (struct, default `[:]`): see Options below.

Returns: ordered struct.

### `tomlReadFile(path, options)`

Read a TOML file (UTF-8) and parse it.

- `path` (required string): absolute or webroot-relative file path.
- `options` (struct): same as `tomlDeserialize`.

Returns: ordered struct.

### `tomlSerialize(data, options)`

Serialize an ordered struct to a TOML 1.0 string.

- `data` (required struct): the data to serialize.
- `options` (struct): see Options below.

Returns: TOML string.

### `tomlWriteFile(path, data, options)`

Serialize and write to a UTF-8 file (no BOM).

- `path` (required string): output file path.
- `data` (required struct): data to write.
- `options` (struct): same as `tomlSerialize`.

Returns: void.

## Options

| Key | Type | Default | Purpose |
|---|---|---|---|
| `strict` | boolean | `true` | Reject any spec violation. `false` allows trailing commas in inline tables. |
| `dateTimeReturn` | string | `"cfdate"` | How datetime values are returned: `"cfdate"` (CFML date object, milliseconds preserved; offset datetimes are converted to the server's local timezone so the instant is preserved), `"iso8601"` (raw RFC 3339 string), `"javatime"` (java.time.OffsetDateTime / LocalDateTime / LocalDate / LocalTime). |
| `int64Mode` | string | `"double"` | Integer return type: `"double"` (CFML number, max safe 2^53), `"javalong"` (Java Long, full int64 range), `"string"` (decimal digit string for arbitrary range). |
| `indent` | string | `""` | Emit-side: indent string under nested `[header]` blocks. `""` = flat output, `"\t"` = one-tab indent per depth. |
| `sortKeys` | boolean | `false` | Emit-side: alphabetize keys. Default preserves insertion order. |
| `inlineThreshold` | numeric | `0` | Emit-side: if `>0`, top-level structs with `<=N` scalar-only keys emit as inline tables instead of `[header]` blocks. |
| `onNull` | string | `"skip"` | Emit-side null handling: `"skip"` (omit key), `"throw"` (cfTOML.TypeError), `"emptyString"` (`key = ""`). |
| `queryAsArrayOfTables` | boolean | `false` | Emit-side: when `true`, CFML query objects emit as array-of-tables. When `false`, query values throw cfTOML.TypeError. |

## Datetime modes

TOML defines four distinct datetime types: offset, local, date-only, time-only. CFML's native date type doesn't cleanly distinguish these, so the parser offers three return modes via `dateTimeReturn`:

- **`"cfdate"`** (default): All four types return CFML date objects. Offset datetimes (including `Z`) are converted to the server's local timezone via `java.time.ZoneId.systemDefault()` so the returned datetime represents the same INSTANT as the source; wall-clock varies by server zone, the instant does not. Local datetimes (no offset in source) keep their wall-clock verbatim. Fractional seconds are truncated to milliseconds (3 digits) and applied with `dateAdd("l", ms, dt)` so precision survives on CF2016+ where `createDateTime()` lacks a millisecond argument. Ergonomic for code that uses CFML's date functions.
- **`"iso8601"`**: All four types return the original RFC 3339 string verbatim. Lossless. Best for config-file use cases.
- **`"javatime"`**: Returns typed `java.time.*` objects (`OffsetDateTime`, `LocalDateTime`, `LocalDate`, `LocalTime`). Lossless, type-distinct, and zone-aware. Requires Java method calls on the caller side.

## Emit key ordering

When serializing CFML to TOML, root-level scalars and arrays get written before the first `[header]` block. This is the TOML grammar at work, not cfTOML being clever.

In TOML, every bare key after a `[header]` belongs to that header's table until the next header shows up. So a CFML struct like `{ "server": { "host": "..." }, "tags": [...] }` cannot serialize as:

```toml
[server]
host = "..."
tags = [...]
```

That would round-trip back as `server.tags`, which is the wrong shape. cfTOML writes `tags` above `[server]` so the original structure survives:

```toml
tags = [...]

[server]
host = "..."
```

Every TOML emitter (Rust, Python, Go) does the same. The data round-trips exactly. Only the textual order of keys at the root differs from the source. To keep the source order more visible, pass `inlineThreshold` so small structs stay inline (`server = { host = "..." }`) and live at the root instead of becoming `[header]` blocks.

## Errors

The library throws four distinct exception types:

- `cfTOML.ParseError` - syntax violations. `detail` is JSON with `line`, `column`, `offset`, `snippet`, `expected` keys.
- `cfTOML.TypeError` - value-shape mismatches (redefining a table as a scalar, unflagged query on emit, etc.).
- `cfTOML.DuplicateKeyError` - key redefinition.
- `cfTOML.OverflowError` - int64 out of range when `int64Mode = "double"` and `strict = true`.

## Engine support

| Engine | Status |
|---|---|
| Adobe ColdFusion 2016 | Supported |
| Adobe ColdFusion 2021 | Supported |
| Adobe ColdFusion 2023 | Supported |
| Adobe ColdFusion 2025 | Supported |
| Lucee 5 | Supported |
| Lucee 6 | Supported |
| Lucee 7 | Supported |
| BoxLang 1+ | Supported |

See `tools/run-engine-matrix.ps1` to run the full unit test suite across all engines (requires CommandBox).

## TOML conformance

The library is verified against the [BurntSushi/toml-test](https://github.com/toml-lang/toml-test) conformance corpus for both TOML 1.0.0 and 1.1.0 across the full engine matrix (Adobe CF 2016/2021/2023/2025, Lucee 5/6/7, BoxLang 1.13). Adobe CF 2021+ passes **100% valid and 100% invalid (553/553 for 1.0.0 and 548/548 for 1.1.0)**, zero runtime errors. CF 2016, Lucee, and BoxLang pass 551/553 (1.0.0) and 546/548 (1.1.0); the two-test gap on each spec is the case-sensitive-key tests that require an engine-native case-sensitive struct with working dot-notation. See `tests/conformance/README.md` for instructions on fetching and running the conformance suite.

All malformed inputs throw a `cfTOML.*`-prefixed exception (`ParseError`, `TypeError`, `DuplicateKeyError`, `OverflowError`, or `ConfigError`). Engine-native exceptions from `parseDateTime()`, `java.time.*.parse()`, or `chr()` on out-of-range Unicode no longer leak through.

## Known limitations

- Comment preservation across parse/emit is out of scope (per TOML library convention - revisit as `cfTOML-edit` in a future release).
- Case-sensitive ordered struct support is currently Adobe CF 2021+ only. CF 2016/2018, Lucee 5/6/7, and BoxLang either lack the type entirely or implement it in a way that defeats CFML's dot-notation accessor (Lucee/BoxLang's `ordered-casesensitive` struct returns a wrapper whose dot-notation accessor uppercases the lookup key, so a key stored as `section` cannot be read via `data.section`). On those engines the parser falls back to the case-insensitive ordered `[:]` literal, so a top-level pair of keys differing only in case (`section` and `sectioN`) collide. Bracket-notation access (`data["section"]`) works regardless.
- IEEE-754 precision limits affect integers above 2^53 in `int64Mode = "double"` (the default). Use `"javalong"` or `"string"` for full 64-bit range.
- CFML date objects are emitted as `DATETIME_LOCAL` (zone-naive). For specific offsets, pass a `java.time.OffsetDateTime` instance.
- Sub-second precision is preserved at millisecond level for `java.time.*` datetime values.

## Live demo

After cloning, start a local CFML server and open `demo.cfm` in a browser. The demo shows the engine and version it detected, lets you paste or pick a TOML payload to parse, lets you pick a pre-built CFML object (or paste JSON) to serialize, and reports both single-conversion time and the number of conversions per second.

If [cf_dump by kwaschny](https://github.com/kwaschny/cf_dump) is available, the demo also renders the parsed object through it below the JSON output. The native `<cfdump>` tag collapses line breaks inside strings and omits data types on scalars, so cf_dump gives a clearer picture of what came out of the parser.

```
git clone https://github.com/JamoCA/cfTOML.git
cd cfTOML
box server start
```

Then open http://localhost:8128/demo.cfm

## Development

```
git clone https://github.com/JamoCA/cfTOML.git
cd cfTOML
box server start
curl http://localhost:8128/tests/runner.cfm
```

To run the conformance suite:

```
powershell tests/conformance/fetch-corpus.ps1
curl http://localhost:8128/tests/conformance/run-conformance.cfm
```

To run the engine matrix:

```
powershell tools/run-engine-matrix.ps1
```

## License

MIT. See `LICENSE`.

## Author

James Moberg <james@sunstarmedia.com>
