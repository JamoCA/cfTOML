<cfscript>
// Default spec is "1.0.0" when no option passed
toml = new cfTOML.cfTOML();
defaults = toml.mergeOptionsForTest();
assertEquals("1.0.0", defaults.spec, "SpecOption: default spec is 1.0.0");

// Per-call options override instance defaults
toml = new cfTOML.cfTOML([:]);
result = toml.tomlDeserialize("a = 1", ["spec": "1.1.0"]);
assertEquals(1, result.a, "SpecOption: per-call spec parses 1.0.0 syntax");

// Instance default carries through
toml = new cfTOML.cfTOML(["spec": "1.1.0"]);
result = toml.tomlDeserialize("a = 1");
assertEquals(1, result.a, "SpecOption: instance default spec parses 1.0.0 syntax");

// Per-call spec wins over instance default
toml = new cfTOML.cfTOML(["spec": "1.0.0"]);
result = toml.tomlDeserialize("a = 1", ["spec": "1.1.0"]);
assertEquals(1, result.a, "SpecOption: per-call spec overrides instance default");

// Unknown spec value throws ConfigError at merge time (init-time validation per Task 1; per-call validation lands in Task 8)
assertThrows("cfTOML\.ConfigError", function() {
	var t = new cfTOML.cfTOML(["spec": "9.9.9"]);
}, "SpecOption: unknown spec value throws cfTOML.ConfigError");
</cfscript>

<cfscript>
// 1.1.0 emitter knobs throw cfTOML.ConfigError under spec=1.0.0

knobs = ["inlineMultiline", "useExtendedEscapes", "omitZeroSeconds", "useBareDigitKeys"];
sample = [:];
sample["a"] = 1;

for (ki = 1; ki lte arraylen(knobs); ki++) {
	knob = knobs[ki];
	assertThrows("cfTOML\.ConfigError", function() {
		var t = new cfTOML.cfTOML();
		var opts = ["spec": "1.0.0"];
		opts[knob] = javacast("boolean", 1);
		t.tomlSerialize(sample, opts);
	}, "SpecOption: knob " & knob & " throws ConfigError under spec=1.0.0");
}

// Same knobs are accepted under spec=1.1.0 (no throw, output is produced)
for (kj = 1; kj lte arraylen(knobs); kj++) {
	knob = knobs[kj];
	t11 = new cfTOML.cfTOML();
	opts11 = ["spec": "1.1.0"];
	opts11[knob] = javacast("boolean", 1);
	out11 = t11.tomlSerialize(sample, opts11);
	assertEquals(true, find("a = 1", out11) gt 0, "SpecOption: knob " & knob & " accepted under spec=1.1.0");
}
</cfscript>
