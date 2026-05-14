<cfscript>
// Convert a cfTOML-parsed value to BurntSushi/toml-test "typed JSON" format.
// Tables -> JSON objects (recurse), arrays -> JSON arrays (recurse), scalars -> {"type": ..., "value": ...}.

// Build a case-sensitive ordered struct only on Adobe CF (2021+), which is the only engine whose
// dot-notation accessor preserves key case on the resulting struct. Lucee and BoxLang both return
// case-sensitive struct implementations whose dot-notation accessor still uppercases the lookup
// key, so a key stored as "title" cannot be read via .title - and the test runner uses dot-notation
// throughout. CF2016/2018 lacks the type entirely; same fallback.
function newTypedJsonStruct() {
	if (structkeyexists(server, "lucee") || structkeyexists(server, "boxlang")) {
		return [:];
	}
	var attempts = ["ordered-casesensitive", "linked-casesensitive", "casesensitive-ordered"];
	for (var t in attempts) {
		try {
			return structNew(t);
		} catch (any e) {}
	}
	return [:];
}

// Case-sensitive JSON deserializer via Jackson. CFML's built-in deserializeJSON folds keys
// that differ only in case ("section" and "Section" both end up at one slot), which breaks
// comparison for tests like key/case-sensitive.toml. Jackson preserves case in JsonNode.
function caseSensitiveJsonDeserialize(jsonText) {
	// Jackson is bundled with CF2018+, Lucee, and BoxLang. On CF2016 (which ships only an older Jackson
	// under a different package) fall back to CFML's deserializeJSON. CF2016 lacks case-sensitive
	// ordered structs anyway, so test data with case-only key differences is a documented limitation
	// on that engine; this fallback at least lets the rest of the conformance suite run.
	try {
		var mapper = createObject("java", "com.fasterxml.jackson.databind.ObjectMapper").init();
		var node = mapper.readTree(arguments.jsonText);
		return jsonNodeToCfml(node);
	} catch (any e) {
		return deserializeJSON(arguments.jsonText);
	}
}

// Java's LocalDateTime/OffsetDateTime/LocalTime toString() OMITS the ":SS" component when seconds and
// nanoseconds are both zero (per the OpenJDK ISO-8601 spec). The toml-test expected JSON always carries
// ":SS", so we splice ":00" in before the timezone/end-of-string when the seconds piece is missing.
// CF2021+ silently coerces the un-normalized strings to dates in `eq`, so this normalization is only
// load-bearing on CF2016/2018 - but it's correct everywhere.
function normalizeJavaTimeString(s) {
	// Match HH:MM that is either at start-of-string (LocalTime case) or preceded by T/space/lowercase-t
	// (LocalDateTime/OffsetDateTime case), and is NOT followed by :digit (i.e., the SS portion is absent).
	// reFind capture-group indexing: pos[1]/len[1] = full match, pos[2]/len[2] = first group (the HH:MM).
	var match = reFind("(^|[Tt ])([0-9]{2}:[0-9]{2})(?![:][0-9])", arguments.s, 1, true);
	if (match.len[1] gt 0) {
		var hmEnd = match.pos[3] + match.len[3] - 1;
		return mid(arguments.s, 1, hmEnd) & ":00" & mid(arguments.s, hmEnd + 1, len(arguments.s) - hmEnd);
	}
	return arguments.s;
}

function jsonNodeToCfml(node) {
	if (arguments.node.isObject()) {
		var out = newTypedJsonStruct();
		var fields = arguments.node.fields();
		while (fields.hasNext()) {
			var entry = fields.next();
			out[entry.getKey()] = jsonNodeToCfml(entry.getValue());
		}
		return out;
	}
	if (arguments.node.isArray()) {
		var out = [];
		var iter = arguments.node.elements();
		while (iter.hasNext()) {
			arrayappend(out, jsonNodeToCfml(iter.next()));
		}
		return out;
	}
	if (arguments.node.isNull()) {
		return javaCast("null", 0);
	}
	if (arguments.node.isBoolean()) {
		return arguments.node.asBoolean();
	}
	if (arguments.node.isTextual()) {
		return arguments.node.asText();
	}
	if (arguments.node.isNumber()) {
		// Numbers in the typed-JSON expected files are always under {"type":..., "value":"..."},
		// so this branch only fires for the outer wrappers and would not normally hit. Best-effort.
		return arguments.node.asText();
	}
	return arguments.node.toString();
}

