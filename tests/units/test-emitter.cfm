<cfscript>
// Empty struct -> empty string
assertEquals("", parser.tomlSerialize([:]), "Emitter: empty struct yields empty string");

// Single integer KV
assertEquals("port = 8080" & chr(10), parser.tomlSerialize(["port": 8080]), "Emitter: integer KV");

// Single boolean KV
assertEquals("flag = true" & chr(10), parser.tomlSerialize(["flag": javacast("boolean", 1)]), "Emitter: bool true KV");
assertEquals("flag = false" & chr(10), parser.tomlSerialize(["flag": javacast("boolean", 0)]), "Emitter: bool false KV");

// Single float KV
assertEquals("ratio = 1.5" & chr(10), parser.tomlSerialize(["ratio": 1.5]), "Emitter: float KV");

// Negative integer
assertEquals("temp = -7" & chr(10), parser.tomlSerialize(["temp": -7]), "Emitter: negative integer");

// String KV (basic only - no special chars)
assertEquals('title = "Hello"' & chr(10), parser.tomlSerialize(["title": "Hello"]), "Emitter: basic string");

// Multiple KV pairs preserve order
expected = 'name = "app"' & chr(10) & "port = 8080" & chr(10);
result = parser.tomlSerialize(["name": "app", "port": 8080]);
assertEquals(expected, result, "Emitter: multiple KV pairs in order");

// Bare-key-eligible key uses bare form
assertEquals("my-key = 1" & chr(10), parser.tomlSerialize(["my-key": 1]), "Emitter: bare key with hyphen");

// Non-bare key gets quoted
assertEquals('"my key" = 1' & chr(10), parser.tomlSerialize(["my key": 1]), "Emitter: quoted key with space");

// Basic string with escape-required characters
assertEquals('s = "tab\there"' & chr(10), parser.tomlSerialize(["s": "tab" & chr(9) & "here"]), "Emitter: tab encoded as \\t");
assertEquals('s = "line\nhere"' & chr(10), parser.tomlSerialize(["s": "line" & chr(10) & "here"]), "Emitter: newline-containing value uses basic with \\n");

// String with backslash but no single-quote becomes literal string
assertEquals("s = 'C:\path\file'" & chr(10), parser.tomlSerialize(["s": "C:\path\file"]), "Emitter: backslash string uses literal quotes");

// String with double-quote in it stays basic and escapes
assertEquals('s = "say \"hi\""' & chr(10), parser.tomlSerialize(["s": 'say "hi"']), "Emitter: double-quote in basic string is escaped");

// Empty string
assertEquals('s = ""' & chr(10), parser.tomlSerialize(["s": ""]), "Emitter: empty string emitted as empty basic");

// CFML date object: emit as DATETIME_LOCAL (no quotes - TOML datetime is a distinct value type)
cfDateVal = createDateTime(1979, 5, 27, 7, 32, 0);
expected = "when = 1979-05-27T07:32:00" & chr(10);
result = parser.tomlSerialize(["when": cfDateVal]);
assertEquals(expected, result, "Emitter: CFML date -> DATETIME_LOCAL (no zone)");

// CFML strings stay as TOML strings even if they look like ISO 8601.
// Round-trip safety: a user-supplied string "2024-01-15" must NOT be silently emitted as a TOML date value
// (which would round-trip back as a date object, breaking type fidelity).
assertEquals('when = "1979-05-27T07:32:00-08:00"' & chr(10), parser.tomlSerialize(["when": "1979-05-27T07:32:00-08:00"]), "Emitter: ISO 8601 STRING stays as quoted TOML string (no auto-coercion)");

// Java OffsetDateTime
javaOffset = createObject("java", "java.time.OffsetDateTime").parse("1979-05-27T07:32:00-08:00");
expected = "when = 1979-05-27T07:32:00-08:00" & chr(10);
assertEquals(expected, parser.tomlSerialize(["when": javaOffset]), "Emitter: java.time.OffsetDateTime");

// Java LocalDate
javaLocalDate = createObject("java", "java.time.LocalDate").parse("1979-05-27");
expected = "when = 1979-05-27" & chr(10);
assertEquals(expected, parser.tomlSerialize(["when": javaLocalDate]), "Emitter: java.time.LocalDate");

// Empty array
assertEquals("nums = []" & chr(10), parser.tomlSerialize(["nums": []]), "Emitter: empty array");

// Integer array
assertEquals("nums = [1, 2, 3]" & chr(10), parser.tomlSerialize(["nums": [1, 2, 3]]), "Emitter: integer array");

// String array
assertEquals('tags = ["a", "b", "c"]' & chr(10), parser.tomlSerialize(["tags": ["a", "b", "c"]]), "Emitter: string array");

