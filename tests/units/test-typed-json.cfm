<cfscript>
include "../conformance/typed-json.cfm";

// Integer
result = toCfmlTypedJson(parser.tomlDeserialize("x = 42").x);
expected = ["type": "integer", "value": "42"];
assertEquals(expected, result, "TypedJson: integer");

// Boolean
result = toCfmlTypedJson(parser.tomlDeserialize("x = true").x);
expected = ["type": "bool", "value": "true"];
assertEquals(expected, result, "TypedJson: bool true");

// Float
result = toCfmlTypedJson(parser.tomlDeserialize("x = 1.5").x);
expected = ["type": "float", "value": "1.5"];
assertEquals(expected, result, "TypedJson: float");

// String
result = toCfmlTypedJson(parser.tomlDeserialize('x = "hello"').x);
expected = ["type": "string", "value": "hello"];
assertEquals(expected, result, "TypedJson: string");

// Array (JSON array, elements typed)
result = toCfmlTypedJson(parser.tomlDeserialize("x = [1, 2, 3]").x);
assertEquals(3, arraylen(result), "TypedJson: array length");
assertEquals("integer", result[1].type, "TypedJson: array element 1 type");
assertEquals("1", result[1].value, "TypedJson: array element 1 value");

// Table (JSON object)
result = toCfmlTypedJson(parser.tomlDeserialize("a = 1"));
assert(structkeyexists(result, "a"), "TypedJson: table key present");
assertEquals("integer", result.a.type, "TypedJson: table value type");
assertEquals("1", result.a.value, "TypedJson: table value");

// Nested table
result = toCfmlTypedJson(parser.tomlDeserialize("[server]" & chr(10) & "host = " & chr(34) & "h" & chr(34)));
assert(structkeyexists(result, "server"), "TypedJson: nested table parent");
assertEquals("string", result.server.host.type, "TypedJson: nested string type");

// Datetime offset
result = toCfmlTypedJson(parser.tomlDeserialize("when = 1979-05-27T07:32:00Z", ["dateTimeReturn": "javatime"]).when);
assertEquals("datetime", result.type, "TypedJson: datetime offset type");

// Datetime local
result = toCfmlTypedJson(parser.tomlDeserialize("when = 1979-05-27T07:32:00", ["dateTimeReturn": "javatime"]).when);
assertEquals("datetime-local", result.type, "TypedJson: datetime-local type");

// Date local
result = toCfmlTypedJson(parser.tomlDeserialize("when = 1979-05-27", ["dateTimeReturn": "javatime"]).when);
assertEquals("date-local", result.type, "TypedJson: date-local type");

// Time local
result = toCfmlTypedJson(parser.tomlDeserialize("when = 07:32:00", ["dateTimeReturn": "javatime"]).when);
assertEquals("time-local", result.type, "TypedJson: time-local type");
</cfscript>
