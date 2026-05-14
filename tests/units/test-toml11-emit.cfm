<cfscript>
toml = new cfTOML.cfTOML();

// useExtendedEscapes=true under 1.1.0: ESC emitted as \e
out = toml.tomlSerialize(["s": "x" & chr(27) & "y"], ["spec": "1.1.0", "useExtendedEscapes": javacast("boolean", 1)]);
assertEquals(true, find("\e", out) gt 0, "Toml11Emit: ESC emits as \e when useExtendedEscapes=true");

// useExtendedEscapes=true under 1.1.0: U+001F emitted as \x1f
out = toml.tomlSerialize(["s": "x" & chr(31) & "y"], ["spec": "1.1.0", "useExtendedEscapes": javacast("boolean", 1)]);
assertEquals(true, find("\x1f", lcase(out)) gt 0, "Toml11Emit: U+001F emits as \x1f when useExtendedEscapes=true");

// Default under 1.1.0 (knob off): ESC still emits as \u001B (current behavior preserved)
out = toml.tomlSerialize(["s": "x" & chr(27) & "y"], ["spec": "1.1.0"]);
assertEquals(true, find("\u001B", out) gt 0, "Toml11Emit: ESC emits as \u001B when useExtendedEscapes=false");
assertEquals(0, find("\e", out), "Toml11Emit: no \e emitted when useExtendedEscapes=false");

// useExtendedEscapes=true under 1.0.0 throws ConfigError (already covered in Task 8 spec-option tests; just confirm here it is NOT silently producing output)
assertThrows("cfTOML\.ConfigError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlSerialize(["s": "x" & chr(27)], ["spec": "1.0.0", "useExtendedEscapes": javacast("boolean", 1)]);
}, "Toml11Emit: useExtendedEscapes throws under spec=1.0.0");

// 1.1.0 with named escapes still works (regression)
out = toml.tomlSerialize(["s": "tab" & chr(9) & "newline" & chr(10)], ["spec": "1.1.0", "useExtendedEscapes": javacast("boolean", 1)]);
assertEquals(true, find("\t", out) gt 0, "Toml11Emit: named \t escape preserved with useExtendedEscapes");
assertEquals(true, find("\n", out) gt 0, "Toml11Emit: named \n escape preserved with useExtendedEscapes");
</cfscript>

<cfscript>
toml = new cfTOML.cfTOML();

// 1.1.0 + omitZeroSeconds=true: LocalDateTime with HH:MM:00 emits as HH:MM
ldt = createObject("java", "java.time.LocalDateTime").of(1979, 5, 27, 7, 32, 0);
out = toml.tomlSerialize(["dt": ldt], ["spec": "1.1.0", "omitZeroSeconds": javacast("boolean", 1)]);
assertEquals(true, find("1979-05-27T07:32", out) gt 0, "Toml11Emit: LocalDateTime :00 omitted");
assertEquals(0, find("07:32:00", out), "Toml11Emit: no explicit :00 emitted");

// Non-zero seconds: preserved (omitZeroSeconds only omits :00)
ldt = createObject("java", "java.time.LocalDateTime").of(1979, 5, 27, 7, 32, 45);
out = toml.tomlSerialize(["dt": ldt], ["spec": "1.1.0", "omitZeroSeconds": javacast("boolean", 1)]);
assertEquals(true, find("07:32:45", out) gt 0, "Toml11Emit: non-zero seconds preserved");

// Default (knob off): :00 still emitted under 1.1.0
ldt = createObject("java", "java.time.LocalDateTime").of(1979, 5, 27, 7, 32, 0);
out = toml.tomlSerialize(["dt": ldt], ["spec": "1.1.0"]);
assertEquals(true, find("07:32:00", out) gt 0, "Toml11Emit: :00 preserved by default");

// Fractional second forces :SS keep (cannot omit :SS when fractional present)
ldt = createObject("java", "java.time.LocalDateTime").of(1979, 5, 27, 7, 32, 0, 500000000);
out = toml.tomlSerialize(["dt": ldt], ["spec": "1.1.0", "omitZeroSeconds": javacast("boolean", 1)]);
assertEquals(true, find("07:32:00.500", out) gt 0, "Toml11Emit: fractional seconds force :SS keep");

