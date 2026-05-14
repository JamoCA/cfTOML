<cfscript>
// First [[products]] creates root.products = array of 1 ordered struct
result = parser.tomlDeserialize("[[products]]" & chr(10) & 'name = "x"');
assert(isArray(result.products), "AoT: root.products is array");
assertEquals(1, arraylen(result.products), "AoT: first occurrence creates array of length 1");
assertEquals("x", result.products[1].name, "AoT: first element's KV");

// Two [[products]] entries
result = parser.tomlDeserialize("[[products]]" & chr(10) & 'name = "a"' & chr(10) & "[[products]]" & chr(10) & 'name = "b"');
assertEquals(2, arraylen(result.products), "AoT: two occurrences yield array of 2");
assertEquals("a", result.products[1].name, "AoT: first element name");
assertEquals("b", result.products[2].name, "AoT: second element name");

// AoT with sub-table: [[products]] followed by [products.color]
toml = "[[products]]" & chr(10) & 'name = "x"' & chr(10) & "[products.color]" & chr(10) & 'hex = "FF0000"';
result = parser.tomlDeserialize(toml);
assertEquals("x", result.products[1].name, "AoT+sub: products[1].name");
assertEquals("FF0000", result.products[1].color.hex, "AoT+sub: sub-table on last element");

// Multiple [[products]] each with sub-tables
toml = "[[products]]" & chr(10) & 'name = "a"' & chr(10) & "[products.color]" & chr(10) & 'hex = "11"' & chr(10) & "[[products]]" & chr(10) & 'name = "b"' & chr(10) & "[products.color]" & chr(10) & 'hex = "22"';
result = parser.tomlDeserialize(toml);
assertEquals("11", result.products[1].color.hex, "AoT+sub: first entry color");
assertEquals("22", result.products[2].color.hex, "AoT+sub: second entry color");

// [[a.b]] - nested AoT path
toml = "[[fruits.varieties]]" & chr(10) & 'name = "red"';
result = parser.tomlDeserialize(toml);
assert(isStruct(result.fruits), "AoT nested: parent struct created");
assert(isArray(result.fruits.varieties), "AoT nested: array under parent");
assertEquals("red", result.fruits.varieties[1].name, "AoT nested: value");

// [[a]] then [a] is an error
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlDeserialize("[[a]]" & chr(10) & 'x = 1' & chr(10) & "[a]" & chr(10) & 'y = 2');
}, "AoT: [[a]] then [a] throws TypeError");

// [a] then [[a]] is an error
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlDeserialize("[a]" & chr(10) & 'x = 1' & chr(10) & "[[a]]" & chr(10) & 'y = 2');
}, "AoT: [a] then [[a]] throws TypeError");

// Subsequent [[a]] after a = 1 error path
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlDeserialize('a = 1' & chr(10) & "[[a]]" & chr(10) & 'x = 1');
}, "AoT: [[a]] after a = 1 throws (a is a scalar, can't become an array)");

// Issue A: static array followed by [[a]] is a TypeError
assertThrows("cfTOML\.TypeError", function() {
	parser.tomlDeserialize("a = [1, 2, 3]" & chr(10) & "[[a]]" & chr(10) & "x = 1");
}, "AoT: static array a = [1,2,3] then [[a]] throws TypeError");

// Issue B: inlineTables cleared per AoT element - dotted key in second element doesn't see first element's inline path
result = parser.tomlDeserialize("[[aot]]" & chr(10) & "p = {x = 1}" & chr(10) & "[[aot]]" & chr(10) & "p = {y = 2}");
assertEquals(2, arraylen(result.aot), "AoT cleanup: two elements created");
assertEquals(1, result.aot[1].p.x, "AoT cleanup: first element inline preserved");
assertEquals(2, result.aot[2].p.y, "AoT cleanup: second element inline allowed (not blocked by stale inlineTables)");
</cfscript>
