<cfscript>
// Empty token array -> empty ordered struct
result = parser.parseTokens([], parser.mergeOptionsForTest());
assertEquals(0, structcount(result), "Parser: empty input yields empty struct");
assert(isStruct(result), "Parser: empty input yields a struct");
</cfscript>

<cfscript>
// Single string KV
result = parser.parseTokens(parser.tokenize('title = "TOML Example"'), parser.mergeOptionsForTest());
assertEquals(1, structcount(result), "Parser: single KV yields 1 entry");
assert(structkeyexists(result, "title"), "Parser: title key present");
assertEquals("TOML Example", result.title, "Parser: title value decoded");

// Integer
result = parser.parseTokens(parser.tokenize("port = 8080"), parser.mergeOptionsForTest());
assertEquals(8080, result.port, "Parser: integer value");

// Boolean
result = parser.parseTokens(parser.tokenize("enabled = true"), parser.mergeOptionsForTest());
assertEquals(javacast("boolean", 1), result.enabled, "Parser: boolean true value");

// Float
result = parser.parseTokens(parser.tokenize("ratio = 0.5"), parser.mergeOptionsForTest());
assertEquals(0.5, result.ratio, "Parser: float value");

// Literal string
result = parser.parseTokens(parser.tokenize("path = 'C:\winpath'"), parser.mergeOptionsForTest());
assertEquals("C:\winpath", result.path, "Parser: literal string value");

// Multi-line basic with escape decoding
result = parser.parseTokens(parser.tokenize('msg = """hello\nworld"""'), parser.mergeOptionsForTest());
assertEquals("hello" & chr(10) & "world", result.msg, "Parser: ML basic with decoded escape");

// Multiple KV pairs on separate lines
result = parser.parseTokens(parser.tokenize("a = 1" & chr(10) & "b = 2" & chr(10)), parser.mergeOptionsForTest());
assertEquals(1, result.a, "Parser: multi-KV first");
assertEquals(2, result.b, "Parser: multi-KV second");
</cfscript>

<cfscript>
// [table] section with one KV
toml = "[server]" & chr(10) & 'host = "10.0.0.1"' & chr(10);
result = parser.parseTokens(parser.tokenize(toml), parser.mergeOptionsForTest());
assert(structkeyexists(result, "server"), "Parser: server table created");
assert(isStruct(result.server), "Parser: server table is a struct");
assertEquals("10.0.0.1", result.server.host, "Parser: server.host value");

// Two tables
toml = '[server]' & chr(10) & 'host = "10.0.0.1"' & chr(10) & '[client]' & chr(10) & 'host = "10.0.0.2"' & chr(10);
result = parser.parseTokens(parser.tokenize(toml), parser.mergeOptionsForTest());
assertEquals("10.0.0.1", result.server.host, "Parser: first table host");
assertEquals("10.0.0.2", result.client.host, "Parser: second table host");

// Top-level KV followed by [table]
toml = 'name = "app"' & chr(10) & '[server]' & chr(10) & 'host = "10.0.0.1"' & chr(10);
result = parser.parseTokens(parser.tokenize(toml), parser.mergeOptionsForTest());
assertEquals("app", result.name, "Parser: top-level KV before table");
assertEquals("10.0.0.1", result.server.host, "Parser: table KV after top-level");
</cfscript>

<cfscript>
// Dotted header
toml = "[server.alpha]" & chr(10) & 'ip = "10.0.0.1"' & chr(10);
result = parser.parseTokens(parser.tokenize(toml), parser.mergeOptionsForTest());
assert(structkeyexists(result, "server"), "Parser: dotted header creates root.server");
assert(structkeyexists(result.server, "alpha"), "Parser: dotted header creates root.server.alpha");
assertEquals("10.0.0.1", result.server.alpha.ip, "Parser: dotted header value placement");

