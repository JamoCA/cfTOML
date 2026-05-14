<cfsetting enablecfoutputonly="false" showdebugoutput="false">
<cfprocessingdirective suppresswhitespace="false">
<cfscript>
// Engine + version detection
function detectEngineInfo() {
	var info = [:];
	if (structkeyexists(server, "boxlang")) {
		info.platform = "BoxLang";
		info.version = structkeyexists(server.boxlang, "version") ? server.boxlang.version : "unknown";
	} else if (structkeyexists(server, "lucee")) {
		info.platform = "Lucee";
		info.version = structkeyexists(server.lucee, "version") ? server.lucee.version : "unknown";
	} else if (structkeyexists(server, "coldfusion")) {
		info.platform = "Adobe ColdFusion";
		var pv = structkeyexists(server.coldfusion, "productversion") ? server.coldfusion.productversion : "";
		var pl = structkeyexists(server.coldfusion, "productlevel") ? server.coldfusion.productlevel : "";
		info.version = trim(pv & (len(pl) ? " (" & pl & ")" : ""));
	} else {
		info.platform = "unknown";
		info.version = "";
	}
	info.java = structkeyexists(server, "java") && structkeyexists(server.java, "version") ? server.java.version : "?";
	return info;
}

engineInfo = detectEngineInfo();
parser = new cfTOML();

// Sample TOML payloads. Using single-quoted CFML strings so literal # (TOML comment marker) is not interpolated.
samples_toml = [:];
samples_toml["basic"] =
	'## A basic TOML example' & chr(10) &
	'title = "cfTOML Example"' & chr(10) &
	'version = 1.0' & chr(10) &
	'' & chr(10) &
	'[server]' & chr(10) &
	'host = "10.0.0.1"' & chr(10) &
	'port = 8080' & chr(10) &
	'enabled = true';

samples_toml["datetime"] =
	'## Datetime examples' & chr(10) &
	'launched = 1979-05-27T07:32:00Z' & chr(10) &
	'birthday = 2024-01-15' & chr(10) &
	'meeting = 14:30:00' & chr(10) &
	'local_dt = 2024-01-15T10:30:00';

samples_toml["arrays"] =
	'## Arrays' & chr(10) &
	'numbers = [1, 2, 3, 4, 5]' & chr(10) &
	'strings = ["alpha", "beta", "gamma"]' & chr(10) &
	'mixed = [1, "two", 3.14, true]';

samples_toml["inline"] =
	'## Inline tables' & chr(10) &
	'point = {x = 1, y = 2}' & chr(10) &
	'contact = {name = "Alice", email = "alice@example.com"}';

samples_toml["aot"] =
	'## Array of tables' & chr(10) &
	'[[products]]' & chr(10) &
	'name = "widget"' & chr(10) &
	'sku = "W-001"' & chr(10) &
	'' & chr(10) &
	'[[products]]' & chr(10) &
	'name = "gadget"' & chr(10) &
	'sku = "G-002"';

samples_toml["numbers"] =
	'## Number formats' & chr(10) &
	'hex = 0xDEADBEEF' & chr(10) &
	'oct = 0o755' & chr(10) &
	'bin = 0b1011' & chr(10) &
	'big = 1_000_000' & chr(10) &
	'pi = 3.14159' & chr(10) &
	'exp = 1e6' & chr(10) &
	'neg_inf = -inf' & chr(10) &
	'nan_val = nan';

samples_toml["strings"] =
	'## String variants' & chr(10) &
	'basic = "Hello\tworld\n"' & chr(10) &
	'multi = """' & chr(10) &
	'line 1' & chr(10) &
	'line 2' & chr(10) &
	'"""';

samples_toml["11_multiline"] =
	'## TOML 1.1.0 multi-line inline (needs 1.1.0 mode)' & chr(10) &
	'contact = {' & chr(10) &
	'  name = "Donald Duck",' & chr(10) &
	'  email = "donald@duckburg.com",' & chr(10) &
	'}';

samples_toml["11_digitkeys"] =
	'## TOML 1.1.0 all-digit bare keys (needs 1.1.0 mode)' & chr(10) &
	'1234 = "value"' & chr(10) &
	'007 = "Bond"';

samples_toml["11_noseconds"] =
	'## TOML 1.1.0 optional datetime seconds (needs 1.1.0 mode)' & chr(10) &
	't = 07:32' & chr(10) &
	'dt = 1979-05-27T07:32' & chr(10) &
	'odt = 1979-05-27T07:32Z';

samples_toml["11_eescape"] =
	'## TOML 1.1.0 \e escape (needs 1.1.0 mode)' & chr(10) &
	's = "escape\e here"';

