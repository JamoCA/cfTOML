<cfscript>
// Helper: parse, serialize, parse again, deep-equal check
function roundTripCheck(string toml, string label) {
	var first = parser.tomlDeserialize(arguments.toml);
	var emitted = parser.tomlSerialize(first);
	var second = parser.tomlDeserialize(emitted);
	assertEquals(first, second, "RoundTrip: " & arguments.label);
}

// Basic scalars
roundTripCheck("port = 8080", "integer");
roundTripCheck("flag = true", "boolean true");
roundTripCheck("flag = false", "boolean false");
roundTripCheck("ratio = 1.5", "float");
roundTripCheck('name = "hello"', "basic string");
roundTripCheck("tags = []", "empty array");
roundTripCheck("tags = [1, 2, 3]", "scalar array");

// Tables
roundTripCheck("[server]" & chr(10) & 'host = "h"' & chr(10) & "port = 8080", "single table");
roundTripCheck("[server.config]" & chr(10) & "timeout = 30", "dotted table");
roundTripCheck("[a]" & chr(10) & "x = 1" & chr(10) & "[b]" & chr(10) & "y = 2", "two tables");

// AoT
roundTripCheck("[[products]]" & chr(10) & 'name = "a"' & chr(10) & "[[products]]" & chr(10) & 'name = "b"', "AoT two entries");
roundTripCheck("[[products]]" & chr(10) & 'name = "x"' & chr(10) & "[products.color]" & chr(10) & 'hex = "FF"', "AoT with sub-table");

// Nested complex
roundTripCheck('title = "App"' & chr(10) & 'version = 1.5' & chr(10) & "[server]" & chr(10) & 'host = "h"' & chr(10) & "[[products]]" & chr(10) & 'name = "x"', "mixed top-level + table + AoT");

// Array of inline tables - parse gives array of structs, serialize emits [[key]] AoT, re-parse gives same structure
roundTripCheck('items = [{id = 1}, {id = 2}]', "array of inline tables");
</cfscript>

<cfscript>
// E2E round-trip of examples/basic.toml
firstParse = parser.tomlReadFile(expandPath("/cfTOML/examples/basic.toml"));
emittedToml = parser.tomlSerialize(firstParse);
secondParse = parser.tomlDeserialize(emittedToml);
assertEquals(firstParse, secondParse, "RoundTrip E2E: basic.toml parse-emit-parse equality");
</cfscript>
