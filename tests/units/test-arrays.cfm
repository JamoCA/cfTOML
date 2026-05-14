<cfscript>
// Empty array
result = parser.tomlDeserialize("x = []");
assert(isArray(result.x), "Arrays: empty array is CFML array");
assertEquals(0, arraylen(result.x), "Arrays: empty array length 0");

// Single-element array
result = parser.tomlDeserialize("x = [1]");
assertEquals(1, arraylen(result.x), "Arrays: single-element length");
assertEquals(1, result.x[1], "Arrays: single-element value");

// Multi-element integer array
result = parser.tomlDeserialize("x = [1, 2, 3]");
assertEquals(3, arraylen(result.x), "Arrays: three-element length");
assertEquals(1, result.x[1], "Arrays: element 1");
assertEquals(2, result.x[2], "Arrays: element 2");
assertEquals(3, result.x[3], "Arrays: element 3");

// String array
result = parser.tomlDeserialize('x = ["a", "b", "c"]');
assertEquals("a", result.x[1], "Arrays: string element 1");
assertEquals("c", result.x[3], "Arrays: string element 3");

// Boolean array
result = parser.tomlDeserialize("x = [true, false, true]");
assertEquals(javacast("boolean", 1), result.x[1], "Arrays: bool true");
assertEquals(javacast("boolean", 0), result.x[2], "Arrays: bool false");

// Trailing comma (allowed in TOML 1.0)
result = parser.tomlDeserialize("x = [1, 2, 3,]");
assertEquals(3, arraylen(result.x), "Arrays: trailing comma allowed");

// Multi-line array
result = parser.tomlDeserialize("x = [" & chr(10) & "1," & chr(10) & "2," & chr(10) & "3" & chr(10) & "]");
assertEquals(3, arraylen(result.x), "Arrays: multi-line length");
assertEquals(2, result.x[2], "Arrays: multi-line element");

// Nested array
result = parser.tomlDeserialize("x = [[1, 2], [3, 4]]");
assertEquals(2, arraylen(result.x), "Arrays: nested outer length");
assert(isArray(result.x[1]), "Arrays: nested element is array");
assertEquals(2, arraylen(result.x[1]), "Arrays: nested inner length");
assertEquals(3, result.x[2][1], "Arrays: nested element access");

// Mixed types (TOML 1.0 allows this)
result = parser.tomlDeserialize('x = [1, "two", true]');
assertEquals(1, result.x[1], "Arrays: mixed int");
assertEquals("two", result.x[2], "Arrays: mixed string");
assertEquals(javacast("boolean", 1), result.x[3], "Arrays: mixed bool");

// Array of strings spanning lines
result = parser.tomlDeserialize('x = [' & chr(10) & '  "a",' & chr(10) & '  "b"' & chr(10) & ']');
assertEquals(2, arraylen(result.x), "Arrays: multi-line strings");
assertEquals("b", result.x[2], "Arrays: multi-line string value");
</cfscript>
