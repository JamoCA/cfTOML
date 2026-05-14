<cfscript>
// Empty input
tokens = parser.tokenize("");
assertEquals(0, arraylen(tokens), "Tokenizer: empty input yields zero tokens");
</cfscript>
<cfscript>
// LF -> one NEWLINE
tokens = parser.tokenize(chr(10));
assertEquals(1, arraylen(tokens), "Tokenizer: single LF yields one token");
assertEquals("NEWLINE", tokens[1].type, "Tokenizer: LF token type is NEWLINE");

// CRLF -> one NEWLINE (not two)
tokens = parser.tokenize(chr(13) & chr(10));
assertEquals(1, arraylen(tokens), "Tokenizer: CRLF yields one token");
assertEquals("NEWLINE", tokens[1].type, "Tokenizer: CRLF token type is NEWLINE");

// Two LFs -> two NEWLINEs
tokens = parser.tokenize(chr(10) & chr(10));
assertEquals(2, arraylen(tokens), "Tokenizer: two LFs yield two tokens");
</cfscript>
<cfscript>
// Position tracking: first token at line 1, col 1
tokens = parser.tokenize(chr(10));
assertEquals(1, tokens[1].line, "Tokenizer: first newline at line 1");
assertEquals(1, tokens[1].col, "Tokenizer: first newline at col 1");

// Position tracking: second newline at line 2, col 1
tokens = parser.tokenize(chr(10) & chr(10));
assertEquals(2, tokens[2].line, "Tokenizer: second newline at line 2");
assertEquals(1, tokens[2].col, "Tokenizer: second newline at col 1");
</cfscript>
<cfscript>
// Bare comment with newline
tokens = parser.tokenize("## hello" & chr(10));
assertEquals(2, arraylen(tokens), "Tokenizer: comment + newline yields 2 tokens");
assertEquals("COMMENT", tokens[1].type, "Tokenizer: first token is COMMENT");
assertEquals("## hello", tokens[1].value, "Tokenizer: comment value includes the hash");
assertEquals("NEWLINE", tokens[2].type, "Tokenizer: trailing newline after comment");

// Comment at EOF (no trailing newline)
tokens = parser.tokenize("## at eof");
assertEquals(1, arraylen(tokens), "Tokenizer: comment-only input yields 1 token");
assertEquals("COMMENT", tokens[1].type, "Tokenizer: comment-only is COMMENT");
assertEquals("## at eof", tokens[1].value, "Tokenizer: EOF comment value preserved");
</cfscript>

<cfscript>
// Bare key only
tokens = parser.tokenize("foo");
assertEquals(1, arraylen(tokens), "Tokenizer: bare key yields 1 token");
assertEquals("KEY", tokens[1].type, "Tokenizer: bare key type is KEY");
assertEquals("foo", tokens[1].value, "Tokenizer: bare key value is the identifier");

// Bare key with digits, underscores, hyphens
tokens = parser.tokenize("my-key_2");
assertEquals(1, arraylen(tokens), "Tokenizer: my-key_2 yields 1 token");
assertEquals("KEY", tokens[1].type, "Tokenizer: my-key_2 type is KEY");
assertEquals("my-key_2", tokens[1].value, "Tokenizer: my-key_2 preserves dashes/underscores/digits");
</cfscript>
<cfscript>
// Dotted key segments
tokens = parser.tokenize("a.b");
assertEquals(3, arraylen(tokens), "Tokenizer: a.b yields 3 tokens");
assertEquals("KEY", tokens[1].type, "Tokenizer: a.b first is KEY");
assertEquals("a", tokens[1].value, "Tokenizer: a.b first value is 'a'");
assertEquals("DOT", tokens[2].type, "Tokenizer: a.b middle is DOT");
assertEquals("KEY", tokens[3].type, "Tokenizer: a.b last is KEY");
assertEquals("b", tokens[3].value, "Tokenizer: a.b last value is 'b'");

// EQUALS
tokens = parser.tokenize("=");
assertEquals(1, arraylen(tokens), "Tokenizer: = yields 1 token");
assertEquals("EQUALS", tokens[1].type, "Tokenizer: = type is EQUALS");
</cfscript>
<cfscript>
// BOOL true
tokens = parser.tokenize("true");
assertEquals(1, arraylen(tokens), "Tokenizer: true yields 1 token");
assertEquals("BOOL", tokens[1].type, "Tokenizer: true type is BOOL");
assertEquals("true", tokens[1].value, "Tokenizer: true value is 'true'");

// BOOL false
tokens = parser.tokenize("false");
assertEquals("BOOL", tokens[1].type, "Tokenizer: false type is BOOL");
assertEquals("false", tokens[1].value, "Tokenizer: false value is 'false'");

