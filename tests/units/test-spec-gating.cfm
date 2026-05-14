<cfscript>
sgToml = new cfTOML.cfTOML();

// Test matrix: each entry is [feature_name, input_toml]
// Note: all-digit bare keys (`1234 = "v"`) are NOT in this gating list because the
// TOML 1.0.0 spec already allows them ("bare keys are allowed to be composed of only
// ASCII digits, e.g. 1234, but are always interpreted as strings").
sgFeatures = [
	["multiline-inline-table", "t = {" & chr(10) & "  a = 1" & chr(10) & "}"],
	["trailing-comma-inline",  "t = { a = 1, }"],
	["escape-e",                's = "\e"'],
	["escape-xHH",              's = "\x41"'],
	["datetime-no-seconds-lt",  "t = 07:32"],
	["datetime-no-seconds-ldt", "dt = 1979-05-27T07:32"]
];

// 1.0.0 mode: every feature must throw
for (sgI = 1; sgI lte arraylen(sgFeatures); sgI++) {
	sgName = sgFeatures[sgI][1];
	sgSrc = sgFeatures[sgI][2];
	sgRejected = javacast("boolean", 0);
	try {
		sgToml.tomlDeserialize(sgSrc, ["spec": "1.0.0"]);
	} catch (cfTOML.ParseError eParse) {
		sgRejected = javacast("boolean", 1);
	}
	assertEquals(true, sgRejected, "SpecGating: 1.0.0 rejects feature " & sgName);
}

// 1.1.0 mode: every feature must parse successfully (no throw)
for (sgJ = 1; sgJ lte arraylen(sgFeatures); sgJ++) {
	sgName2 = sgFeatures[sgJ][1];
	sgSrc2 = sgFeatures[sgJ][2];
	sgOk = javacast("boolean", 0);
	try {
		sgResult = sgToml.tomlDeserialize(sgSrc2, ["spec": "1.1.0"]);
		sgOk = javacast("boolean", structcount(sgResult) gt 0);
	} catch (any eAny2) {
		// Re-throw with clearer label so test failure pinpoints which feature
		throw(type="cfTOML.TestError", message="1.1.0 mode failed feature '" & sgName2 & "': " & eAny2.message);
	}
	assertEquals(true, sgOk, "SpecGating: 1.1.0 accepts feature " & sgName2);
}
</cfscript>