// Nested array
assertEquals("matrix = [[1, 2], [3, 4]]" & chr(10), parser.tomlSerialize(["matrix": [[1, 2], [3, 4]]]), "Emitter: nested array");

// Mixed-type array
assertEquals('mix = [1, "two", true]' & chr(10), parser.tomlSerialize(["mix": [1, "two", javacast("boolean", 1)]]), "Emitter: mixed-type array");

// Inline table inside an array (struct array element) - now emitted as AoT after Task 8
expected = "[[items]]" & chr(10) & "id = 1" & chr(10) & chr(10) & "[[items]]" & chr(10) & "id = 2" & chr(10);
result = parser.tomlSerialize(["items": [["id": 1], ["id": 2]]]);
assertEquals(expected, result, "Emitter: array of structs emits as AoT blocks (changed from Task 6 inline form)");

// Empty struct inside array - now emitted as AoT after Task 8
expected = "[[items]]" & chr(10);
result = parser.tomlSerialize(["items": [[:]]]);
assertEquals(expected, result, "Emitter: array of single empty struct emits as one [[items]] block");

// Single [table] section
expected = 'name = "app"' & chr(10) & chr(10) & "[server]" & chr(10) & 'host = "10.0.0.1"' & chr(10);
result = parser.tomlSerialize(["name": "app", "server": ["host": "10.0.0.1"]]);
assertEquals(expected, result, "Emitter: top-level scalar + nested [server] block");

// Dotted-path header [server.config]
expected = "[server.config]" & chr(10) & "timeout = 30" & chr(10);
result = parser.tomlSerialize(["server": ["config": ["timeout": 30]]]);
assertEquals(expected, result, "Emitter: dotted-path table header");

// Multiple sub-tables under a root table
expected = "[server]" & chr(10) & 'host = "h"' & chr(10) & chr(10) & "[server.config]" & chr(10) & "timeout = 30" & chr(10);
result = parser.tomlSerialize(["server": ["host": "h", "config": ["timeout": 30]]]);
assertEquals(expected, result, "Emitter: [server] then [server.config]");

// Single [[products]] entry
expected = "[[products]]" & chr(10) & 'name = "x"' & chr(10);
result = parser.tomlSerialize(["products": [["name": "x"]]]);
assertEquals(expected, result, "Emitter: single AoT entry");

// Two [[products]] entries
expected = "[[products]]" & chr(10) & 'name = "a"' & chr(10) & chr(10) & "[[products]]" & chr(10) & 'name = "b"' & chr(10);
result = parser.tomlSerialize(["products": [["name": "a"], ["name": "b"]]]);
assertEquals(expected, result, "Emitter: two AoT entries");

// Nested AoT path [[a.b]]
expected = "[[fruits.varieties]]" & chr(10) & 'name = "red"' & chr(10);
result = parser.tomlSerialize(["fruits": ["varieties": [["name": "red"]]]]);
assertEquals(expected, result, "Emitter: nested AoT path");

// sortKeys = true: alphabetical
expected = 'a = 1' & chr(10) & 'b = 2' & chr(10) & 'c = 3' & chr(10);
result = parser.tomlSerialize(["c": 3, "a": 1, "b": 2], ["sortKeys": javacast("boolean", 1)]);
assertEquals(expected, result, "Emitter: sortKeys true alphabetizes");

// sortKeys default false: insertion order preserved
expected = 'c = 3' & chr(10) & 'a = 1' & chr(10) & 'b = 2' & chr(10);
result = parser.tomlSerialize(["c": 3, "a": 1, "b": 2]);
assertEquals(expected, result, "Emitter: sortKeys default preserves insertion order");

// indent with tab: KV lines under [header] get prepended with tab
expected = "[server]" & chr(10) & chr(9) & 'host = "h"' & chr(10);
result = parser.tomlSerialize(["server": ["host": "h"]], ["indent": chr(9)]);
assertEquals(expected, result, "Emitter: indent tab under [header]");

// indent applied at deeper levels (2 tabs at depth 2)
expected = "[server]" & chr(10) & chr(9) & 'host = "h"' & chr(10) & chr(10) & "[server.config]" & chr(10) & chr(9) & chr(9) & 'timeout = 30' & chr(10);
result = parser.tomlSerialize(["server": ["host": "h", "config": ["timeout": 30]]], ["indent": chr(9)]);
assertEquals(expected, result, "Emitter: indent grows with depth");

// Default behavior: nested struct gets [header] block
expected = "[point]" & chr(10) & "x = 1" & chr(10) & "y = 2" & chr(10);
result = parser.tomlSerialize(["point": ["x": 1, "y": 2]]);
assertEquals(expected, result, "Emitter: inlineThreshold=0 (default) uses [header]");