// Word boundary: 'truely' is KEY, not BOOL
tokens = parser.tokenize("truely");
assertEquals("KEY", tokens[1].type, "Tokenizer: 'truely' is KEY not BOOL");
assertEquals("truely", tokens[1].value, "Tokenizer: 'truely' value preserved");
</cfscript>
<cfscript>
// Simple decimal
tokens = parser.tokenize("42");
assertEquals(1, arraylen(tokens), "Tokenizer: 42 yields 1 token");
assertEquals("INT", tokens[1].type, "Tokenizer: 42 type is INT");
assertEquals("42", tokens[1].value, "Tokenizer: 42 value preserved");

// Negative
tokens = parser.tokenize("-7");
assertEquals("INT", tokens[1].type, "Tokenizer: -7 type is INT");
assertEquals("-7", tokens[1].value, "Tokenizer: -7 value preserved");

// Positive sign
tokens = parser.tokenize("+99");
assertEquals("INT", tokens[1].type, "Tokenizer: +99 type is INT");
assertEquals("+99", tokens[1].value, "Tokenizer: +99 value preserved");

// Underscores
tokens = parser.tokenize("1_000_000");
assertEquals("INT", tokens[1].type, "Tokenizer: 1_000_000 type is INT");
assertEquals("1_000_000", tokens[1].value, "Tokenizer: underscores preserved");

// Zero
tokens = parser.tokenize("0");
assertEquals("INT", tokens[1].type, "Tokenizer: 0 type is INT");
</cfscript>
<cfscript>
// Simple string
tokens = parser.tokenize('"hello"');
assertEquals(1, arraylen(tokens), "Tokenizer: basic string yields 1 token");
assertEquals("STRING_BASIC", tokens[1].type, "Tokenizer: basic string type");
assertEquals("hello", tokens[1].value, "Tokenizer: basic string value excludes quotes");

// Empty string
tokens = parser.tokenize('""');
assertEquals(1, arraylen(tokens), "Tokenizer: empty basic string yields 1 token");
assertEquals("STRING_BASIC", tokens[1].type, "Tokenizer: empty basic string type");
assertEquals("", tokens[1].value, "Tokenizer: empty basic string has empty value");

// String with escaped quote (raw passthrough)
tokens = parser.tokenize('"a\"b"');
assertEquals(1, arraylen(tokens), "Tokenizer: escaped quote yields 1 token");
assertEquals("STRING_BASIC", tokens[1].type, "Tokenizer: escaped quote type");
assertEquals('a\"b', tokens[1].value, "Tokenizer: escape sequences preserved raw");

// String with embedded backslash
tokens = parser.tokenize('"a\\b"');
assertEquals('a\\b', tokens[1].value, "Tokenizer: double backslash preserved raw");
</cfscript>

<cfscript>
// Unterminated string throws
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize('"hello');
}, "Tokenizer: unterminated basic string throws ParseError");

// String spanning a newline throws
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize('"line1' & chr(10) & 'line2"');
}, "Tokenizer: basic string cannot span newline");
</cfscript>
<cfscript>
// Whitespace between tokens
tokens = parser.tokenize("foo = 1");
assertEquals(3, arraylen(tokens), "Tokenizer: 'foo = 1' yields 3 tokens (KEY, EQUALS, INT)");
assertEquals("KEY", tokens[1].type, "Tokenizer: foo=1 first is KEY");
assertEquals("EQUALS", tokens[2].type, "Tokenizer: foo=1 second is EQUALS");
assertEquals("INT", tokens[3].type, "Tokenizer: foo=1 third is INT");
assertEquals("1", tokens[3].value, "Tokenizer: foo=1 INT value preserved");

// Tabs as whitespace
tokens = parser.tokenize("foo" & chr(9) & "=" & chr(9) & "1");
assertEquals(3, arraylen(tokens), "Tokenizer: tab-separated yields 3 tokens");
</cfscript>
<cfscript>
// Realistic key/value with string (4 tokens: KEY EQUALS STRING_BASIC NEWLINE)
tokens = parser.tokenize('title = "TOML Example"' & chr(10));
assertEquals(4, arraylen(tokens), "Tokenizer: KV line yields 4 tokens (KEY EQUALS STRING NEWLINE)");
assertEquals("KEY", tokens[1].type, "Tokenizer: KV first is KEY");
assertEquals("title", tokens[1].value, "Tokenizer: KV key is 'title'");
assertEquals("EQUALS", tokens[2].type, "Tokenizer: KV second is EQUALS");
assertEquals("STRING_BASIC", tokens[3].type, "Tokenizer: KV third is STRING_BASIC");
assertEquals("TOML Example", tokens[3].value, "Tokenizer: KV string value preserved");
assertEquals("NEWLINE", tokens[4].type, "Tokenizer: KV fourth is NEWLINE");

