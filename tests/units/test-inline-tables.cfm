<cfscript>
// Empty inline table
result = parser.tomlDeserialize("x = {}");
assert(isStruct(result.x), "Inline: empty inline table is struct");
assertEquals(0, structcount(result.x), "Inline: empty inline table count");

// Simple inline table with scalars
result = parser.tomlDeserialize('point = {x = 1, y = 2}');
assertEquals(1, result.point.x, "Inline: point.x");
assertEquals(2, result.point.y, "Inline: point.y");

// Mixed types inside inline table
result = parser.tomlDeserialize('cfg = {name = "app", port = 8080, ready = true}');
assertEquals("app", result.cfg.name, "Inline: mixed string");
assertEquals(8080, result.cfg.port, "Inline: mixed int");
assertEquals(javacast("boolean", 1), result.cfg.ready, "Inline: mixed bool");

// Dotted key inside inline table
result = parser.tomlDeserialize('cfg = {db.host = "localhost", db.port = 5432}');
assertEquals("localhost", result.cfg.db.host, "Inline: dotted key creates sub-struct");
assertEquals(5432, result.cfg.db.port, "Inline: dotted key sibling");

// Nested inline table
result = parser.tomlDeserialize('outer = {inner = {x = 1}}');
assertEquals(1, result.outer.inner.x, "Inline: nested inline table");

// Inline table inside array
result = parser.tomlDeserialize('items = [{id = 1}, {id = 2}]');
assertEquals(2, arraylen(result.items), "Inline: array of inline tables length");
assertEquals(1, result.items[1].id, "Inline: array element 1");
assertEquals(2, result.items[2].id, "Inline: array element 2");

// Array inside inline table
result = parser.tomlDeserialize('cfg = {nums = [1, 2, 3]}');
assertEquals(3, arraylen(result.cfg.nums), "Inline: array inside inline table");
assertEquals(2, result.cfg.nums[2], "Inline: array element inside inline table");

// Dotted key cannot walk INTO an inline table
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlDeserialize('point = {x = 1}' & chr(10) & 'point.y = 2');
}, "Inline: dotted-key walk into inline table throws TypeError");

// [table.sub] header cannot walk into inline table
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlDeserialize('point = {x = 1}' & chr(10) & '[point.sub]' & chr(10) & 'a = 2');
}, "Inline: [table.sub] header walking into inline table throws TypeError");

// Issue C: trailing comma in inline table is not allowed per TOML 1.0
assertThrows("cfTOML\.ParseError", function() {
	parser.tomlDeserialize('point = {x = 1, y = 2,}');
}, "Inline: trailing comma in inline table throws ParseError");
</cfscript>