// inlineThreshold = 5 and struct has 2 scalar keys -> inline
expected = "point = { x = 1, y = 2 }" & chr(10);
result = parser.tomlSerialize(["point": ["x": 1, "y": 2]], ["inlineThreshold": 5]);
assertEquals(expected, result, "Emitter: inlineThreshold=5 with 2-key struct emits inline");

// Struct that exceeds threshold stays as [header] block
expected = "[point]" & chr(10) & "x = 1" & chr(10) & "y = 2" & chr(10) & "z = 3" & chr(10);
result = parser.tomlSerialize(["point": ["x": 1, "y": 2, "z": 3]], ["inlineThreshold": 2]);
assertEquals(expected, result, "Emitter: struct exceeds threshold stays as [header]");

// Struct with nested struct is NOT inline-eligible even if threshold permits key count
expected = "[outer.inner]" & chr(10) & "x = 1" & chr(10);
result = parser.tomlSerialize(["outer": ["inner": ["x": 1]]], ["inlineThreshold": 5]);
assertEquals(expected, result, "Emitter: struct with nested struct stays as [header] regardless of threshold (no spurious [outer] header)");

// onNull = "skip" (default): null key omitted
result = parser.tomlSerialize(["a": 1, "b": javacast("null", 0)]);
assertEquals("a = 1" & chr(10), result, "Emitter: onNull=skip default omits null");

// onNull = "throw": ParseError
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlSerialize(["b": javacast("null", 0)], ["onNull": "throw"]);
}, "Emitter: onNull=throw raises TypeError");

// onNull = "emptyString": emit key = ""
result = parser.tomlSerialize(["b": javacast("null", 0)], ["onNull": "emptyString"]);
assertEquals('b = ""' & chr(10), result, "Emitter: onNull=emptyString emits empty");

// query without queryAsArrayOfTables option: throws
q = queryNew("name,age", "varchar,integer");
queryAddRow(q);
querySetCell(q, "name", "Alice", 1);
querySetCell(q, "age", 30, 1);
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlSerialize(["users": q]);
}, "Emitter: query without queryAsArrayOfTables throws TypeError");

// query with queryAsArrayOfTables: converts to AoT
result = parser.tomlSerialize(["users": q], ["queryAsArrayOfTables": javacast("boolean", 1)]);
expected = "[[users]]" & chr(10) & 'name = "Alice"' & chr(10) & "age = 30" & chr(10);
assertEquals(expected, result, "Emitter: query converts to AoT");

// Write and read back
tempPath = getTempDirectory() & "cftoml-write-test-" & createUUID() & ".toml";
parser.tomlWriteFile(tempPath, ["x": 1, "name": "test"]);
assert(fileExists(tempPath), "WriteFile: file created");
// Read raw bytes via Java's Files.readAllBytes to avoid engine-specific text-mode side effects. CFML's
// fileRead (text mode) is permitted by some engines - notably BoxLang on Windows - to normalize line
// endings (rewriting `\n` to `\r\n` mid-string and stripping the trailing newline). The contract for
// tomlWriteFile is bit-for-bit, so the test reads the bytes and reconstructs the string via Java's
// strict UTF-8 decoder.
content = createObject("java", "java.lang.String").init(
	createObject("java", "java.nio.file.Files").readAllBytes(
		createObject("java", "java.nio.file.Paths").get(javaCast("string", tempPath), [])
	),
	createObject("java", "java.nio.charset.StandardCharsets").UTF_8
);
assertEquals("x = 1" & chr(10) & 'name = "test"' & chr(10), content, "WriteFile: file content matches expected");
fileDelete(tempPath);

// Fix 1: control char in string that would otherwise pick literal variant
result = parser.tomlSerialize(["s": "C:\path" & chr(10) & "file"]);
// Backslash + newline: literal variant would produce invalid TOML. Force basic with escaping.
assertEquals('s = "C:\\path\nfile"' & chr(10), result, "Fix1: backslash + newline forces basic-string variant");

// Fix 2: non-whole float emits with a decimal point everywhere.
// Note on whole-number Doubles: the emitter intentionally emits whole-number Doubles as TOML integers
// for cross-engine consistency. Lucee stores all numeric literals as Double regardless of source, so
// distinguishing `1` from `1.0` at the engine level is not portable - the round-trip-to-float promise
// would only hold on Adobe CF and BoxLang. Callers who specifically want a TOML float should pass a
// non-whole numeric value or an exponent.
floatVal = javacast("double", 1.5);
result = parser.tomlSerialize(["x": floatVal]);
assertEquals("x = 1.5" & chr(10), result, "Fix2: non-whole float emits with decimal");