// KV with integer
tokens = parser.tokenize('port = 8080' & chr(10));
assertEquals(4, arraylen(tokens), "Tokenizer: port=8080 yields 4 tokens");
assertEquals("INT", tokens[3].type, "Tokenizer: port value is INT");
assertEquals("8080", tokens[3].value, "Tokenizer: port value preserved");

// KV with boolean
tokens = parser.tokenize('enabled = true' & chr(10));
assertEquals("BOOL", tokens[3].type, "Tokenizer: enabled value is BOOL");
assertEquals("true", tokens[3].value, "Tokenizer: enabled value preserved");

// Comment and KV line
tokens = parser.tokenize("## a comment" & chr(10) & "a = 1" & chr(10));
assertEquals(6, arraylen(tokens), "Tokenizer: comment + KV yields 6 tokens");
assertEquals("COMMENT", tokens[1].type, "Tokenizer: comment first");
assertEquals("NEWLINE", tokens[2].type, "Tokenizer: newline after comment");
assertEquals("KEY", tokens[3].type, "Tokenizer: KEY after comment");
</cfscript>
<cfscript>
// Simple hex
tokens = parser.tokenize("0xDEADBEEF");
assertEquals(1, arraylen(tokens), "Tokenizer: hex INT yields 1 token");
assertEquals("INT", tokens[1].type, "Tokenizer: hex INT type is INT");
assertEquals("0xDEADBEEF", tokens[1].value, "Tokenizer: hex INT value preserves 0x prefix and case");

// Lowercase hex
tokens = parser.tokenize("0xabc123");
assertEquals("0xabc123", tokens[1].value, "Tokenizer: lowercase hex digits preserved");

// Mixed case
tokens = parser.tokenize("0xDeadBeef");
assertEquals("0xDeadBeef", tokens[1].value, "Tokenizer: mixed-case hex preserved");

// Underscores between digits
tokens = parser.tokenize("0xDEAD_BEEF");
assertEquals("0xDEAD_BEEF", tokens[1].value, "Tokenizer: underscores in hex preserved");

// Zero hex
tokens = parser.tokenize("0x0");
assertEquals("0x0", tokens[1].value, "Tokenizer: 0x0 preserved");
</cfscript>
<cfscript>
// Simple octal
tokens = parser.tokenize("0o755");
assertEquals(1, arraylen(tokens), "Tokenizer: octal INT yields 1 token");
assertEquals("INT", tokens[1].type, "Tokenizer: octal INT type is INT");
assertEquals("0o755", tokens[1].value, "Tokenizer: octal INT value preserved");

// Underscores between octal digits
tokens = parser.tokenize("0o7_5_5");
assertEquals("0o7_5_5", tokens[1].value, "Tokenizer: underscores in octal preserved");

// Zero octal
tokens = parser.tokenize("0o0");
assertEquals("0o0", tokens[1].value, "Tokenizer: 0o0 preserved");
</cfscript>
<cfscript>
// Simple binary
tokens = parser.tokenize("0b101010");
assertEquals(1, arraylen(tokens), "Tokenizer: binary INT yields 1 token");
assertEquals("INT", tokens[1].type, "Tokenizer: binary INT type is INT");
assertEquals("0b101010", tokens[1].value, "Tokenizer: binary INT value preserved");

// Underscores between binary digits
tokens = parser.tokenize("0b1010_1010");
assertEquals("0b1010_1010", tokens[1].value, "Tokenizer: underscores in binary preserved");

// Zero binary
tokens = parser.tokenize("0b0");
assertEquals("0b0", tokens[1].value, "Tokenizer: 0b0 preserved");
</cfscript>
<cfscript>
// Simple literal string
tokens = parser.tokenize("'hello'");
assertEquals(1, arraylen(tokens), "Tokenizer: literal string yields 1 token");
assertEquals("STRING_LITERAL", tokens[1].type, "Tokenizer: literal string type");
assertEquals("hello", tokens[1].value, "Tokenizer: literal string value excludes quotes");

// Empty literal string
tokens = parser.tokenize("''");
assertEquals(1, arraylen(tokens), "Tokenizer: empty literal string yields 1 token");
assertEquals("", tokens[1].value, "Tokenizer: empty literal string has empty value");

