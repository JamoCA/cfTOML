<cfsetting enablecfoutputonly="false" showdebugoutput="false">
<cfprocessingdirective suppresswhitespace="false">
<cfoutput><pre>
[ cfTOML test runner ]

<cfscript>
request.testStats = ["pass": 0, "fail": 0, "errors": 0];

// Load assertion helpers
include "assert.cfm";

// Create the parser instance (visible to every included test file)
parser = new cfTOML.cfTOML();

// Run each test file. Add a new include per test-*.cfm file as it's created.
include "units/test-skeleton.cfm";
include "units/test-tokenizer.cfm";
include "units/test-strings.cfm";
include "units/test-numbers.cfm";
include "units/test-datetime.cfm";
include "units/test-parser.cfm";
include "units/test-arrays.cfm";
include "units/test-inline-tables.cfm";
include "units/test-aot.cfm";
include "units/test-emitter.cfm";
include "units/test-roundtrip.cfm";
include "units/test-typed-json.cfm";
include "units/test-spec-option.cfm";
include "units/test-toml11-escapes.cfm";
include "units/test-toml11-datetime.cfm";
include "units/test-toml11-keys.cfm";
include "units/test-toml11-inline.cfm";
include "units/test-toml11-emit.cfm";
include "units/test-spec-gating.cfm";
</cfscript>

-------------------------------------------
#request.testStats.pass# passed, #request.testStats.fail# failed, #request.testStats.errors# errors
</pre></cfoutput>
</cfprocessingdirective>
