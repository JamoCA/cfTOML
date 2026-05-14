<cfscript>
toml = new cfTOML.cfTOML();

// 1.1.0 mode: \e decodes to U+001B
result = toml.tomlDeserialize('s = "before\eafter"', ["spec": "1.1.0"]);
assertEquals("before" & chr(27) & "after", result.s, "Toml11Escapes: \e decodes to U+001B under 1.1.0");

// 1.0.0 mode: \e is unknown escape, throws
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlDeserialize('s = "x\ey"', ["spec": "1.0.0"]);
}, "Toml11Escapes: \e throws under 1.0.0");

// 1.1.0 mode: \e in multi-line basic strings too
result = toml.tomlDeserialize('s = """' & chr(10) & 'line1\eline2"""', ["spec": "1.1.0"]);
assertEquals("line1" & chr(27) & "line2", result.s, "Toml11Escapes: \e in multi-line basic under 1.1.0");

// 1.1.0 mode: \x41 decodes to "A"
result = toml.tomlDeserialize('s = "\x41"', ["spec": "1.1.0"]);
assertEquals("A", result.s, "Toml11Escapes: \x41 decodes to A under 1.1.0");

// 1.1.0 mode: \xFF decodes to U+00FF
result = toml.tomlDeserialize('s = "\xff"', ["spec": "1.1.0"]);
assertEquals(chr(255), result.s, "Toml11Escapes: \xff decodes to U+00FF under 1.1.0");

// 1.1.0 mode: case-insensitive hex digits accepted
result = toml.tomlDeserialize('s = "\xAb"', ["spec": "1.1.0"]);
assertEquals(chr(171), result.s, "Toml11Escapes: \xAb decodes to U+00AB under 1.1.0");

// 1.1.0 mode: exactly 2 hex digits required, third hex digit is literal text
result = toml.tomlDeserialize('s = "\x412"', ["spec": "1.1.0"]);
assertEquals("A2", result.s, "Toml11Escapes: \x412 decodes to 'A' then literal '2' under 1.1.0");

// 1.1.0 mode: non-hex char after \x throws
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlDeserialize('s = "\xZZ"', ["spec": "1.1.0"]);
}, "Toml11Escapes: invalid \xHH throws under 1.1.0");

// 1.0.0 mode: \x is unknown escape, throws
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlDeserialize('s = "\x41"', ["spec": "1.0.0"]);
}, "Toml11Escapes: \x throws under 1.0.0");

// 1.1.0 mode: \x in multi-line basic
result = toml.tomlDeserialize('s = """' & chr(10) & '\x41line"""', ["spec": "1.1.0"]);
assertEquals("Aline", result.s, "Toml11Escapes: \x in multi-line basic under 1.1.0");
</cfscript>
<cfscript>
// 1.1.0 mode: \x with only 1 trailing char throws truncation error
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlDeserialize('s = "\x4"', ["spec": "1.1.0"]);
}, "Toml11Escapes: truncated \x throws under 1.1.0");
</cfscript>