// Pre-built CFML samples for emit (server side, never editable from the page)
function buildSample(key) {
	switch (arguments.key) {
		case "simple":
			return ["title": "cfTOML Example", "version": 1.0, "active": javacast("boolean", 1)];
		case "nested":
			return ["server": ["host": "10.0.0.1", "port": 8080], "client": ["host": "10.0.0.2", "port": 9090]];
		case "withdate":
			return ["launched": now(), "title": "Demo", "count": 42];
		case "arrays":
			return ["tags": ["alpha", "beta", "stable"], "counts": [1, 2, 3], "mixed": [1, "two", javacast("boolean", 1)]];
		case "aot":
			return ["products": [["name": "widget", "sku": "W-001"], ["name": "gadget", "sku": "G-002"]]];
		case "deep":
			var inner = [:];
			inner.appendix = ["version": "1.0", "date": "2026-05-12"];
			inner.tags = ["alpha", "beta"];
			return ["app": ["name": "cfTOML", "config": ["timeout": 30, "retries": 3]], "meta": inner];
	}
	return [:];
}

// Read inputs (POST or GET defaults)
isPost = (cgi.request_method eq "POST");
action = isPost && structkeyexists(form, "action") ? form.action : "";
toml_sample = isPost && structkeyexists(form, "toml_sample") ? form.toml_sample : "basic";
toml_input = isPost && structkeyexists(form, "toml_input") ? form.toml_input : samples_toml.basic;
cfml_sample = isPost && structkeyexists(form, "cfml_sample") ? form.cfml_sample : "simple";
json_input = isPost && structkeyexists(form, "json_input") ? form.json_input : '{"server": {"host": "10.0.0.1", "port": 8080}, "tags": ["alpha", "beta"]}';
spec_mode = isPost && structkeyexists(form, "spec_mode") ? form.spec_mode : "1.0.0";

// Perform conversion if action set
result_data = "";
result_parsed = "";
result_error = "";
result_single_ms = 0;
result_throughput = 0;
result_action = "";

function runParse(toml, spec) {
	var out = ["data": "", "parsed": "", "error": "", "single_ms": 0, "throughput": 0];
	try {
		var opts = ["spec": arguments.spec];
		var t0 = getTickCount();
		var parsed = parser.tomlDeserialize(arguments.toml, opts);
		var t1 = getTickCount();
		out.single_ms = t1 - t0;
		out.data = serializeJSON(parsed);
		out.parsed = parsed;

		var count = 0;
		var loopStart = getTickCount();
		while ((getTickCount() - loopStart) lt 1000) {
			parser.tomlDeserialize(arguments.toml, opts);
			count++;
		}
		out.throughput = count;
	} catch (any e) {
		out.error = e.type & ": " & e.message;
		if (structkeyexists(e, "detail") && len(e.detail)) {
			out.error &= chr(10) & e.detail;
		}
	}
	return out;
}

function runEmit(data, spec) {
	var out = ["data": "", "error": "", "single_ms": 0, "throughput": 0];
	try {
		var opts = ["spec": arguments.spec];
		var t0 = getTickCount();
		var emitted = parser.tomlSerialize(arguments.data, opts);
		var t1 = getTickCount();
		out.single_ms = t1 - t0;
		out.data = emitted;

		var count = 0;
		var loopStart = getTickCount();
		while ((getTickCount() - loopStart) lt 1000) {
			parser.tomlSerialize(arguments.data, opts);
			count++;
		}
		out.throughput = count;
	} catch (any e) {
		out.error = e.type & ": " & e.message;
	}
	return out;
}

if (action eq "parse" && len(toml_input)) {
	result_action = "parse";
	r = runParse(toml_input, spec_mode);
	result_data = r.data;
	result_parsed = r.parsed;
	result_error = r.error;
	result_single_ms = r.single_ms;
	result_throughput = r.throughput;
}