// Header [a.b] then [a.c] - sibling subtables share parent
toml = "[a.b]" & chr(10) & "x = 1" & chr(10) & "[a.c]" & chr(10) & "y = 2" & chr(10);
result = parser.parseTokens(parser.tokenize(toml), parser.mergeOptionsForTest());
assertEquals(1, result.a.b.x, "Parser: a.b.x");
assertEquals(2, result.a.c.y, "Parser: a.c.y");
</cfscript>

<cfscript>
// Dotted key at top level
result = parser.parseTokens(parser.tokenize("a.b.c = 1"), parser.mergeOptionsForTest());
assertEquals(1, result.a.b.c, "Parser: dotted key at top level");

// Dotted key inside a [table] section
toml = "[server]" & chr(10) & "config.timeout = 30" & chr(10);
result = parser.parseTokens(parser.tokenize(toml), parser.mergeOptionsForTest());
assertEquals(30, result.server.config.timeout, "Parser: dotted key inside table");

// Mixed: bare key and dotted key in same table
toml = "[server]" & chr(10) & 'host = "host"' & chr(10) & "config.port = 80" & chr(10);
result = parser.parseTokens(parser.tokenize(toml), parser.mergeOptionsForTest());
assertEquals("host", result.server.host, "Parser: bare key alongside dotted key");
assertEquals(80, result.server.config.port, "Parser: dotted key alongside bare key");
</cfscript>

<cfscript>
// Duplicate top-level key
assertThrows("cfTOML\.DuplicateKeyError", function() {
	parser.parseTokens(parser.tokenize("a = 1" & chr(10) & "a = 2"), parser.mergeOptionsForTest());
}, "Parser: duplicate top-level key throws DuplicateKeyError");

// Duplicate key inside table
assertThrows("cfTOML\.DuplicateKeyError", function() {
	parser.parseTokens(parser.tokenize("[t]" & chr(10) & "k = 1" & chr(10) & "k = 2"), parser.mergeOptionsForTest());
}, "Parser: duplicate key inside table throws DuplicateKeyError");

// Same key in different tables is fine (not a duplicate)
result = parser.parseTokens(parser.tokenize("[a]" & chr(10) & "k = 1" & chr(10) & "[b]" & chr(10) & "k = 2"), parser.mergeOptionsForTest());
assertEquals(1, result.a.k, "Parser: same key in different tables - a.k");
assertEquals(2, result.b.k, "Parser: same key in different tables - b.k");
</cfscript>

<cfscript>
// [a] defined twice
assertThrows("cfTOML\.DuplicateKeyError", function() {
	parser.parseTokens(parser.tokenize("[a]" & chr(10) & "x = 1" & chr(10) & "[a]" & chr(10) & "y = 2"), parser.mergeOptionsForTest());
}, "Parser: redefining [a] throws DuplicateKeyError");

// [a.b] then [a] is OK - a was implicit, promoted to explicit
result = parser.parseTokens(parser.tokenize("[a.b]" & chr(10) & "y = 2" & chr(10) & "[a]" & chr(10) & "x = 1"), parser.mergeOptionsForTest());
assertEquals(1, result.a.x, "Parser: implicit a promoted to explicit");
assertEquals(2, result.a.b.y, "Parser: a.b retained after a promotion");

// [a] then [a.b] is OK
result = parser.parseTokens(parser.tokenize("[a]" & chr(10) & "x = 1" & chr(10) & "[a.b]" & chr(10) & "y = 2"), parser.mergeOptionsForTest());
assertEquals(1, result.a.x, "Parser: a then a.b - a.x");
assertEquals(2, result.a.b.y, "Parser: a then a.b - a.b.y");
</cfscript>

<cfscript>
// tomlDeserialize end-to-end
result = parser.tomlDeserialize("port = 8080" & chr(10));
assertEquals(8080, result.port, "Deserialize: port=8080");

// Deserialize with options override
result = parser.tomlDeserialize("when = 2024-01-15", {"dateTimeReturn": "iso8601"});
assertEquals("2024-01-15", result.when, "Deserialize: iso8601 mode returns string");
</cfscript>