// Backslashes are LITERAL (not escape characters) in literal strings
tokens = parser.tokenize("'C:\winpath'");
assertEquals("C:\winpath", tokens[1].value, "Tokenizer: backslashes in literal string are literal");

// Embedded double-quote is fine in a literal string
tokens = parser.tokenize("'say " & chr(34) & "hi" & chr(34) & "'");
assertEquals('say "hi"', tokens[1].value, "Tokenizer: literal string preserves embedded double-quote");

// Unterminated literal string throws
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize("'hello");
}, "Tokenizer: unterminated literal string throws ParseError");

// Newline in literal string throws
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize("'line1" & chr(10) & "line2'");
}, "Tokenizer: literal string cannot span newline");
</cfscript>
<cfscript>
// Triple-quote opens and closes
tokens = parser.tokenize('"""hello"""');
assertEquals(1, arraylen(tokens), "Tokenizer: ML basic string yields 1 token");
assertEquals("STRING_ML_BASIC", tokens[1].type, "Tokenizer: ML basic string type");
assertEquals("hello", tokens[1].value, "Tokenizer: ML basic string content");

// First newline after opening triple-quote is trimmed
tokens = parser.tokenize('"""' & chr(10) & 'hello"""');
assertEquals("hello", tokens[1].value, "Tokenizer: leading newline after opening is trimmed");

// CRLF after opening triple-quote is trimmed
tokens = parser.tokenize('"""' & chr(13) & chr(10) & 'hello"""');
assertEquals("hello", tokens[1].value, "Tokenizer: leading CRLF after opening is trimmed");

// Embedded newlines preserved
tokens = parser.tokenize('"""line1' & chr(10) & 'line2"""');
assertEquals("line1" & chr(10) & "line2", tokens[1].value, "Tokenizer: embedded newlines preserved");

// Single embedded double-quote is fine
tokens = parser.tokenize('"""say "hi" please"""');
assertEquals('say "hi" please', tokens[1].value, "Tokenizer: single embedded double-quote preserved");

// Empty ML basic string
tokens = parser.tokenize('""""""');
assertEquals("", tokens[1].value, "Tokenizer: empty ML basic string");

// Unterminated ML basic string
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize('"""hello');
}, "Tokenizer: unterminated ML basic string throws");
</cfscript>
<cfscript>
// Triple-quote literal opens and closes
tokens = parser.tokenize("'''hello'''");
assertEquals(1, arraylen(tokens), "Tokenizer: ML literal string yields 1 token");
assertEquals("STRING_ML_LITERAL", tokens[1].type, "Tokenizer: ML literal string type");
assertEquals("hello", tokens[1].value, "Tokenizer: ML literal string content");

// First newline after opening trimmed
tokens = parser.tokenize("'''" & chr(10) & "hello'''");
assertEquals("hello", tokens[1].value, "Tokenizer: leading newline after opening trimmed");

// Backslashes are literal in ML literal
tokens = parser.tokenize("'''C:\winpath\file'''");
assertEquals("C:\winpath\file", tokens[1].value, "Tokenizer: ML literal preserves backslashes");

// Embedded newlines preserved
tokens = parser.tokenize("'''line1" & chr(10) & "line2'''");
assertEquals("line1" & chr(10) & "line2", tokens[1].value, "Tokenizer: ML literal embedded newlines");

// Unterminated
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize("'''hello");
}, "Tokenizer: unterminated ML literal throws");
</cfscript>
<cfscript>
// Simple float
tokens = parser.tokenize("1.5");
assertEquals(1, arraylen(tokens), "Tokenizer: 1.5 yields 1 token");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: 1.5 type is FLOAT");
assertEquals("1.5", tokens[1].value, "Tokenizer: 1.5 value preserved");

// Negative float
tokens = parser.tokenize("-0.001");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: -0.001 type is FLOAT");
assertEquals("-0.001", tokens[1].value, "Tokenizer: -0.001 value preserved");

// Float with underscores
tokens = parser.tokenize("3.14_159");
assertEquals("3.14_159", tokens[1].value, "Tokenizer: float with underscores preserved");

// Float followed by newline
tokens = parser.tokenize("1.5" & chr(10));
assertEquals(2, arraylen(tokens), "Tokenizer: 1.5 then newline yields 2 tokens");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: 1.5 is FLOAT before newline");

// Still INT, not FLOAT, when no fraction follows
tokens = parser.tokenize("42");
assertEquals("INT", tokens[1].type, "Tokenizer: 42 still INT after FLOAT branch added");
assertEquals("42", tokens[1].value, "Tokenizer: 42 value preserved");

