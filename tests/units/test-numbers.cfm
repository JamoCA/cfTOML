<cfscript>
// Plain decimal
assertEquals(42, parser.parseIntegerLexeme("42", "double", javacast("boolean", 1)), "Numbers: 42 decimal");
assertEquals(-7, parser.parseIntegerLexeme("-7", "double", javacast("boolean", 1)), "Numbers: -7 decimal");
assertEquals(0, parser.parseIntegerLexeme("0", "double", javacast("boolean", 1)), "Numbers: zero");

// Underscores stripped
assertEquals(1000000, parser.parseIntegerLexeme("1_000_000", "double", javacast("boolean", 1)), "Numbers: underscores stripped");

// Hex
assertEquals(255, parser.parseIntegerLexeme("0xFF", "double", javacast("boolean", 1)), "Numbers: 0xFF -> 255");
assertEquals(255, parser.parseIntegerLexeme("0xff", "double", javacast("boolean", 1)), "Numbers: lowercase hex");
assertEquals(3735928559, parser.parseIntegerLexeme("0xDEADBEEF", "double", javacast("boolean", 1)), "Numbers: 0xDEADBEEF");

// Octal
assertEquals(493, parser.parseIntegerLexeme("0o755", "double", javacast("boolean", 1)), "Numbers: 0o755 -> 493");

// Binary
assertEquals(42, parser.parseIntegerLexeme("0b101010", "double", javacast("boolean", 1)), "Numbers: 0b101010 -> 42");

// Strict-mode underscore violations
assertThrows("cfTOML\.ParseError", function() {
	parser.parseIntegerLexeme("1__2", "double", javacast("boolean", 1));
}, "Numbers: double underscore rejected in strict mode");
assertThrows("cfTOML\.ParseError", function() {
	parser.parseIntegerLexeme("1_", "double", javacast("boolean", 1));
}, "Numbers: trailing underscore rejected in strict mode");
assertThrows("cfTOML\.ParseError", function() {
	parser.parseIntegerLexeme("_1", "double", javacast("boolean", 1));
}, "Numbers: leading underscore rejected in strict mode");

// Non-strict mode allows them
assertEquals(12, parser.parseIntegerLexeme("1__2", "double", javacast("boolean", 0)), "Numbers: non-strict accepts double underscore");

// javalong mode returns Java Long
assertEquals("java.lang.Long", parser.parseIntegerLexeme("42", "javalong", javacast("boolean", 1)).getClass().getName(), "Numbers: javalong mode returns java.lang.Long");

// string mode returns the normalized digits as a string (decimal)
assertEquals("255", parser.parseIntegerLexeme("0xFF", "string", javacast("boolean", 1)), "Numbers: string mode returns decimal string");
</cfscript>
