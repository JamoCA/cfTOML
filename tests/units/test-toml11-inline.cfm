<cfscript>
toml = new cfTOML.cfTOML();

// 1.1.0: newlines inside { } accepted
src = 'contact = {' & chr(10) &
      '    name = "Donald Duck",' & chr(10) &
      '    email = "donald@duckburg.com"' & chr(10) &
      '}';
result = toml.tomlDeserialize(src, ["spec": "1.1.0"]);
assertEquals("Donald Duck", result.contact.name, "Toml11Inline: multi-line name");
assertEquals("donald@duckburg.com", result.contact.email, "Toml11Inline: multi-line email");

// 1.1.0: trailing comma before close brace accepted
src = 'c = {' & chr(10) &
      '    a = 1,' & chr(10) &
      '    b = 2,' & chr(10) &
      '}';
result = toml.tomlDeserialize(src, ["spec": "1.1.0"]);
assertEquals(1, result.c.a, "Toml11Inline: trailing comma a");
assertEquals(2, result.c.b, "Toml11Inline: trailing comma b");

// 1.1.0: comments inside { } accepted
src = 'c = {' & chr(10) &
      '    ##  a comment' & chr(10) &
      '    a = 1' & chr(10) &
      '}';
result = toml.tomlDeserialize(src, ["spec": "1.1.0"]);
assertEquals(1, result.c.a, "Toml11Inline: comment inside inline table");

// 1.1.0: single-line inline table (regression - both forms work)
result = toml.tomlDeserialize('c = { a = 1, b = 2 }', ["spec": "1.1.0"]);
assertEquals(1, result.c.a, "Toml11Inline: 1.1.0 single-line a");
assertEquals(2, result.c.b, "Toml11Inline: 1.1.0 single-line b");

// 1.0.0: newline inside { } throws
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	src = 'c = {' & chr(10) & 'a = 1' & chr(10) & '}';
	t.tomlDeserialize(src, ["spec": "1.0.0"]);
}, "Toml11Inline: 1.0.0 rejects newline inside inline table");

// 1.0.0: trailing comma still throws
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlDeserialize('c = { a = 1, }', ["spec": "1.0.0"]);
}, "Toml11Inline: 1.0.0 rejects trailing comma");
</cfscript>