// 1.abc (digit then dot then non-digit) is NOT a float - falls through to INT DOT KEY
tokens = parser.tokenize("1.abc");
assertEquals(3, arraylen(tokens), "Tokenizer: 1.abc yields INT DOT KEY (3 tokens)");
assertEquals("INT", tokens[1].type, "Tokenizer: 1.abc first is INT");
assertEquals("DOT", tokens[2].type, "Tokenizer: 1.abc second is DOT");
assertEquals("KEY", tokens[3].type, "Tokenizer: 1.abc third is KEY");
</cfscript>
<cfscript>
// Float with exponent only
tokens = parser.tokenize("1e10");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: 1e10 is FLOAT");
assertEquals("1e10", tokens[1].value, "Tokenizer: 1e10 value preserved");

// Float with fraction and exponent
tokens = parser.tokenize("1.5e+3");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: 1.5e+3 is FLOAT");
assertEquals("1.5e+3", tokens[1].value, "Tokenizer: 1.5e+3 value preserved");

// Uppercase E
tokens = parser.tokenize("2E-5");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: 2E-5 is FLOAT");
assertEquals("2E-5", tokens[1].value, "Tokenizer: 2E-5 value preserved");

// Float with underscores in exponent
tokens = parser.tokenize("1e1_0");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: 1e1_0 is FLOAT");
assertEquals("1e1_0", tokens[1].value, "Tokenizer: 1e1_0 value preserved");
</cfscript>
<cfscript>
// Plain inf
tokens = parser.tokenize("inf");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: inf type is FLOAT");
assertEquals("inf", tokens[1].value, "Tokenizer: inf value");

// +inf and -inf
tokens = parser.tokenize("+inf");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: +inf type is FLOAT");
assertEquals("+inf", tokens[1].value, "Tokenizer: +inf value");
tokens = parser.tokenize("-inf");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: -inf type is FLOAT");

// nan / +nan / -nan
tokens = parser.tokenize("nan");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: nan type is FLOAT");
tokens = parser.tokenize("+nan");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: +nan type is FLOAT");
tokens = parser.tokenize("-nan");
assertEquals("FLOAT", tokens[1].type, "Tokenizer: -nan type is FLOAT");

// Word boundary: 'infinity' is KEY, not FLOAT
tokens = parser.tokenize("infinity");
assertEquals("KEY", tokens[1].type, "Tokenizer: 'infinity' is KEY not FLOAT");
assertEquals("infinity", tokens[1].value, "Tokenizer: 'infinity' value preserved");
</cfscript>
<cfscript>
// Local date
tokens = parser.tokenize("1979-05-27");
assertEquals(1, arraylen(tokens), "Tokenizer: date yields 1 token");
assertEquals("DATE_LOCAL", tokens[1].type, "Tokenizer: date type");
assertEquals("1979-05-27", tokens[1].value, "Tokenizer: date value preserved");

// Date followed by newline
tokens = parser.tokenize("1979-05-27" & chr(10));
assertEquals(2, arraylen(tokens), "Tokenizer: date + newline yields 2 tokens");
assertEquals("DATE_LOCAL", tokens[1].type, "Tokenizer: date type before newline");

// INT still works for non-date digit runs
tokens = parser.tokenize("1979");
assertEquals("INT", tokens[1].type, "Tokenizer: 4 digits without hyphen is INT");
</cfscript>
<cfscript>
// Local time without fraction
tokens = parser.tokenize("07:32:00");
assertEquals(1, arraylen(tokens), "Tokenizer: time yields 1 token");
assertEquals("TIME_LOCAL", tokens[1].type, "Tokenizer: time type");
assertEquals("07:32:00", tokens[1].value, "Tokenizer: time value preserved");

// Local time with fraction
tokens = parser.tokenize("07:32:00.123");
assertEquals("TIME_LOCAL", tokens[1].type, "Tokenizer: time with fraction type");
assertEquals("07:32:00.123", tokens[1].value, "Tokenizer: time with fraction value preserved");

// Long fractional seconds
tokens = parser.tokenize("07:32:00.123456789");
assertEquals("07:32:00.123456789", tokens[1].value, "Tokenizer: long fractional seconds preserved");
</cfscript>
<cfscript>
// Datetime with T separator
tokens = parser.tokenize("1979-05-27T07:32:00");
assertEquals(1, arraylen(tokens), "Tokenizer: datetime yields 1 token");
assertEquals("DATETIME_LOCAL", tokens[1].type, "Tokenizer: datetime type");
assertEquals("1979-05-27T07:32:00", tokens[1].value, "Tokenizer: datetime value preserved");

// Lowercase t separator
tokens = parser.tokenize("1979-05-27t07:32:00");
assertEquals("DATETIME_LOCAL", tokens[1].type, "Tokenizer: lowercase-t datetime type");