// Fix 3: NaN, Inf emission
nanVal = createObject("java", "java.lang.Double").NaN;
infVal = createObject("java", "java.lang.Double").POSITIVE_INFINITY;
negInfVal = createObject("java", "java.lang.Double").NEGATIVE_INFINITY;
assertEquals("v = nan" & chr(10), parser.tomlSerialize(["v": nanVal]), "Fix3: NaN emits as nan");
assertEquals("v = inf" & chr(10), parser.tomlSerialize(["v": infVal]), "Fix3: +Inf emits as inf");
assertEquals("v = -inf" & chr(10), parser.tomlSerialize(["v": negInfVal]), "Fix3: -Inf emits as -inf");

// Fix 4: quoted key with embedded double-quote
fix4Key = "my" & chr(34) & "key";
fix4Data = {};
fix4Data[fix4Key] = 1;
result = parser.tomlSerialize(fix4Data);
// Expected: key escaped via basic-string rules. The key is my"key. Quoted: "my\"key"
// chr(34) = double-quote, chr(92) = backslash
expected = chr(34) & "my" & chr(92) & chr(34) & "key" & chr(34) & " = 1" & chr(10);
assertEquals(expected, result, "Fix4: quoted key escapes embedded double-quote");

// Fix 5: inline table respects sortKeys
result = parser.tomlSerialize(["pt": ["z": 3, "a": 1, "m": 2]], ["inlineThreshold": 5, "sortKeys": javacast("boolean", 1)]);
assertEquals("pt = { a = 1, m = 2, z = 3 }" & chr(10), result, "Fix5: emitInlineTable respects sortKeys");

// Phase 6 fix: CFML date is zone-naive, emit as DATETIME_LOCAL (no Z)
cfDateNaive = createDateTime(1979, 5, 27, 7, 32, 0);
expected = "when = 1979-05-27T07:32:00" & chr(10);
result = parser.tomlSerialize(["when": cfDateNaive]);
assertEquals(expected, result, "P6-Fix: CFML date emits as DATETIME_LOCAL (no Z suffix)");

// Round-trip cfDate -> serialize -> parse back -> cfDate equality
firstParse = parser.tomlDeserialize("when = 1979-05-27T07:32:00");
emitted = parser.tomlSerialize(firstParse);
secondParse = parser.tomlDeserialize(emitted);
assertEquals(firstParse.when, secondParse.when, "P6-Fix: CFML datetime round-trips bit-for-bit");

// Phase 6 fix: UTC OffsetDateTime emits as Z, not +00:00
utcOffset = createObject("java", "java.time.OffsetDateTime").parse("1979-05-27T07:32:00+00:00");
expected = "when = 1979-05-27T07:32:00Z" & chr(10);
result = parser.tomlSerialize(["when": utcOffset]);
assertEquals(expected, result, "P6-Fix: UTC OffsetDateTime emits canonical Z");

// Non-UTC offset stays with explicit offset
nonUtcOffset = createObject("java", "java.time.OffsetDateTime").parse("1979-05-27T07:32:00-08:00");
expected = "when = 1979-05-27T07:32:00-08:00" & chr(10);
result = parser.tomlSerialize(["when": nonUtcOffset]);
assertEquals(expected, result, "P6-Fix: Non-UTC OffsetDateTime keeps explicit offset");

// Phase 6 fix: sub-second precision preserved (millisecond)
withMs = createObject("java", "java.time.OffsetDateTime").parse("1979-05-27T07:32:00.123-08:00");
expected = "when = 1979-05-27T07:32:00.123-08:00" & chr(10);
result = parser.tomlSerialize(["when": withMs]);
assertEquals(expected, result, "P6-Fix: OffsetDateTime preserves millisecond precision");

// Zero milliseconds: emit without the .000
noMs = createObject("java", "java.time.OffsetDateTime").parse("1979-05-27T07:32:00-08:00");
expected = "when = 1979-05-27T07:32:00-08:00" & chr(10);
result = parser.tomlSerialize(["when": noMs]);
assertEquals(expected, result, "P6-Fix: OffsetDateTime with zero ms emits without .000");

// LocalDateTime preserves milliseconds
withMsLocal = createObject("java", "java.time.LocalDateTime").parse("1979-05-27T07:32:00.456");
expected = "when = 1979-05-27T07:32:00.456" & chr(10);
result = parser.tomlSerialize(["when": withMsLocal]);
assertEquals(expected, result, "P6-Fix: LocalDateTime preserves millisecond precision");
</cfscript>
