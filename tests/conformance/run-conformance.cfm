<cfsetting enablecfoutputonly="false" showdebugoutput="false">
<cfprocessingdirective suppresswhitespace="false">
<cfoutput><pre>
[ cfTOML conformance runner ]
Corpus: BurntSushi/toml-test pinned (see tests/conformance/README.md)

<cfscript>
request.conformanceStats = ["valid_pass": 0, "valid_fail": 0, "invalid_pass": 0, "invalid_fail": 0, "errors": 0];
spec = structKeyExists(url, "spec") ? url.spec : "1.0.0";
if (spec neq "1.0.0" && spec neq "1.1.0") {
	writeOutput("Invalid spec '" & encodeForHTML(spec) & "'. Use spec=1.0.0 or spec=1.1.0." & chr(10));
	abort;
}
parser = new cfTOML.cfTOML(["spec": spec]);
writeOutput("Spec: TOML " & spec & chr(10));
include "typed-json.cfm";

if (spec eq "1.1.0") {
	corpusRoot = expandPath("/cfTOML/tests/conformance/corpus-1.1.0");
} else {
	corpusRoot = expandPath("/cfTOML/tests/conformance/corpus");
}
validDir = corpusRoot & "/valid";
invalidDir = corpusRoot & "/invalid";

// Read a file as strict UTF-8 (reject malformed sequences and UTF-16 surrogates encoded as 3-byte CESU-8).
// CFML's fileRead silently substitutes the U+FFFD replacement character for malformed bytes on most engines,
// which masks the "this is not valid UTF-8" rejection the TOML spec requires. This uses InputStreamReader
// rather than ByteBuffer.wrap() because BoxLang cannot dispatch the static wrap() method on the abstract
// ByteBuffer class via createObject; InputStreamReader works through instance methods only.
function readStrictUtf8(filepath) {
	var REPORT = createObject("java", "java.nio.charset.CodingErrorAction").REPORT;
	var decoder = createObject("java", "java.nio.charset.StandardCharsets").UTF_8.newDecoder();
	decoder.onMalformedInput(REPORT);
	decoder.onUnmappableCharacter(REPORT);
	var jFile = createObject("java", "java.io.File").init(javacast("string", arguments.filepath));
	var fis = createObject("java", "java.io.FileInputStream").init(jFile);
	var reader = createObject("java", "java.io.InputStreamReader").init(fis, decoder);
	var sb = createObject("java", "java.lang.StringBuilder").init();
	var c = reader.read();
	while (c neq -1) {
		sb.append(javacast("char", c));
		c = reader.read();
	}
	reader.close();
	return sb.toString();
}

// Deep-equal that handles the typed-JSON shape comparison.
// Special case: a typed-JSON wrapper like {"type": "float", "value": "1.0"} compares numerically
// for the "value" string when "type" is "float", because Java's Double.toString(1.0) -> "1.0"
// while the BurntSushi expected JSON often uses "1" - CFML on Adobe coerces those equal via eq,
// Lucee does not, and the spec defines float identity numerically anyway.
function typedJsonEquals(a, b) {
	var result = javacast("boolean", 0);
	if (isStruct(arguments.a) && isStruct(arguments.b)) {
		result = typedJsonEqualsStructs(arguments.a, arguments.b);
	} else if (isArray(arguments.a) && isArray(arguments.b)) {
		result = typedJsonEqualsArrays(arguments.a, arguments.b);
	} else if (isSimpleValue(arguments.a) && isSimpleValue(arguments.b)) {
		result = (arguments.a eq arguments.b);
	}
	return javacast("boolean", result);
}

function typedJsonEqualsStructs(a, b) {
	var aKeys = structkeyarray(arguments.a);
	var bKeys = structkeyarray(arguments.b);
	var result = javacast("boolean", 1);
	if (arraylen(aKeys) neq arraylen(bKeys)) {
		result = javacast("boolean", 0);
	} else if (isFloatWrapper(arguments.a, arguments.b)) {
		result = floatWrapperEquals(arguments.a, arguments.b);
	} else {
		for (var k in aKeys) {
			if (!structkeyexists(arguments.b, k)) {
				result = javacast("boolean", 0);
				break;
			}
			if (!typedJsonEquals(arguments.a[k], arguments.b[k])) {
				result = javacast("boolean", 0);
				break;
			}
		}
	}
	return javacast("boolean", result);
}