// Space separator
tokens = parser.tokenize("1979-05-27 07:32:00");
assertEquals("DATETIME_LOCAL", tokens[1].type, "Tokenizer: space-separator datetime type");

// With fractional seconds
tokens = parser.tokenize("1979-05-27T07:32:00.999");
assertEquals("DATETIME_LOCAL", tokens[1].type, "Tokenizer: fractional datetime type");
assertEquals("1979-05-27T07:32:00.999", tokens[1].value, "Tokenizer: fractional datetime value");
</cfscript>
<cfscript>
// With Z (UTC)
tokens = parser.tokenize("1979-05-27T07:32:00Z");
assertEquals(1, arraylen(tokens), "Tokenizer: offset datetime yields 1 token");
assertEquals("DATETIME_OFFSET", tokens[1].type, "Tokenizer: Z offset datetime type");
assertEquals("1979-05-27T07:32:00Z", tokens[1].value, "Tokenizer: Z offset datetime value");

// Lowercase z
tokens = parser.tokenize("1979-05-27T07:32:00z");
assertEquals("DATETIME_OFFSET", tokens[1].type, "Tokenizer: lowercase-z offset datetime type");

// Positive offset
tokens = parser.tokenize("1979-05-27T07:32:00+04:30");
assertEquals("DATETIME_OFFSET", tokens[1].type, "Tokenizer: +HH:MM offset datetime type");
assertEquals("1979-05-27T07:32:00+04:30", tokens[1].value, "Tokenizer: +HH:MM offset value");

// Negative offset
tokens = parser.tokenize("1979-05-27T07:32:00-08:00");
assertEquals("DATETIME_OFFSET", tokens[1].type, "Tokenizer: -HH:MM offset datetime type");
assertEquals("1979-05-27T07:32:00-08:00", tokens[1].value, "Tokenizer: -HH:MM offset value");

// With fractional seconds and offset
tokens = parser.tokenize("1979-05-27T07:32:00.999-08:00");
assertEquals("1979-05-27T07:32:00.999-08:00", tokens[1].value, "Tokenizer: fractional + offset preserved");
</cfscript>
<cfscript>
// A pyproject-style line set: 3 KV lines
tokens = parser.tokenize('title = "TOML Example"' & chr(10) & 'version = 1.0' & chr(10) & 'released = 2024-01-15T10:30:00Z' & chr(10));
// Should produce: KEY EQUALS STRING_BASIC NEWLINE KEY EQUALS FLOAT NEWLINE KEY EQUALS DATETIME_OFFSET NEWLINE = 12 tokens
assertEquals(12, arraylen(tokens), "Integration: 3-line config yields 12 tokens");
assertEquals("KEY", tokens[1].type, "Integration: title is KEY");
assertEquals("STRING_BASIC", tokens[3].type, "Integration: title value is STRING_BASIC");
assertEquals("KEY", tokens[5].type, "Integration: version is KEY");
assertEquals("FLOAT", tokens[7].type, "Integration: version value is FLOAT");
assertEquals("1.0", tokens[7].value, "Integration: version value preserved");
assertEquals("KEY", tokens[9].type, "Integration: released is KEY");
assertEquals("DATETIME_OFFSET", tokens[11].type, "Integration: released value is DATETIME_OFFSET");
assertEquals("2024-01-15T10:30:00Z", tokens[11].value, "Integration: datetime value preserved");

// Mixed types: hex number, literal string with backslash
tokens = parser.tokenize('color = 0xFF8800' & chr(10) & "name = 'C:\path' " & chr(10));
assertEquals("INT", tokens[3].type, "Integration: color value is INT");
assertEquals("0xFF8800", tokens[3].value, "Integration: hex value preserved");
assertEquals("STRING_LITERAL", tokens[7].type, "Integration: name value is STRING_LITERAL");
assertEquals("C:\path", tokens[7].value, "Integration: literal string backslash preserved");

// Special floats in a config-like form
tokens = parser.tokenize("limit = inf" & chr(10) & "rate = nan" & chr(10));
assertEquals("FLOAT", tokens[3].type, "Integration: limit value is FLOAT");
assertEquals("inf", tokens[3].value, "Integration: inf value");
assertEquals("FLOAT", tokens[7].type, "Integration: rate value is FLOAT");
assertEquals("nan", tokens[7].value, "Integration: nan value");
</cfscript>
<cfscript>
// ML basic: 4 trailing quotes = content has 1 trailing quote
tokens = parser.tokenize('"""abc""""');
assertEquals(1, arraylen(tokens), "Tokenizer: ML basic with 4 trailing quotes yields 1 token");
assertEquals("STRING_ML_BASIC", tokens[1].type, "Tokenizer: 4 trailing quotes type");
assertEquals('abc"', tokens[1].value, "Tokenizer: 4 trailing quotes content has 1 quote");