if (action eq "emit") {
	result_action = "emit";
	try {
		cfml_data = "";
		if (cfml_sample eq "json") {
			if (!len(json_input)) {
				throw(type="DemoError", message="JSON input is empty.");
			}
			cfml_data = deserializeJSON(json_input);
		} else {
			cfml_data = buildSample(cfml_sample);
		}
		r = runEmit(cfml_data, spec_mode);
		result_data = r.data;
		result_error = r.error;
		result_single_ms = r.single_ms;
		result_throughput = r.throughput;
	} catch (any e) {
		result_error = e.type & ": " & e.message;
	}
}
</cfscript>
<!DOCTYPE html>
<html>
<head>
<title>cfTOML live demo</title>
<style>
	body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; max-width: 1200px; margin: 1em auto; padding: 0 1em; color: #222; }
	h1 { margin-bottom: 0.2em; }
	.platform { background: #f0f4f8; padding: 0.6em 1em; border-left: 4px solid #4a8bc2; margin: 0.5em 0 1.5em; font-size: 14px; }
	.cols { display: flex; gap: 1.5em; flex-wrap: wrap; }
	.col { flex: 1; min-width: 420px; }
	h2 { margin-top: 0; color: #2a5f8f; }
	label { display: block; margin-top: 0.8em; font-weight: 600; font-size: 13px; color: #444; }
	textarea, select, input[type=text] { width: 100%; box-sizing: border-box; font-family: "Courier New", Consolas, monospace; font-size: 13px; padding: 0.4em; }
	textarea { resize: vertical; }
	textarea:disabled { background: #eee; color: #999; cursor: not-allowed; }
	.spec-row { margin: 0.6em 0; }
	.spec-row label { display: inline-block; margin: 0 1em 0 0; font-weight: normal; }
	button { padding: 0.6em 1.2em; font-size: 14px; background: #2a5f8f; color: white; border: 0; cursor: pointer; margin-top: 0.8em; }
	button:hover { background: #1d4670; }
	.result { background: #f8f8f8; border: 1px solid #ddd; padding: 0.7em; min-height: 5em; white-space: pre-wrap; font-family: "Courier New", Consolas, monospace; font-size: 12px; overflow-x: auto; }
	.error { background: #fff0f0; border: 1px solid #e0a0a0; color: #800; padding: 0.7em; white-space: pre-wrap; font-family: "Courier New", Consolas, monospace; font-size: 12px; margin-top: 0.5em; }
	.timing { background: #f0f8f0; border: 1px solid #a0c8a0; padding: 0.7em; margin: 0.5em 0; font-size: 13px; }
	.timing strong { color: #2a5f2a; }
	.footer { margin-top: 2em; padding-top: 1em; border-top: 1px solid #ddd; font-size: 12px; color: #666; }
	code { background: #f4f4f4; padding: 0.1em 0.3em; border-radius: 2px; }
	.note { color: #666; font-size: 12px; font-weight: normal; }
</style>
</head>
<body>

<h1>cfTOML live demo</h1>
<div>Parse TOML to CFML, or serialize CFML to TOML. Each conversion is timed once, then re-run in a 1 second loop to show throughput.</div>

<cfoutput>
<div class="platform">
	<strong>Platform:</strong> #engineInfo.platform# #engineInfo.version#
	&nbsp;|&nbsp; <strong>Java:</strong> #engineInfo.java#
	&nbsp;|&nbsp; <strong>cfTOML:</strong> 1.2.0
</div>
</cfoutput>

<form method="post" action="demo.cfm">

<div class="spec-row">
	<strong>TOML spec mode:</strong>
	<cfoutput>
	<label><input type="radio" name="spec_mode" value="1.0.0" <cfif spec_mode eq "1.0.0">checked</cfif>> 1.0.0 (default)</label>
	<label><input type="radio" name="spec_mode" value="1.1.0" <cfif spec_mode eq "1.1.0">checked</cfif>> 1.1.0 (opt-in)</label>
	</cfoutput>
	<span class="note">Samples prefixed <code>11_</code> need 1.1.0 mode.</span>
</div>

<div class="cols">

<div class="col">
<h2>TOML to CFML</h2>

<label for="toml_sample">Sample payload (selecting one auto-fills the textarea):</label>
<select id="toml_sample" name="toml_sample" onchange="autoFillToml(this.value)">
	<cfoutput>
	<optgroup label="TOML 1.0.0">
		<cfloop list="basic,datetime,arrays,inline,aot,numbers,strings" index="skey">
			<option value="#skey#" <cfif skey eq toml_sample>selected</cfif>>#skey#</option>
		</cfloop>
	</optgroup>
	<optgroup label="TOML 1.1.0 (requires 1.1.0 spec mode)">
		<cfloop list="11_multiline,11_digitkeys,11_noseconds,11_eescape" index="skey">
			<option value="#skey#" <cfif skey eq toml_sample>selected</cfif>>#skey#</option>
		</cfloop>
	</optgroup>
	</cfoutput>
</select>

<label for="toml_input">TOML input (editable):</label>
<cfoutput><textarea id="toml_input" name="toml_input" rows="14" placeholder="paste TOML here">#encodeforhtml(toml_input)#</textarea></cfoutput>

<button type="submit" name="action" value="parse">Parse to CFML</button>

<cfif result_action eq "parse">
	<cfif len(result_error)>
		<cfoutput><div class="error">#encodeforhtml(result_error)#</div></cfoutput>
	<cfelse>
		<cfoutput>
		<div class="timing">
			<strong>Single conversion:</strong> #result_single_ms# ms
			&nbsp;|&nbsp; <strong>Throughput (1s):</strong> #numberFormat(result_throughput)# conversions/sec
		</div>
		<label>Parsed CFML result (as JSON for display):</label>
		<div class="result">#encodeforhtml(result_data)#</div>
		</cfoutput>
		<label>cf_dump (ColdFusion object):</label>
		<cftry>
			<cf_dump var="#result_parsed#" pre=1>
			<cfcatch type="any"><div class="result"><a href="https://github.com/kwaschny/cf_dump" rel="nofollow noopener noreferrer">cf_dump</a> not installed</div></cfcatch>
		</cftry>
	</cfif>
</cfif>
</div>

<div class="col">
<h2>CFML to TOML</h2>

<label for="cfml_sample">Pre-built CFML sample (not editable):</label>
<cfoutput>
<select id="cfml_sample" name="cfml_sample" onchange="toggleJsonInput(this.value)">
	<option value="simple"   <cfif cfml_sample eq "simple">selected</cfif>>simple - flat scalars</option>
	<option value="nested"   <cfif cfml_sample eq "nested">selected</cfif>>nested - two table headers</option>
	<option value="withdate" <cfif cfml_sample eq "withdate">selected</cfif>>with datetime (now())</option>
	<option value="arrays"   <cfif cfml_sample eq "arrays">selected</cfif>>arrays - including mixed types</option>
	<option value="aot"      <cfif cfml_sample eq "aot">selected</cfif>>array of tables - 2 products</option>
	<option value="deep"     <cfif cfml_sample eq "deep">selected</cfif>>deep - nested headers and meta</option>
	<option value="json"     <cfif cfml_sample eq "json">selected</cfif>>from JSON input (below)</option>
</select>
</cfoutput>

<label for="json_input">JSON input (enabled only when "from JSON input" is selected):</label>
<cfoutput><textarea id="json_input" name="json_input" rows="6" placeholder='{"key": "value"}' <cfif cfml_sample neq "json">disabled</cfif>>#encodeforhtml(json_input)#</textarea></cfoutput>

<button type="submit" name="action" value="emit">Serialize to TOML</button>

<cfif result_action eq "emit">
	<cfif len(result_error)>
		<cfoutput><div class="error">#encodeforhtml(result_error)#</div></cfoutput>
	<cfelse>
		<cfoutput>
		<div class="timing">
			<strong>Single conversion:</strong> #result_single_ms# ms
			&nbsp;|&nbsp; <strong>Throughput (1s):</strong> #numberFormat(result_throughput)# conversions/sec
		</div>
		<label>cf_dump (ColdFusion object):</label>
		<cftry>
			<cf_dump var="#cfml_data#" pre=1>
			<cfcatch type="any"><div class="result"><a href="https://github.com/kwaschny/cf_dump" rel="nofollow noopener noreferrer">cf_dump</a> not installed</div></cfcatch>
		</cftry>
		<label>Serialized TOML output:</label>
		<div class="result">#encodeforhtml(result_data)#</div>
		</cfoutput>
	</cfif>
</cfif>
</div>

</div>

</form>

<div class="footer">
	cfTOML is MIT-licensed. Source and docs: <a href="https://github.com/JamoCA/cfTOML">github.com/JamoCA/cfTOML</a>.
	Unit suite: 616 tests. Conformance against BurntSushi/toml-test: 1.0.0 132/187 + 258/371, 1.1.0 138/187 + 245/361.
</div>

<cfoutput>
<script>
var tomlSamples = {
<cfset jsItems = []>
<cfloop collection="#samples_toml#" item="skey">
	<cfset arrayappend(jsItems, serializeJSON(skey) & ": " & serializeJSON(samples_toml[skey]))>
</cfloop>
#arraytolist(jsItems, ",")#
};
function autoFillToml(name) {
	if (tomlSamples.hasOwnProperty(name)) {
		document.getElementById('toml_input').value = tomlSamples[name];
	}
}
function toggleJsonInput(name) {
	var ta = document.getElementById('json_input');
	if (!ta) { return; }
	ta.disabled = (name !== 'json');
}
document.addEventListener('DOMContentLoaded', function() {
	var sel = document.getElementById('cfml_sample');
	if (sel) { toggleJsonInput(sel.value); }
});
</script>
</cfoutput>

</body>
</html>
</cfprocessingdirective>
