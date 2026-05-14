<cfscript>
toml = new cfTOML.cfTOML();

// 1.1.0: top-level all-digit bare key
result = toml.tomlDeserialize('1234 = "value"', ["spec": "1.1.0"]);
assertEquals("value", result["1234"], "Toml11Keys: 1234 = 'value' under 1.1.0");

// 1.1.0: leading-zero bare key
result = toml.tomlDeserialize('007 = "Bond"', ["spec": "1.1.0"]);
assertEquals("Bond", result["007"], "Toml11Keys: 007 = 'Bond' preserves leading zeros");

// 1.1.0: all-digit segment inside a dotted key
result = toml.tomlDeserialize('foo.1234 = "value"', ["spec": "1.1.0"]);
assertEquals("value", result.foo["1234"], "Toml11Keys: foo.1234 dotted key");

// 1.1.0: all-digit key inside an inline table
result = toml.tomlDeserialize('t = { 1234 = "x" }', ["spec": "1.1.0"]);
assertEquals("x", result.t["1234"], "Toml11Keys: inline-table all-digit key");

// 1.1.0: all-digit segment in a table header
result = toml.tomlDeserialize('[1234]' & chr(10) & 'k = 1', ["spec": "1.1.0"]);
assertEquals(1, result["1234"].k, "Toml11Keys: table header [1234]");

// All-digit bare keys are valid in TOML 1.0.0 as well (the spec note reads "bare keys
// are allowed to be composed of only ASCII digits, e.g. 1234, but are always interpreted
// as strings"). The 1.1.0 changes here extend the set, but 1.0.0 already accepts them.
result = toml.tomlDeserialize('1234 = "value"', ["spec": "1.0.0"]);
assertEquals("value", result["1234"], "Toml11Keys: 1.0.0 accepts all-digit bare key");
</cfscript>