// ML basic: 5 trailing quotes = content has 2 trailing quotes
tokens = parser.tokenize('"""abc"""""');
assertEquals(1, arraylen(tokens), "Tokenizer: ML basic with 5 trailing quotes yields 1 token");
assertEquals('abc""', tokens[1].value, "Tokenizer: 5 trailing quotes content has 2 quotes");

// ML literal: 4 trailing single-quotes
tokens = parser.tokenize("'''abc''''");
assertEquals("STRING_ML_LITERAL", tokens[1].type, "Tokenizer: ML literal with 4 trailing quotes type");
assertEquals("abc'", tokens[1].value, "Tokenizer: 4 trailing literal quotes content");

// ML literal: 5 trailing single-quotes
tokens = parser.tokenize("'''abc'''''");
assertEquals("abc''", tokens[1].value, "Tokenizer: 5 trailing literal quotes content");
</cfscript>
<cfscript>
// Bare table header
tokens = parser.tokenize("[server]" & chr(10));
assertEquals(2, arraylen(tokens), "Tokenizer: [server] + newline yields 2 tokens");
assertEquals("TABLE_HEADER", tokens[1].type, "Tokenizer: TABLE_HEADER type");
assertEquals("server", tokens[1].value, "Tokenizer: TABLE_HEADER value is path without brackets");

// Dotted table header
tokens = parser.tokenize("[server.alpha.config]" & chr(10));
assertEquals("TABLE_HEADER", tokens[1].type, "Tokenizer: dotted TABLE_HEADER type");
assertEquals("server.alpha.config", tokens[1].value, "Tokenizer: dotted TABLE_HEADER value");

// Quoted segment in header
tokens = parser.tokenize('["my server"]' & chr(10));
assertEquals("TABLE_HEADER", tokens[1].type, "Tokenizer: quoted-segment header type");
assertEquals('"my server"', tokens[1].value, "Tokenizer: quoted-segment header preserves quotes in value");

// Whitespace inside brackets
tokens = parser.tokenize("[a . b]" & chr(10));
assertEquals("TABLE_HEADER", tokens[1].type, "Tokenizer: spaced header type");
assertEquals("a . b", tokens[1].value, "Tokenizer: header preserves internal whitespace");

// Header at start of file (no preceding newline) works
tokens = parser.tokenize("[root]");
assertEquals(1, arraylen(tokens), "Tokenizer: header at file start yields 1 token");
assertEquals("TABLE_HEADER", tokens[1].type, "Tokenizer: header-at-start type");

// Unterminated header throws
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize("[server");
}, "Tokenizer: unterminated TABLE_HEADER throws");
</cfscript>
<cfscript>
// Bare array-of-tables header
tokens = parser.tokenize("[[products]]" & chr(10));
assertEquals(2, arraylen(tokens), "Tokenizer: [[products]] + newline yields 2 tokens");
assertEquals("ARRAY_TABLE_HEADER", tokens[1].type, "Tokenizer: ARRAY_TABLE_HEADER type");
assertEquals("products", tokens[1].value, "Tokenizer: ARRAY_TABLE_HEADER value is path without brackets");

// Dotted array-of-tables header
tokens = parser.tokenize("[[fruits.varieties]]" & chr(10));
assertEquals("ARRAY_TABLE_HEADER", tokens[1].type, "Tokenizer: dotted ARRAY_TABLE_HEADER type");
assertEquals("fruits.varieties", tokens[1].value, "Tokenizer: dotted ARRAY_TABLE_HEADER value");

// Unterminated array header throws
assertThrows("cfTOML\.ParseError", function() {
	parser.tokenize("[[products]");
}, "Tokenizer: unterminated ARRAY_TABLE_HEADER throws");

