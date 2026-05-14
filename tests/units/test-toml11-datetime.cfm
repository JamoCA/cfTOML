<cfscript>
toml = new cfTOML.cfTOML();

// 1.1.0: local time without seconds normalizes to :00
result = toml.tomlDeserialize('t = 07:32', ["spec": "1.1.0", "dateTimeReturn": "iso8601"]);
assertEquals("07:32:00", result.t, "Toml11DateTime: local time no-seconds -> :00 (iso8601)");

// 1.1.0: local datetime without seconds normalizes to :00
result = toml.tomlDeserialize('dt = 1979-05-27T07:32', ["spec": "1.1.0", "dateTimeReturn": "iso8601"]);
assertEquals("1979-05-27T07:32:00", result.dt, "Toml11DateTime: local datetime no-seconds -> :00 (iso8601)");

// 1.1.0: offset datetime without seconds normalizes to :00
result = toml.tomlDeserialize('odt = 1979-05-27 07:32Z', ["spec": "1.1.0", "dateTimeReturn": "iso8601"]);
assertEquals("1979-05-27 07:32:00Z", result.odt, "Toml11DateTime: offset datetime no-seconds -> :00 (iso8601)");

// 1.1.0: cfdate mode still works for seconds-less time
result = toml.tomlDeserialize('t = 07:32', ["spec": "1.1.0"]);
assertEquals(7, hour(result.t), "Toml11DateTime: cfdate hour from no-seconds time");
assertEquals(32, minute(result.t), "Toml11DateTime: cfdate minute from no-seconds time");
assertEquals(0, second(result.t), "Toml11DateTime: cfdate second defaults to 0");

// 1.0.0: seconds-less time throws
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlDeserialize('t = 07:32', ["spec": "1.0.0"]);
}, "Toml11DateTime: 1.0.0 rejects no-seconds time");

// 1.0.0: seconds-less local datetime throws
assertThrows("cfTOML\.ParseError", function() {
	var t = new cfTOML.cfTOML();
	t.tomlDeserialize('dt = 1979-05-27T07:32', ["spec": "1.0.0"]);
}, "Toml11DateTime: 1.0.0 rejects no-seconds local datetime");

// 1.1.0: with-seconds form still works (regression)
result = toml.tomlDeserialize('dt = 1979-05-27T07:32:45', ["spec": "1.1.0", "dateTimeReturn": "iso8601"]);
assertEquals("1979-05-27T07:32:45", result.dt, "Toml11DateTime: 1.1.0 with-seconds still parses");
</cfscript>