<cfscript>
// End-to-end via tomlReadFile
result = parser.tomlReadFile(expandPath("/cfTOML/examples/basic.toml"));
assertEquals("cfTOML Example", result.title, "E2E: title");
assertEquals(1.0, result.version, "E2E: version");
assertEquals("10.0.0.1", result.server.host, "E2E: server.host");
assertEquals(8080, result.server.port, "E2E: server.port");
assertEquals(javacast("boolean", 1), result.server.enabled, "E2E: server.enabled");
assertEquals(30, result.server.config.timeout, "E2E: server.config.timeout");
assertEquals(3, result.server.config.retries, "E2E: server.config.retries");
assertEquals("10.0.0.2", result.client.host, "E2E: client.host");
assertEquals(9090, result.client.port, "E2E: client.port");
</cfscript>

<cfscript>
// Quoted single segment: header is ["my key"] - tokenizer captures raw "my key" (with quotes)
result = parser.parseTokens(parser.tokenize('[' & chr(34) & 'my key' & chr(34) & ']' & chr(10) & 'a = 1'), parser.mergeOptionsForTest());
assert(structkeyexists(result, "my key"), "QPath: quoted segment with space");
assertEquals(1, result["my key"].a, "QPath: value placed under quoted segment");

// Quoted segment with dot inside (the dot is literal, not a separator)
result = parser.parseTokens(parser.tokenize('[' & chr(34) & 'my.server' & chr(34) & ']' & chr(10) & 'a = 1'), parser.mergeOptionsForTest());
assert(structkeyexists(result, "my.server"), "QPath: dot inside quoted segment is literal");
assertEquals(1, result["my.server"].a, "QPath: value under dotted-quoted segment");

// Mixed: bare and quoted segments
result = parser.parseTokens(parser.tokenize('[a.' & chr(34) & 'x.y' & chr(34) & '.b]' & chr(10) & 'k = 1'), parser.mergeOptionsForTest());
assert(structkeyexists(result.a["x.y"].b, "k"), "QPath: mixed bare and quoted segments");
assertEquals(1, result.a["x.y"].b.k, "QPath: mixed segments value");

// Literal-string segment (single quotes)
result = parser.parseTokens(parser.tokenize("['raw\path']" & chr(10) & "k = 1"), parser.mergeOptionsForTest());
assert(structkeyexists(result, "raw\path"), "QPath: literal-string segment preserves backslash");
</cfscript>

<cfscript>
// E2E with arrays, inline tables, AoT
result = parser.tomlReadFile(expandPath("/cfTOML/examples/basic.toml"));

// Array of strings
assertEquals(3, arraylen(result.features.tags), "E2E: features.tags length");
assertEquals("alpha", result.features.tags[1], "E2E: features.tags[1]");
assertEquals("stable", result.features.tags[3], "E2E: features.tags[3]");

// Array of integers
assertEquals(2, result.features.counts[2], "E2E: features.counts[2]");

// Inline table
assertEquals("10.0.0.1", result.features.endpoint.host, "E2E: features.endpoint.host");
assertEquals(9090, result.features.endpoint.port, "E2E: features.endpoint.port");

// Array of tables
assertEquals(2, arraylen(result.products), "E2E: products array length");
assertEquals("widget", result.products[1].name, "E2E: products[1].name");
assertEquals("W-001", result.products[1].sku, "E2E: products[1].sku");
assertEquals("gadget", result.products[2].name, "E2E: products[2].name");

// AoT under AoT - both suppliers attach to products[2]
assertEquals(2, arraylen(result.products[2].suppliers), "E2E: products[2].suppliers length");
assertEquals("Acme", result.products[2].suppliers[1].name, "E2E: first supplier");
assertEquals("Globex", result.products[2].suppliers[2].name, "E2E: second supplier");
</cfscript>