// OffsetDateTime with HH:MM:00 omits :00 under knob
odt = createObject("java", "java.time.OffsetDateTime").parse("1979-05-27T07:32:00Z");
out = toml.tomlSerialize(["odt": odt], ["spec": "1.1.0", "omitZeroSeconds": javacast("boolean", 1)]);
assertEquals(true, find("1979-05-27T07:32Z", out) gt 0, "Toml11Emit: OffsetDateTime :00 omitted with Z suffix");

// LocalTime with HH:MM:00 omits :00 under knob
ltime = createObject("java", "java.time.LocalTime").of(7, 32, 0);
out = toml.tomlSerialize(["t": ltime], ["spec": "1.1.0", "omitZeroSeconds": javacast("boolean", 1)]);
assertEquals(true, find("07:32", out) gt 0, "Toml11Emit: LocalTime :00 omitted");
assertEquals(0, find("07:32:", out), "Toml11Emit: LocalTime no trailing colon when omitted");
</cfscript>

<cfscript>
toml = new cfTOML.cfTOML();

// Default 1.1.0 (knob off): all-digit keys quoted
data = [:];
data["1234"] = "value";
out = toml.tomlSerialize(data, ["spec": "1.1.0"]);
assertEquals(true, find('"1234"', out) gt 0, "Toml11Emit: all-digit key quoted by default under 1.1.0");

// useBareDigitKeys=true under 1.1.0: emit bare
out = toml.tomlSerialize(data, ["spec": "1.1.0", "useBareDigitKeys": javacast("boolean", 1)]);
assertEquals(true, find("1234 = ", out) gt 0, "Toml11Emit: all-digit key bare when knob set");
assertEquals(0, find('"1234"', out), "Toml11Emit: no quoting when knob set");

// Non-bare keys (with space) still quoted under useBareDigitKeys=true
data = [:];
data["has space"] = "v";
out = toml.tomlSerialize(data, ["spec": "1.1.0", "useBareDigitKeys": javacast("boolean", 1)]);
assertEquals(true, find('"has space"', out) gt 0, "Toml11Emit: non-bare key quoted regardless of knob");

// Round-trip under 1.1.0 + both knobs aligned
data = [:];
data["1234"] = "v1";
data["foo"] = "v2";
out = toml.tomlSerialize(data, ["spec": "1.1.0", "useBareDigitKeys": javacast("boolean", 1)]);
parsed = toml.tomlDeserialize(out, ["spec": "1.1.0"]);
assertEquals("v1", parsed["1234"], "Toml11Emit: round-trip 1234 key");
assertEquals("v2", parsed.foo, "Toml11Emit: round-trip foo key");
</cfscript>

<cfscript>
toml = new cfTOML.cfTOML();

// Short inline struct: stays single-line even with knob on (under 80 chars)
data = ["t": ["a": 1, "b": 2]];
out = toml.tomlSerialize(data, ["spec": "1.1.0", "inlineMultiline": javacast("boolean", 1), "inlineThreshold": 5]);
assertEquals(true, find("{ a = 1, b = 2 }", out) gt 0, "Toml11Emit: short inline stays single-line");

// Long inline struct (>80 chars): switches to multi-line
longData = ["t": [
	"first_name": "Donald",
	"last_name": "Duck",
	"email": "donald@duckburg.com",
	"phone": "+1-555-DUCK-OUT"
]];
out = toml.tomlSerialize(longData, ["spec": "1.1.0", "inlineMultiline": javacast("boolean", 1), "inlineThreshold": 10]);
// Multi-line form: opening { then newline then keys
assertEquals(true, find("{" & chr(10), out) gt 0, "Toml11Emit: long inline opens { with newline");
assertEquals(true, find(chr(10) & "}", out) gt 0, "Toml11Emit: long inline closes } on its own line");

// Default (knob off): single-line regardless of width
out = toml.tomlSerialize(longData, ["spec": "1.1.0", "inlineThreshold": 10]);
assertEquals(0, find("{" & chr(10), out), "Toml11Emit: knob off stays single-line");

// Round-trip after multi-line emit
out = toml.tomlSerialize(longData, ["spec": "1.1.0", "inlineMultiline": javacast("boolean", 1), "inlineThreshold": 10]);
parsed = toml.tomlDeserialize(out, ["spec": "1.1.0"]);
assertEquals("Donald", parsed.t.first_name, "Toml11Emit: round-trip after multi-line emit");
</cfscript>