function toCfmlTypedJson(value) {
	// Struct (table) - recurse on each key
	if (isStruct(arguments.value) && !isArray(arguments.value)) {
		var out = newTypedJsonStruct();
		for (var key in arguments.value) {
			out[key] = toCfmlTypedJson(arguments.value[key]);
		}
		return out;
	}
	// Array - recurse on each element
	if (isArray(arguments.value)) {
		var out = [];
		for (var elem in arguments.value) {
			arrayappend(out, toCfmlTypedJson(elem));
		}
		return out;
	}
	// Java-class-based detection for simple values. Order matters: check String first so
	// numeric-looking strings like "4" (a quoted TOML scalar) are not promoted to integer.
	if (isSimpleValue(arguments.value)) {
		try {
			var cls = arguments.value.getClass().getName();
			if (cls eq "java.lang.String") {
				return ["type": "string", "value": arguments.value];
			}
			if (cls eq "java.lang.Boolean") {
				return ["type": "bool", "value": (arguments.value ? "true" : "false")];
			}
			if (cls eq "java.lang.Double") {
				var d = arguments.value.doubleValue();
				if (createObject("java", "java.lang.Double").isNaN(d)) {
					return ["type": "float", "value": "nan"];
				}
				if (createObject("java", "java.lang.Double").isInfinite(d)) {
					return ["type": "float", "value": (d gt 0 ? "inf" : "-inf")];
				}
				// Use Java's canonical Double.toString() so precision is preserved
				// (CFML's toString() truncates to ~11 sig digits on Adobe CF).
				return ["type": "float", "value": createObject("java", "java.lang.Double").toString(d)];
			}
			if (cls eq "java.lang.Long" || cls eq "java.lang.Integer") {
				return ["type": "integer", "value": arguments.value.toString()];
			}
		} catch (any e) {}
	}
	// Java time objects (non-simple)
	if (!isSimpleValue(arguments.value)) {
		try {
			var cls2 = arguments.value.getClass().getName();
			if (cls2 eq "java.time.OffsetDateTime") {
				return ["type": "datetime", "value": normalizeJavaTimeString(arguments.value.toString())];
			}
			if (cls2 eq "java.time.LocalDateTime") {
				return ["type": "datetime-local", "value": normalizeJavaTimeString(arguments.value.toString())];
			}
			if (cls2 eq "java.time.LocalDate") {
				return ["type": "date-local", "value": arguments.value.toString()];
			}
			if (cls2 eq "java.time.LocalTime") {
				return ["type": "time-local", "value": normalizeJavaTimeString(arguments.value.toString())];
			}
		} catch (any e) {}
	}
	// CFML date detection
	if (isDate(arguments.value) && isSimpleValue(arguments.value)) {
		try {
			var dCls = arguments.value.getClass().getName();
			if (dCls neq "java.lang.String") {
				// CFML date - emit as datetime-local (matches Task 1 behavior). Build from component
				// accessors rather than dateTimeFormat() because mask conventions differ across engines.
				var dt = year(arguments.value) & "-" & numberFormat(month(arguments.value), "00")
				       & "-" & numberFormat(day(arguments.value), "00")
				       & "T" & numberFormat(hour(arguments.value), "00")
				       & ":" & numberFormat(minute(arguments.value), "00")
				       & ":" & numberFormat(second(arguments.value), "00");
				return ["type": "datetime-local", "value": dt];
			}
		} catch (any e) {}
	}
	// Integer detection for plain CFML numbers
	if (isSimpleValue(arguments.value) && isNumeric(arguments.value)) {
		if (int(arguments.value) eq arguments.value) {
			return ["type": "integer", "value": toString(int(arguments.value))];
		}
		return ["type": "float", "value": toString(arguments.value)];
	}
	// Fall back to string
	if (isSimpleValue(arguments.value)) {
		return ["type": "string", "value": toString(arguments.value)];
	}
	throw(type="cfTOML.TypedJsonError", message="Cannot convert value of unsupported type to typed JSON");
}
</cfscript>