// Distinguish from TABLE_HEADER: [single] vs [[double]]
tokens = parser.tokenize("[a]" & chr(10) & "[[b]]" & chr(10));
assertEquals("TABLE_HEADER", tokens[1].type, "Tokenizer: [a] is TABLE_HEADER");
assertEquals("ARRAY_TABLE_HEADER", tokens[3].type, "Tokenizer: [[b]] is ARRAY_TABLE_HEADER");
</cfscript>
<cfscript>
// Empty array: x = []
tokens = parser.tokenize("x = []");
assertEquals(4, arraylen(tokens), "Tokenizer: x = [] yields 4 tokens KEY EQUALS ARRAY_OPEN ARRAY_CLOSE");
assertEquals("KEY", tokens[1].type, "Tokenizer: x is KEY");
assertEquals("EQUALS", tokens[2].type, "Tokenizer: = is EQUALS");
assertEquals("ARRAY_OPEN", tokens[3].type, "Tokenizer: [ after = is ARRAY_OPEN");
assertEquals("[", tokens[3].value, "Tokenizer: ARRAY_OPEN value is literal [");
assertEquals("ARRAY_CLOSE", tokens[4].type, "Tokenizer: ] is ARRAY_CLOSE");
assertEquals("]", tokens[4].value, "Tokenizer: ARRAY_CLOSE value is literal ]");

// Single-element array: x = [1]
tokens = parser.tokenize("x = [1]");
assertEquals(5, arraylen(tokens), "Tokenizer: x = [1] yields 5 tokens");
assertEquals("ARRAY_OPEN", tokens[3].type, "Tokenizer: single-elem ARRAY_OPEN");
assertEquals("INT", tokens[4].type, "Tokenizer: single-elem INT inside array");
assertEquals("ARRAY_CLOSE", tokens[5].type, "Tokenizer: single-elem ARRAY_CLOSE");

// [ at line-start with depth 0 stays TABLE_HEADER (regression)
tokens = parser.tokenize("[server]");
assertEquals("TABLE_HEADER", tokens[1].type, "Tokenizer: [server] at line-start depth 0 still TABLE_HEADER");

// Nested array: x = [[1]]
tokens = parser.tokenize("x = [[1]]");
assertEquals("ARRAY_OPEN", tokens[3].type, "Tokenizer: outer [ is ARRAY_OPEN");
assertEquals("ARRAY_OPEN", tokens[4].type, "Tokenizer: inner [ is ARRAY_OPEN, depth tracking works");

// [ at line-start INSIDE an open array becomes ARRAY_OPEN
// arr = [\n[1]\n] - the inner [ is at line-start with depth=1, should be ARRAY_OPEN
tokens = parser.tokenize("arr = [" & chr(10) & "[1]" & chr(10) & "]");
innerOpenIdx = 0;
for (idx = 1; idx lte arraylen(tokens); idx++) {
	if (idx gt 3 && tokens[idx].type eq "ARRAY_OPEN") {
		innerOpenIdx = idx;
		break;
	}
}
assert(innerOpenIdx gt 0, "Tokenizer: inner ARRAY_OPEN at line-start with depth>0 found");
</cfscript>
<cfscript>
// Array with commas: x = [1,2,3]
tokens = parser.tokenize("x = [1,2,3]");
// Expected: KEY EQUALS ARRAY_OPEN INT COMMA INT COMMA INT ARRAY_CLOSE = 9 tokens
assertEquals(9, arraylen(tokens), "Tokenizer: x = [1,2,3] yields 9 tokens");
assertEquals("COMMA", tokens[5].type, "Tokenizer: first comma is COMMA");
assertEquals(",", tokens[5].value, "Tokenizer: COMMA value is literal comma");
assertEquals("COMMA", tokens[7].type, "Tokenizer: second comma is COMMA");

// Array with spaces and commas: x = [1, 2, 3]
tokens = parser.tokenize("x = [1, 2, 3]");
assertEquals(9, arraylen(tokens), "Tokenizer: spaced array yields 9 tokens (whitespace skipped)");
</cfscript>
<cfscript>
// Simple inline table tokens: x = {y = 1}
tokens = parser.tokenize("x = {y = 1}");
// Expected: KEY EQUALS INLINE_OPEN KEY EQUALS INT INLINE_CLOSE = 7 tokens
assertEquals(7, arraylen(tokens), "Tokenizer: x = {y = 1} yields 7 tokens");
assertEquals("INLINE_OPEN", tokens[3].type, "Tokenizer: { is INLINE_OPEN");
assertEquals("{", tokens[3].value, "Tokenizer: INLINE_OPEN value");
assertEquals("INLINE_CLOSE", tokens[7].type, "Tokenizer: } is INLINE_CLOSE");
assertEquals("}", tokens[7].value, "Tokenizer: INLINE_CLOSE value");

// Empty inline table: x = {}
tokens = parser.tokenize("x = {}");
assertEquals(4, arraylen(tokens), "Tokenizer: x = {} yields 4 tokens");
assertEquals("INLINE_OPEN", tokens[3].type, "Tokenizer: empty inline {");
assertEquals("INLINE_CLOSE", tokens[4].type, "Tokenizer: empty inline }");
</cfscript>