function typedJsonEqualsArrays(a, b) {
	var result = javacast("boolean", 1);
	if (arraylen(arguments.a) neq arraylen(arguments.b)) {
		result = javacast("boolean", 0);
	} else {
		for (var i = 1; i lte arraylen(arguments.a); i++) {
			if (!typedJsonEquals(arguments.a[i], arguments.b[i])) {
				result = javacast("boolean", 0);
				break;
			}
		}
	}
	return javacast("boolean", result);
}

function isFloatWrapper(a, b) {
	if (!structkeyexists(arguments.a, "type") || !structkeyexists(arguments.a, "value")) return javacast("boolean", 0);
	if (!structkeyexists(arguments.b, "type") || !structkeyexists(arguments.b, "value")) return javacast("boolean", 0);
	if (arguments.a.type neq "float" || arguments.b.type neq "float") return javacast("boolean", 0);
	if (!isSimpleValue(arguments.a.value) || !isSimpleValue(arguments.b.value)) return javacast("boolean", 0);
	return javacast("boolean", 1);
}

function floatWrapperEquals(a, b) {
	var lcA = lcase(arguments.a.value);
	var lcB = lcase(arguments.b.value);
	var specials = "nan,inf,-inf,+inf";
	if (listFindNoCase(specials, lcA) || listFindNoCase(specials, lcB)) {
		return javacast("boolean", lcA eq lcB);
	}
	var result = javacast("boolean", 0);
	try {
		var dA = createObject("java", "java.lang.Double").parseDouble(arguments.a.value);
		var dB = createObject("java", "java.lang.Double").parseDouble(arguments.b.value);
		result = javacast("boolean", dA eq dB);
	} catch (any e) {
		result = javacast("boolean", arguments.a.value eq arguments.b.value);
	}
	return javacast("boolean", result);
}

function runValidTests(validDir, corpusRoot, parser) {
	writeOutput("Valid tests:" & chr(10));
	var validFiles = directoryList(arguments.validDir, true, "path", "*.toml");
	for (var tomlFile in validFiles) {
		try {
			var tomlContent = readStrictUtf8(tomlFile);
			var jsonFile = replace(tomlFile, ".toml", ".json");
			if (!fileExists(jsonFile)) {
				continue;
			}
			var expectedJsonText = fileRead(jsonFile, "UTF-8");
			var expectedStruct = caseSensitiveJsonDeserialize(expectedJsonText);
			var parsedStruct = arguments.parser.tomlDeserialize(tomlContent, ["dateTimeReturn": "javatime"]);
			var actualTyped = toCfmlTypedJson(parsedStruct);
			if (typedJsonEquals(actualTyped, expectedStruct)) {
				request.conformanceStats.valid_pass++;
			} else {
				request.conformanceStats.valid_fail++;
				writeOutput("  FAIL: " & replace(tomlFile, arguments.corpusRoot, "") & chr(10));
			}
		} catch (any e) {
			request.conformanceStats.errors++;
			writeOutput("  ERROR: " & replace(tomlFile, arguments.corpusRoot, "") & " - " & e.type & ": " & e.message & chr(10));
		}
	}
}

function runInvalidTests(invalidDir, corpusRoot, parser) {
	writeOutput(chr(10) & "Invalid tests:" & chr(10));
	var invalidFiles = directoryList(arguments.invalidDir, true, "path", "*.toml");
	for (var tomlFile in invalidFiles) {
		try {
			var tomlContent = "";
			try {
				tomlContent = readStrictUtf8(tomlFile);
			} catch (any readErr) {
				throw(type="cfTOML.ParseError", message="Not valid UTF-8: #readErr.message#");
			}
			arguments.parser.tomlDeserialize(tomlContent);
			request.conformanceStats.invalid_fail++;
			writeOutput("  FAIL (should have thrown): " & replace(tomlFile, arguments.corpusRoot, "") & chr(10));
		} catch (any e) {
			if (left(e.type, 7) eq "cfTOML.") {
				request.conformanceStats.invalid_pass++;
			} else {
				request.conformanceStats.errors++;
				writeOutput("  WRONG ERROR TYPE: " & replace(tomlFile, arguments.corpusRoot, "") & " - " & e.type & chr(10));
			}
		}
	}
}

runValidTests(validDir, corpusRoot, parser);
runInvalidTests(invalidDir, corpusRoot, parser);
</cfscript>

-------------------------------------------
Valid tests: #request.conformanceStats.valid_pass# passed, #request.conformanceStats.valid_fail# failed
Invalid tests: #request.conformanceStats.invalid_pass# passed, #request.conformanceStats.invalid_fail# failed
Errors: #request.conformanceStats.errors#
</pre></cfoutput>
</cfprocessingdirective>
