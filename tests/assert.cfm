<cfscript>
// Pad a label to fixed width for aligned PASS/FAIL output
function _padLabel(required string label, numeric width=40) {
	if (len(arguments.label) gte arguments.width) {
		return arguments.label;
	}
	return arguments.label & repeatString(" ", arguments.width - len(arguments.label));
}

function _recordPass(required string label) {
	request.testStats.pass++;
	writeOutput(_padLabel(arguments.label) & " PASS" & chr(10));
}

function _recordFail(required string label, required string detail) {
	request.testStats.fail++;
	writeOutput(_padLabel(arguments.label) & " FAIL" & chr(10));
	writeOutput("  " & arguments.detail & chr(10));
}

function _recordError(required string label, required string detail) {
	request.testStats.errors++;
	writeOutput(_padLabel(arguments.label) & " ERROR" & chr(10));
	writeOutput("  " & arguments.detail & chr(10));
}

function assert(required boolean condition, required string label) {
	try {
		if (arguments.condition) {
			_recordPass(arguments.label);
		} else {
			_recordFail(arguments.label, "expected true, got false");
		}
	} catch (any e) {
		_recordError(arguments.label, e.type & ": " & e.message);
	}
}

function deepEquals(required any a, required any b) {
	// Same primitive equality
	if (isSimpleValue(arguments.a) && isSimpleValue(arguments.b)) {
		return arguments.a eq arguments.b;
	}
	// Arrays
	if (isArray(arguments.a) && isArray(arguments.b)) {
		if (arraylen(arguments.a) neq arraylen(arguments.b)) return javacast("boolean", 0);
		for (var i = 1; i lte arraylen(arguments.a); i++) {
			if (!deepEquals(arguments.a[i], arguments.b[i])) return javacast("boolean", 0);
		}
		return javacast("boolean", 1);
	}
	// Structs (including ordered)
	if (isStruct(arguments.a) && isStruct(arguments.b)) {
		var aKeys = structkeyarray(arguments.a);
		var bKeys = structkeyarray(arguments.b);
		if (arraylen(aKeys) neq arraylen(bKeys)) return javacast("boolean", 0);
		for (var k in aKeys) {
			if (!structkeyexists(arguments.b, k)) return javacast("boolean", 0);
			if (!deepEquals(arguments.a[k], arguments.b[k])) return javacast("boolean", 0);
		}
		return javacast("boolean", 1);
	}
	// Type mismatch
	return javacast("boolean", 0);
}

function assertEquals(required any expected, required any actual, required string label) {
	try {
		if (deepEquals(arguments.expected, arguments.actual)) {
			_recordPass(arguments.label);
		} else {
			var expStr = isSimpleValue(arguments.expected) ? toString(arguments.expected) : serializeJSON(arguments.expected);
			var actStr = isSimpleValue(arguments.actual) ? toString(arguments.actual) : serializeJSON(arguments.actual);
			_recordFail(arguments.label, "expected " & expStr & ", got " & actStr);
		}
	} catch (any e) {
		_recordError(arguments.label, e.type & ": " & e.message);
	}
}

function assertThrows(required string typePattern, required any callback, required string label) {
	try {
		arguments.callback();
		_recordFail(arguments.label, "expected throw matching " & arguments.typePattern & " but no error was thrown");
	} catch (any e) {
		if (reFind(arguments.typePattern, e.type)) {
			_recordPass(arguments.label);
		} else {
			_recordFail(arguments.label, "expected throw matching " & arguments.typePattern & " but got " & e.type);
		}
	}
}
</cfscript>
