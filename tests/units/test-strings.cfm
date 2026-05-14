<cfscript>
// No escapes - identity
assertEquals("hello", parser.decodeBasicStringEscapes("hello"), "Strings: no-escape identity");

// Named escapes
assertEquals(chr(10), parser.decodeBasicStringEscapes("\n"), "Strings: \n -> LF");
assertEquals(chr(9), parser.decodeBasicStringEscapes("\t"), "Strings: \t -> TAB");
assertEquals(chr(13), parser.decodeBasicStringEscapes("\r"), "Strings: \r -> CR");
assertEquals(chr(8), parser.decodeBasicStringEscapes("\b"), "Strings: \b -> BS");
assertEquals(chr(12), parser.decodeBasicStringEscapes("\f"), "Strings: \f -> FF");
assertEquals('"', parser.decodeBasicStringEscapes('\"'), "Strings: backslash-quote -> quote");
assertEquals("\", parser.decodeBasicStringEscapes("\\"), "Strings: double-backslash -> single backslash");

// 4-digit unicode
assertEquals(chr(65), parser.decodeBasicStringEscapes("\u0041"), "Strings: \\u0041 -> 'A'");

// 8-digit unicode (BMP only for now)
assertEquals(chr(65), parser.decodeBasicStringEscapes("\U00000041"), "Strings: \U00000041 -> 'A'");

// Mixed content
assertEquals("a" & chr(10) & "b", parser.decodeBasicStringEscapes("a\nb"), "Strings: mixed content");

// Unknown escape sequence -> ParseError
assertThrows("cfTOML\.ParseError", function() {
	parser.decodeBasicStringEscapes("\q");
}, "Strings: unknown escape sequence throws");

// decodeMultiLineBasicEscapes
// Identical to basic for normal escapes
assertEquals("a" & chr(10) & "b", parser.decodeMultiLineBasicEscapes("a\nb"), "MLBasicEscapes: \n works");
assertEquals('"', parser.decodeMultiLineBasicEscapes('\"'), "MLBasicEscapes: backslash-quote works");

// Line-continuation escape: backslash at end of line eats all whitespace until next non-whitespace
assertEquals("abc", parser.decodeMultiLineBasicEscapes("a\" & chr(10) & "   bc"), "MLBasicEscapes: backslash-LF skips whitespace");
assertEquals("ab", parser.decodeMultiLineBasicEscapes("a\" & chr(10) & chr(10) & chr(10) & "b"), "MLBasicEscapes: backslash-LF skips multiple newlines");
assertEquals("ab", parser.decodeMultiLineBasicEscapes("a\   " & chr(10) & "b"), "MLBasicEscapes: backslash-trailing-space-LF skips");
</cfscript>
