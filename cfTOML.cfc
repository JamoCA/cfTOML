component hint="Pure CFML TOML 1.0.0 parser/emitter" {

	variables.options = [:];
	variables.engine = "";
	variables.jTrue = javacast("boolean", 1);
	variables.jFalse = javacast("boolean", 0);
	variables.csOrderedType = "";  // structNew() type string for an ordered case-sensitive struct on this engine, or "" if unsupported (CF2016/2018, etc.)

	// ----- public API -----

	public cfTOML function init(struct options = [:]) hint="Initialize with default options merged over built-in defaults." {
		variables.options = mergeWithDefaults(arguments.options);
		variables.engine = detectEngine();
		variables.csOrderedType = detectCaseSensitiveOrderedType();
		return this;
	}

	public struct function tomlDeserialize(required string toml, struct options = [:]) hint="Parse a TOML string and return an ordered struct." {
		var opts = mergeOptions(arguments.options);
		var tokens = tokenize(arguments.toml, opts.spec);
		return parseTokens(tokens, opts);
	}

	public struct function tomlReadFile(required string path, struct options = [:]) hint="Read a TOML file and parse it." {
		if (!fileExists(arguments.path)) {
			throw(type="cfTOML.ParseError", message="TOML file not found: #arguments.path#");
		}
		var content = fileRead(arguments.path, "UTF-8");
		return tomlDeserialize(content, arguments.options);
	}

	public string function tomlSerialize(required struct data, struct options = [:]) hint="Serialize an ordered struct to a TOML 1.0 string." {
		var opts = mergeOptions(arguments.options);
		return emitTable(arguments.data, [], opts, 0);
	}

	public void function tomlWriteFile(required string path, required struct data, struct options = [:]) hint="Serialize a struct and write to a UTF-8 file at the given path." {
		var content = tomlSerialize(arguments.data, arguments.options);
		// Write as raw bytes to avoid engine-specific text-mode side effects (CF2025 appends a trailing CRLF
		// when fileWrite is called with a string + charset, which corrupts the serialized output).
		fileWrite(arguments.path, charsetDecode(content, "UTF-8"));
	}

	// ----- options merging -----

	private struct function mergeWithDefaults(required struct callOptions) hint="Merge call-time options over built-in defaults." {
		var defaults = [
			"strict": variables.jTrue,
			"dateTimeReturn": "cfdate",
			"int64Mode": "double",
			"indent": "",
			"inlineThreshold": 0,
			"sortKeys": variables.jFalse,
			"queryAsArrayOfTables": variables.jFalse,
			"onNull": "skip",
			"spec": "1.0.0",
			"inlineMultiline": variables.jFalse,
			"useExtendedEscapes": variables.jFalse,
			"omitZeroSeconds": variables.jFalse,
			"useBareDigitKeys": variables.jFalse
		];
		structAppend(defaults, arguments.callOptions, true);
		validateSpec(defaults.spec);
		validateEmitterKnobs(defaults);
		return defaults;
	}

	private void function validateSpec(required string spec) hint="Throw cfTOML.ConfigError if spec is not a recognized TOML version." {
		if (arguments.spec neq "1.0.0" && arguments.spec neq "1.1.0") {
			throw(type="cfTOML.ConfigError", message="Unknown spec '#arguments.spec#'. Supported: '1.0.0', '1.1.0'.");
		}
	}

	private void function validateEmitterKnobs(required struct opts) hint="Throw cfTOML.ConfigError when a 1.1.0-only emitter knob is set while spec=1.0.0." {
		if (arguments.opts.spec neq "1.0.0") {
			return;
		}
		var gated = ["inlineMultiline", "useExtendedEscapes", "omitZeroSeconds", "useBareDigitKeys"];
		for (var k in gated) {
			if (arguments.opts[k]) {
				throw(type="cfTOML.ConfigError", message="Option '#k#' requires spec='1.1.0' but spec='1.0.0' is in effect. Pass { spec: '1.1.0' } to enable, or remove the option.");
			}
		}
	}

	private struct function mergeOptions(struct callOptions) hint="Merge call-time options over instance defaults from init()." {
		var result = duplicate(variables.options);
		if (structcount(arguments.callOptions)) {
			structAppend(result, arguments.callOptions, true);
		}
		validateSpec(result.spec);
		validateEmitterKnobs(result);
		return result;
	}

	// ----- tokenizer (Phase 1) -----

	private boolean function isForbiddenStringControlChar(required string c) hint="TOML forbids these control chars unescaped inside any string or comment: U+0000..U+0008, U+000B, U+000C, U+000E..U+001F, U+007F. Tab (U+0009), LF (U+000A), and CR (U+000D) are NOT flagged here; callers handle them per context (single-line strings reject LF/CR as 'unterminated', multi-line strings allow LF and CRLF but reject bare CR via separate logic)." {
		var code = asc(arguments.c);
		if (code lt 32) {
			return (code neq 9 && code neq 10 && code neq 13);
		}
		return code eq 127;
	}

	public array function tokenize(required string source, string spec = "1.0.0") hint="Lex a TOML source string into a token array. Exposed as public for testability. spec='1.1.0' enables optional datetime seconds." {
		var tokens = [];
		var srcLen = len(arguments.source);
		if (!srcLen) {
			return tokens;
		}
		var pos = 1;
		var line = 1;
		var col = 1;
		var lineStart = variables.jTrue;
		var bracketDepth = 0;
		var ch = "";

		while (pos lte srcLen) {
			ch = mid(arguments.source, pos, 1);

			// Skip non-newline whitespace
			if (ch eq " " || ch eq chr(9)) {
				pos++;
				col++;
				continue;
			}

			// CRLF -> single NEWLINE
			if (ch eq chr(13) && pos lt srcLen && mid(arguments.source, pos + 1, 1) eq chr(10)) {
				arrayappend(tokens, ["type": "NEWLINE", "value": chr(10), "line": line, "col": col]);
				pos += 2;
				line++;
				col = 1;
				lineStart = variables.jTrue;
				continue;
			}

			// LF
			if (ch eq chr(10)) {
				arrayappend(tokens, ["type": "NEWLINE", "value": chr(10), "line": line, "col": col]);
				pos++;
				line++;
				col = 1;
				lineStart = variables.jTrue;
				continue;
			}

			// COMMENT: # through end of line
			if (ch eq "##") {
				var startCol = col;
				var startPos = pos;
				while (pos lte srcLen) {
					var cmtCh = mid(arguments.source, pos, 1);
					if (cmtCh eq chr(10) || cmtCh eq chr(13)) { break; }
					if (isForbiddenStringControlChar(cmtCh)) {
						throw(type="cfTOML.ParseError", message="Control character U+#numberFormat(asc(cmtCh), '0000')# not allowed in comment at line #line#, column #col#");
					}
					pos++;
					col++;
				}
				arrayappend(tokens, ["type": "COMMENT", "value": mid(arguments.source, startPos, pos - startPos), "line": line, "col": startCol]);
				lineStart = variables.jFalse;
				continue;
			}

			// ARRAY_OPEN: [ - any context except line-start at depth 0 (those are TABLE_HEADER / ARRAY_TABLE_HEADER, checked next)
			if (ch eq "[" && (lineStart eq variables.jFalse || bracketDepth gt 0)) {
				arrayappend(tokens, ["type": "ARRAY_OPEN", "value": "[", "line": line, "col": col]);
				pos++;
				col++;
				bracketDepth++;
				lineStart = variables.jFalse;
				continue;
			}

			// ARRAY_TABLE_HEADER: [[name.dotted]] at line-start only
			if (ch eq "[" && lineStart && bracketDepth eq 0 && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq "[") {
				var startCol = col;
				var startLine = line;
				pos += 2;
				col += 2;
				var buf = "";
				var closed = variables.jFalse;
				while (pos lte srcLen) {
					var c = mid(arguments.source, pos, 1);
					if (c eq chr(10) || c eq chr(13)) {
						throw(type="cfTOML.ParseError", message="Unterminated array-of-tables header at line #startLine#, column #startCol#");
					}
					if (c eq "]" && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq "]") {
						pos += 2;
						col += 2;
						arrayappend(tokens, ["type": "ARRAY_TABLE_HEADER", "value": buf, "line": startLine, "col": startCol]);
						closed = variables.jTrue;
						lineStart = variables.jFalse;
						break;
					}
					buf &= c;
					pos++;
					col++;
				}
				if (!closed) {
					throw(type="cfTOML.ParseError", message="Unterminated array-of-tables header at line #startLine#, column #startCol#");
				}
				continue;
			}

			// TABLE_HEADER: [name.dotted] at line-start only
			if (ch eq "[" && lineStart && bracketDepth eq 0) {
				var startCol = col;
				var startLine = line;
				pos++;
				col++;
				var buf = "";
				var closed = variables.jFalse;
				while (pos lte srcLen) {
					var c = mid(arguments.source, pos, 1);
					if (c eq chr(10) || c eq chr(13)) {
						throw(type="cfTOML.ParseError", message="Unterminated table header at line #startLine#, column #startCol#");
					}
					if (c eq "]") {
						pos++;
						col++;
						arrayappend(tokens, ["type": "TABLE_HEADER", "value": buf, "line": startLine, "col": startCol]);
						closed = variables.jTrue;
						lineStart = variables.jFalse;
						break;
					}
					buf &= c;
					pos++;
					col++;
				}
				if (!closed) {
					throw(type="cfTOML.ParseError", message="Unterminated table header at line #startLine#, column #startCol#");
				}
				continue;
			}

			// BOOL: 'true' or 'false', case-sensitive, requires word boundary.
			// Case-sensitive comparison via compare() because CFML's eq is case-insensitive,
			// which would otherwise let "True" or "TRUE" slip through.
			if (ch eq "t" || ch eq "f") {
				var rest = mid(arguments.source, pos, srcLen - pos + 1);
				var matchedWord = "";
				if (compare(left(rest, 4), "true") eq 0) {
					matchedWord = "true";
				} else if (compare(left(rest, 5), "false") eq 0) {
					matchedWord = "false";
				}
				if (len(matchedWord)) {
					var lookahead = (pos + len(matchedWord) gt srcLen) ? "" : mid(arguments.source, pos + len(matchedWord), 1);
					if (!len(lookahead) || !reFind("[A-Za-z0-9_-]", lookahead)) {
						arrayappend(tokens, ["type": "BOOL", "value": matchedWord, "line": line, "col": col]);
						pos += len(matchedWord);
						col += len(matchedWord);
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// Hex INT: 0x[hex_]+
			if (ch eq "0" && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq "x") {
				var matchResult = reFind("^0x[0-9A-Fa-f](_?[0-9A-Fa-f])*", mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					var lookahead = (pos + matchResult.len[1] gt srcLen) ? "" : mid(arguments.source, pos + matchResult.len[1], 1);
					if (!len(lookahead) || !reFind("[A-Za-z0-9_]", lookahead)) {
						arrayappend(tokens, ["type": "INT", "value": lexeme, "line": line, "col": col]);
						pos += matchResult.len[1];
						col += matchResult.len[1];
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// Octal INT: 0o[0-7_]+
			if (ch eq "0" && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq "o") {
				var matchResult = reFind("^0o[0-7](_?[0-7])*", mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					var lookahead = (pos + matchResult.len[1] gt srcLen) ? "" : mid(arguments.source, pos + matchResult.len[1], 1);
					if (!len(lookahead) || !reFind("[A-Za-z0-9_]", lookahead)) {
						arrayappend(tokens, ["type": "INT", "value": lexeme, "line": line, "col": col]);
						pos += matchResult.len[1];
						col += matchResult.len[1];
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// Binary INT: 0b[01_]+
			if (ch eq "0" && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq "b") {
				var matchResult = reFind("^0b[01](_?[01])*", mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					var lookahead = (pos + matchResult.len[1] gt srcLen) ? "" : mid(arguments.source, pos + matchResult.len[1], 1);
					if (!len(lookahead) || !reFind("[A-Za-z0-9_]", lookahead)) {
						arrayappend(tokens, ["type": "INT", "value": lexeme, "line": line, "col": col]);
						pos += matchResult.len[1];
						col += matchResult.len[1];
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// TIME_LOCAL: HH:MM:SS[.frac] (1.0.0) or HH:MM[:SS][.frac] (1.1.0)
			if (reFind("[0-9]", ch)) {
				var timeLocalPattern = (arguments.spec eq "1.1.0")
					? "^[0-9]{2}:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?"
					: "^[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?";
				var matchResult = reFind(timeLocalPattern, mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					var lookahead = (pos + matchResult.len[1] gt srcLen) ? "" : mid(arguments.source, pos + matchResult.len[1], 1);
					// Lookahead must NOT be another digit (would extend the seconds part)
					if (!len(lookahead) || !reFind("[0-9]", lookahead)) {
						arrayappend(tokens, ["type": "TIME_LOCAL", "value": lexeme, "line": line, "col": col]);
						pos += matchResult.len[1];
						col += matchResult.len[1];
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// DATETIME_OFFSET: YYYY-MM-DD[Tt ]HH:MM:SS[.frac](Z|z|+HH:MM|-HH:MM) (1.0.0)
			//                  or YYYY-MM-DD[Tt ]HH:MM[:SS][.frac](Z|...) (1.1.0)
			if (reFind("[0-9]", ch)) {
				var dtOffsetPattern = (arguments.spec eq "1.1.0")
					? "^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?(Z|z|[+\-][0-9]{2}:[0-9]{2})"
					: "^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|z|[+\-][0-9]{2}:[0-9]{2})";
				var matchResult = reFind(dtOffsetPattern, mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					arrayappend(tokens, ["type": "DATETIME_OFFSET", "value": lexeme, "line": line, "col": col]);
					pos += matchResult.len[1];
					col += matchResult.len[1];
					lineStart = variables.jFalse;
					continue;
				}
			}

			// DATETIME_LOCAL: YYYY-MM-DD[Tt ]HH:MM:SS[.frac] (no timezone, 1.0.0)
			//                 or YYYY-MM-DD[Tt ]HH:MM[:SS][.frac] (1.1.0)
			if (reFind("[0-9]", ch)) {
				var dtLocalPattern = (arguments.spec eq "1.1.0")
					? "^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}(:[0-9]{2})?(\.[0-9]+)?"
					: "^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?";
				var matchResult = reFind(dtLocalPattern, mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					// DATETIME_OFFSET is tried before this branch; if we're here, no offset suffix is present.
					arrayappend(tokens, ["type": "DATETIME_LOCAL", "value": lexeme, "line": line, "col": col]);
					pos += matchResult.len[1];
					col += matchResult.len[1];
					lineStart = variables.jFalse;
					continue;
				}
			}

			// DATE_LOCAL: YYYY-MM-DD
			if (reFind("[0-9]", ch)) {
				var matchResult = reFind("^[0-9]{4}-[0-9]{2}-[0-9]{2}", mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					var lookahead = (pos + matchResult.len[1] gt srcLen) ? "" : mid(arguments.source, pos + matchResult.len[1], 1);
					// Only emit DATE_LOCAL if lookahead is whitespace/newline/EOF/punctuation.
					// If lookahead is T/t/space, it's a datetime (handled by later branch in Task 12+); skip here.
					if (!len(lookahead) || lookahead eq " " || lookahead eq chr(9) || lookahead eq chr(10) || lookahead eq chr(13) || lookahead eq "##" || lookahead eq "," || lookahead eq "]" || lookahead eq "}") {
						arrayappend(tokens, ["type": "DATE_LOCAL", "value": lexeme, "line": line, "col": col]);
						pos += matchResult.len[1];
						col += matchResult.len[1];
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// Special floats: inf | +inf | -inf | nan | +nan | -nan (case-sensitive lowercase, word boundary required)
			if (ch eq "i" || ch eq "n" || ch eq "+" || ch eq "-") {
				var rest = mid(arguments.source, pos, srcLen - pos + 1);
				var matchedWord = "";
				if (compare(left(rest, 4), "+inf") eq 0 || compare(left(rest, 4), "-inf") eq 0) {
					matchedWord = left(rest, 4);
				} else if (compare(left(rest, 3), "inf") eq 0) {
					matchedWord = "inf";
				} else if (compare(left(rest, 4), "+nan") eq 0 || compare(left(rest, 4), "-nan") eq 0) {
					matchedWord = left(rest, 4);
				} else if (compare(left(rest, 3), "nan") eq 0) {
					matchedWord = "nan";
				}
				if (len(matchedWord)) {
					var lookahead = (pos + len(matchedWord) gt srcLen) ? "" : mid(arguments.source, pos + len(matchedWord), 1);
					if (!len(lookahead) || !reFind("[A-Za-z0-9_-]", lookahead)) {
						arrayappend(tokens, ["type": "FLOAT", "value": matchedWord, "line": line, "col": col]);
						pos += len(matchedWord);
						col += len(matchedWord);
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// FLOAT: [+-]?\d(_?\d)* with at least one of (\.\d(_?\d)*) or ([eE][+-]?\d(_?\d)*)
			if (ch eq "+" || ch eq "-" || reFind("[0-9]", ch)) {
				// Try fraction-with-optional-exponent first (longer pattern)
				var matchResult = reFind("^[+\-]?[0-9](_?[0-9])*\.[0-9](_?[0-9])*([eE][+\-]?[0-9](_?[0-9])*)?", mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] eq 0) {
					// Try exponent-only form (no fraction)
					matchResult = reFind("^[+\-]?[0-9](_?[0-9])*[eE][+\-]?[0-9](_?[0-9])*", mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				}
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					var lookahead = (pos + matchResult.len[1] gt srcLen) ? "" : mid(arguments.source, pos + matchResult.len[1], 1);
					if (!len(lookahead) || !reFind("[A-Za-z0-9_]", lookahead)) {
						// Reject leading-zero floats: 01.5, +01.5, etc. The integer part can be a single 0
						// (as in 0.5), but multi-digit integer parts cannot start with 0.
						var floatBody = lexeme;
						if (left(floatBody, 1) eq "+" || left(floatBody, 1) eq "-") {
							floatBody = mid(floatBody, 2, len(floatBody) - 1);
						}
						var intPart = listFirst(replace(floatBody, "e", ".", "all"), ".");
						if (len(intPart) gt 1 && left(intPart, 1) eq "0") {
							throw(type="cfTOML.ParseError", message="Leading zero not allowed in float integer part of '#lexeme#' at line #line#, column #col#");
						}
						arrayappend(tokens, ["type": "FLOAT", "value": lexeme, "line": line, "col": col]);
						pos += matchResult.len[1];
						col += matchResult.len[1];
						lineStart = variables.jFalse;
						continue;
					}
				}
			}

			// INT: optional sign + digits with optional underscores between digits
			// Pattern: [+-]?[0-9](_?[0-9])*
			if (ch eq "+" || ch eq "-" || reFind("[0-9]", ch)) {
				var matchResult = reFind("^[+\-]?[0-9](_?[0-9])*", mid(arguments.source, pos, srcLen - pos + 1), 1, true);
				if (matchResult.len[1] gt 0) {
					var lexeme = mid(arguments.source, pos, matchResult.len[1]);
					var lookahead = (pos + matchResult.len[1] gt srcLen) ? "" : mid(arguments.source, pos + matchResult.len[1], 1);
					// Lookahead must NOT be a bare-key continuation char ([A-Za-z0-9_-]); a trailing dash
					// means the digits are part of a bare key like `2000-datetime`, not an INT value.
					if (!len(lookahead) || !reFind("[A-Za-z0-9_\-]", lookahead)) {
						// Leading-zero rejection happens in parseIntegerLexeme (value-side) so that
						// all-digit bare keys like `000111 = "x"` still tokenize - the parser will route
						// the token to isKeySegmentToken which accepts it, never reaching the value path.
						arrayappend(tokens, ["type": "INT", "value": lexeme, "line": line, "col": col]);
						pos += matchResult.len[1];
						col += matchResult.len[1];
						lineStart = variables.jFalse;
						continue;
					}
				}
				// '+' without digits has no valid TOML interpretation (bare keys cannot start with '+').
				// '-' falls through: '-' alone or '-foo' is a valid bare key.
				if (ch eq "+") {
					throw(type="cfTOML.ParseError", message="Unexpected '+' at line #line#, column #col#");
				}
			}

			// Bare key: [A-Za-z0-9_-]+ (1.0.0) or [A-Za-z0-9_-] | non-ASCII (1.1.0).
			// 1.1.0 widens the bare-key class to allow Unicode letters/digits and selected punctuation.
			// The conservative approximation here treats any non-ASCII byte as a bare-key char in 1.1.0 mode,
			// which is a superset of the spec's explicit per-range list but lets the common cases through.
			var bareKeyPattern = (arguments.spec eq "1.1.0") ? "[A-Za-z0-9_\-]|[^\x00-\x7F]" : "[A-Za-z0-9_\-]";
			if (reFind(bareKeyPattern, ch)) {
				var startCol = col;
				var startPos = pos;
				while (pos lte srcLen && reFind(bareKeyPattern, mid(arguments.source, pos, 1))) {
					pos++;
					col++;
				}
				arrayappend(tokens, ["type": "KEY", "value": mid(arguments.source, startPos, pos - startPos), "line": line, "col": startCol]);
				lineStart = variables.jFalse;
				continue;
			}

			// ARRAY_CLOSE: ]
			if (ch eq "]") {
				arrayappend(tokens, ["type": "ARRAY_CLOSE", "value": "]", "line": line, "col": col]);
				pos++;
				col++;
				if (bracketDepth gt 0) {
					bracketDepth--;
				}
				lineStart = variables.jFalse;
				continue;
			}

			// DOT
			if (ch eq ".") {
				arrayappend(tokens, ["type": "DOT", "value": ".", "line": line, "col": col]);
				pos++;
				col++;
				lineStart = variables.jFalse;
				continue;
			}

			// EQUALS
			if (ch eq "=") {
				arrayappend(tokens, ["type": "EQUALS", "value": "=", "line": line, "col": col]);
				pos++;
				col++;
				lineStart = variables.jFalse;
				continue;
			}

			// COMMA: ,
			if (ch eq ",") {
				arrayappend(tokens, ["type": "COMMA", "value": ",", "line": line, "col": col]);
				pos++;
				col++;
				lineStart = variables.jFalse;
				continue;
			}

			// INLINE_OPEN: {
			if (ch eq "{") {
				arrayappend(tokens, ["type": "INLINE_OPEN", "value": "{", "line": line, "col": col]);
				pos++;
				col++;
				bracketDepth++;
				lineStart = variables.jFalse;
				continue;
			}

			// INLINE_CLOSE: }
			if (ch eq "}") {
				arrayappend(tokens, ["type": "INLINE_CLOSE", "value": "}", "line": line, "col": col]);
				pos++;
				col++;
				if (bracketDepth gt 0) {
					bracketDepth--;
				}
				lineStart = variables.jFalse;
				continue;
			}

			// STRING_ML_BASIC: """...""" with first-newline trim and raw escape passthrough
			// (Falls through to STRING_BASIC for single double-quote.)
			if (ch eq chr(34)) {
				// Check for triple-quote opening
				if (pos + 2 lte srcLen && mid(arguments.source, pos + 1, 1) eq chr(34) && mid(arguments.source, pos + 2, 1) eq chr(34)) {
					var startCol = col;
					var startLine = line;
					pos += 3;
					col += 3;
					// Trim a single immediately-following newline (LF or CRLF)
					if (pos lte srcLen) {
						var first = mid(arguments.source, pos, 1);
						if (first eq chr(13) && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq chr(10)) {
							pos += 2;
							line++;
							col = 1;
						} else if (first eq chr(10)) {
							pos++;
							line++;
							col = 1;
						}
					}
					var buf = "";
					var closed = variables.jFalse;
					while (pos lte srcLen) {
						// Closing triple-quote: at least three consecutive double-quotes.
						// Allow up to 2 leading content quotes before the closing 3, per TOML 1.0 spec.
						if (mid(arguments.source, pos, 1) eq chr(34)
							&& pos + 2 lte srcLen
							&& mid(arguments.source, pos + 1, 1) eq chr(34)
							&& mid(arguments.source, pos + 2, 1) eq chr(34)) {
							// Count consecutive quotes from pos to determine content trailing quotes
							var quoteRun = 0;
							while (pos + quoteRun lte srcLen && mid(arguments.source, pos + quoteRun, 1) eq chr(34)) {
								quoteRun++;
							}
							if (quoteRun gt 5) {
								throw(type="cfTOML.ParseError", message="ML basic string has too many trailing quotes (#quoteRun#) at line #line#, column #col#");
							}
							// quoteRun is 3, 4, or 5. Closing is always the LAST 3; the first (quoteRun - 3) are content.
							var contentQuotes = quoteRun - 3;
							if (contentQuotes gt 0) {
								buf &= repeatString(chr(34), contentQuotes);
							}
							pos += quoteRun;
							col += quoteRun;
							arrayappend(tokens, ["type": "STRING_ML_BASIC", "value": buf, "line": startLine, "col": startCol]);
							closed = variables.jTrue;
							break;
						}
						var c = mid(arguments.source, pos, 1);
						if (c eq "\") {
							if (pos + 1 gt srcLen) {
								throw(type="cfTOML.ParseError", message="Unterminated escape in ML basic string at line #line#, column #col#");
							}
							buf &= c & mid(arguments.source, pos + 1, 1);
							pos += 2;
							col += 2;
							continue;
						}
						if (c eq chr(13) && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq chr(10)) {
							// Normalize CRLF to LF inside content
							buf &= chr(10);
							pos += 2;
							line++;
							col = 1;
							continue;
						}
						if (c eq chr(13)) {
							// Bare CR (not part of CRLF) is forbidden in ML basic strings.
							throw(type="cfTOML.ParseError", message="Bare carriage return (U+000D) not allowed in multi-line basic string at line #line#, column #col#");
						}
						if (c eq chr(10)) {
							buf &= c;
							pos++;
							line++;
							col = 1;
							continue;
						}
						if (isForbiddenStringControlChar(c)) {
							throw(type="cfTOML.ParseError", message="Control character U+#numberFormat(asc(c), '0000')# not allowed in multi-line basic string at line #line#, column #col#");
						}
						buf &= c;
						pos++;
						col++;
					}
					if (!closed) {
						throw(type="cfTOML.ParseError", message="Unterminated ML basic string at line #startLine#, column #startCol#");
					}
					lineStart = variables.jFalse;
					continue;
				}

				// Single-quote STRING_BASIC (Phase 1 behavior)
				var startCol = col;
				pos++;
				col++;
				var buf = "";
				var closed = variables.jFalse;
				while (pos lte srcLen) {
					var c = mid(arguments.source, pos, 1);
					if (c eq chr(10) || c eq chr(13)) {
						throw(type="cfTOML.ParseError", message="Unterminated basic string at line #line#, column #startCol#");
					}
					if (c eq "\") {
						if (pos + 1 gt srcLen) {
							throw(type="cfTOML.ParseError", message="Unterminated basic string escape at line #line#, column #col#");
						}
						buf &= c & mid(arguments.source, pos + 1, 1);
						pos += 2;
						col += 2;
						continue;
					}
					if (c eq chr(34)) {
						pos++;
						col++;
						arrayappend(tokens, ["type": "STRING_BASIC", "value": buf, "line": line, "col": startCol]);
						closed = variables.jTrue;
						break;
					}
					if (isForbiddenStringControlChar(c)) {
						throw(type="cfTOML.ParseError", message="Control character U+#numberFormat(asc(c), '0000')# not allowed in basic string at line #line#, column #col#");
					}
					buf &= c;
					pos++;
					col++;
				}
				if (!closed) {
					throw(type="cfTOML.ParseError", message="Unterminated basic string at line #line#, column #startCol#");
				}
				lineStart = variables.jFalse;
				continue;
			}

			// STRING_ML_LITERAL: '''...''' literal, no escape processing
			// (Falls through to STRING_LITERAL for single single-quote.)
			if (ch eq "'") {
				// Check for triple-quote opening
				if (pos + 2 lte srcLen && mid(arguments.source, pos + 1, 1) eq "'" && mid(arguments.source, pos + 2, 1) eq "'") {
					var startCol = col;
					var startLine = line;
					pos += 3;
					col += 3;
					// Trim a single immediately-following newline
					if (pos lte srcLen) {
						var first = mid(arguments.source, pos, 1);
						if (first eq chr(13) && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq chr(10)) {
							pos += 2;
							line++;
							col = 1;
						} else if (first eq chr(10)) {
							pos++;
							line++;
							col = 1;
						}
					}
					var buf = "";
					var closed = variables.jFalse;
					while (pos lte srcLen) {
						if (mid(arguments.source, pos, 1) eq "'"
							&& pos + 2 lte srcLen
							&& mid(arguments.source, pos + 1, 1) eq "'"
							&& mid(arguments.source, pos + 2, 1) eq "'") {
							var quoteRun = 0;
							while (pos + quoteRun lte srcLen && mid(arguments.source, pos + quoteRun, 1) eq "'") {
								quoteRun++;
							}
							if (quoteRun gt 5) {
								throw(type="cfTOML.ParseError", message="ML literal string has too many trailing quotes (#quoteRun#) at line #line#, column #col#");
							}
							var contentQuotes = quoteRun - 3;
							if (contentQuotes gt 0) {
								buf &= repeatString("'", contentQuotes);
							}
							pos += quoteRun;
							col += quoteRun;
							arrayappend(tokens, ["type": "STRING_ML_LITERAL", "value": buf, "line": startLine, "col": startCol]);
							closed = variables.jTrue;
							break;
						}
						var c = mid(arguments.source, pos, 1);
						if (c eq chr(13) && pos + 1 lte srcLen && mid(arguments.source, pos + 1, 1) eq chr(10)) {
							buf &= chr(10);
							pos += 2;
							line++;
							col = 1;
							continue;
						}
						if (c eq chr(13)) {
							// Bare CR (not part of CRLF) is forbidden in ML literal strings.
							throw(type="cfTOML.ParseError", message="Bare carriage return (U+000D) not allowed in multi-line literal string at line #line#, column #col#");
						}
						if (c eq chr(10)) {
							buf &= c;
							pos++;
							line++;
							col = 1;
							continue;
						}
						if (isForbiddenStringControlChar(c)) {
							throw(type="cfTOML.ParseError", message="Control character U+#numberFormat(asc(c), '0000')# not allowed in multi-line literal string at line #line#, column #col#");
						}
						buf &= c;
						pos++;
						col++;
					}
					if (!closed) {
						throw(type="cfTOML.ParseError", message="Unterminated ML literal string at line #startLine#, column #startCol#");
					}
					lineStart = variables.jFalse;
					continue;
				}

				// Single-quote STRING_LITERAL (Task 1 behavior)
				var startCol = col;
				pos++;
				col++;
				var buf = "";
				var closed = variables.jFalse;
				while (pos lte srcLen) {
					var c = mid(arguments.source, pos, 1);
					if (c eq chr(10) || c eq chr(13)) {
						throw(type="cfTOML.ParseError", message="Unterminated literal string at line #line#, column #startCol#");
					}
					if (c eq "'") {
						pos++;
						col++;
						arrayappend(tokens, ["type": "STRING_LITERAL", "value": buf, "line": line, "col": startCol]);
						closed = variables.jTrue;
						break;
					}
					if (isForbiddenStringControlChar(c)) {
						throw(type="cfTOML.ParseError", message="Control character U+#numberFormat(asc(c), '0000')# not allowed in literal string at line #line#, column #col#");
					}
					buf &= c;
					pos++;
					col++;
				}
				if (!closed) {
					throw(type="cfTOML.ParseError", message="Unterminated literal string at line #line#, column #startCol#");
				}
				lineStart = variables.jFalse;
				continue;
			}

			// Unrecognized: throw for now
			throw(type="cfTOML.ParseError", message="Unexpected character at line #line#, column #col#: '#ch#'");
		}

		return tokens;
	}

	// ----- parser -----

	public struct function parseTokens(required array tokens, required struct options) hint="Parse a token array into an ordered struct. Public for testability." {
		var root = newDataStruct();
		var currentTable = root;
		var explicitTables = newDataStruct();
		var inlineTables = newDataStruct();
		var aotArrays = newDataStruct();
		// Tables created implicitly as parent paths during KV-pair dotted-key resolution. Once a path is here,
		// a later TABLE_HEADER [X] for the same path is invalid (a "redefinition" via dotted keys).
		var dottedKeyTables = newDataStruct();
		var currentTablePath = "";
		var n = arraylen(arguments.tokens);
		if (!n) {
			return root;
		}
		var i = 1;
		while (i lte n) {
			var tok = arguments.tokens[i];
			// Skip standalone NEWLINE and COMMENT tokens between statements
			if (tok.type eq "NEWLINE" || tok.type eq "COMMENT") {
				i++;
				continue;
			}
			// Array-of-tables header: [[path]] appends a new ordered struct to the array at path
			if (tok.type eq "ARRAY_TABLE_HEADER") {
				var aotPath = trim(tok.value);
				// Check no prefix is an inline table
				var aotSegs = splitDottedPath(aotPath, arguments.options.spec);
				var aotPrefix = "";
				for (var seg in aotSegs) {
					aotPrefix = (len(aotPrefix) eq 0) ? seg : (aotPrefix & "." & seg);
					if (structkeyexists(inlineTables, aotPrefix)) {
						throw(type="cfTOML.TypeError", message="Cannot define [[#aotPath#]]: '#aotPrefix#' is an inline table");
					}
				}
				// Walk to the parent (all segments except last); the last segment is the array key
				var aotParent = root;
				if (arraylen(aotSegs) gt 1) {
					var parentParts = [];
					for (var k = 1; k lte arraylen(aotSegs) - 1; k++) {
						arrayappend(parentParts, aotSegs[k]);
					}
					aotParent = walkOrCreatePath(root, arraytolist(parentParts, "."), arguments.options.spec);
				}
				var leafName = aotSegs[arraylen(aotSegs)];
				if (!structkeyexists(aotParent, leafName)) {
					aotParent[leafName] = [];
				} else if (!isArray(aotParent[leafName])) {
					throw(type="cfTOML.TypeError", message="Cannot define [[#aotPath#]]: '#leafName#' is already a non-array value");
				} else if (!structkeyexists(aotArrays, aotPath)) {
					// Array exists but wasn't created by an AoT header - it's a static array
					throw(type="cfTOML.TypeError", message="Cannot define [[#aotPath#]]: '#leafName#' is a static array, not an array of tables");
				}
				aotArrays[aotPath] = variables.jTrue;
				// Append a new ordered struct and point currentTable at it
				var newEntry = newDataStruct();
				arrayappend(aotParent[leafName], newEntry);
				currentTable = aotParent[leafName][arraylen(aotParent[leafName])];
				currentTablePath = aotPath;
				// Clear any sub-table explicit-table records from the previous AoT element
				// so [aotPath.sub] can be re-defined under the new element
				var aotSubPrefix = aotPath & ".";
				var keysToRemove = [];
				for (var etKey in explicitTables) {
					if (left(etKey, len(aotSubPrefix)) eq aotSubPrefix) {
						arrayappend(keysToRemove, etKey);
					}
				}
				for (var etKey in keysToRemove) {
					structDelete(explicitTables, etKey);
				}
				// Also clear inlineTables entries for sub-paths so inline tables defined in one AoT element don't block dotted keys in the next
				var inlineKeysToRemove = [];
				for (var ikey in inlineTables) {
					if (left(ikey, len(aotSubPrefix)) eq aotSubPrefix) {
						arrayappend(inlineKeysToRemove, ikey);
					}
				}
				for (var rikey in inlineKeysToRemove) {
					structdelete(inlineTables, rikey);
				}
				i++;
				if (i lte n && arguments.tokens[i].type neq "NEWLINE" && arguments.tokens[i].type neq "COMMENT") {
					throw(type="cfTOML.ParseError", message="Expected newline or end-of-input after [[#aotPath#]] at line #tok.line#, column #tok.col# (got '#arguments.tokens[i].type#')");
				}
				continue;
			}
			// Table header: switch currentTable to the leaf of the dotted path; track explicit definitions
			if (tok.type eq "TABLE_HEADER") {
				var headerPath = trim(tok.value);
				if (structkeyexists(explicitTables, headerPath)) {
					throw(type="cfTOML.DuplicateKeyError", message="Table '#headerPath#' already defined at line #tok.line#, column #tok.col#");
				}
				if (structkeyexists(dottedKeyTables, headerPath)) {
					throw(type="cfTOML.DuplicateKeyError", message="Table '#headerPath#' was already created by dotted keys, cannot redefine at line #tok.line#, column #tok.col#");
				}
				// Check that no prefix of the header path is an inline table
				var headerSegs = splitDottedPath(headerPath, arguments.options.spec);
				var prefix = "";
				for (var seg in headerSegs) {
					prefix = (len(prefix) eq 0) ? seg : (prefix & "." & seg);
					if (structkeyexists(inlineTables, prefix)) {
						throw(type="cfTOML.TypeError", message="Cannot define [#headerPath#]: '#prefix#' is an inline table");
					}
				}
				// Check that the leaf path does NOT already point to an array (which would indicate AoT)
				// Walk path manually (without the AoT-step into-last-element) to detect this
				var checkNode = root;
				var walkPath = "";
				for (var k = 1; k lte arraylen(headerSegs) - 1; k++) {
					var s = headerSegs[k];
					walkPath = (k eq 1) ? s : (walkPath & "." & s);
					if (!structkeyexists(checkNode, s)) break;
					if (isArray(checkNode[s])) {
						// Walking through an array is only allowed when it's an array-of-tables (created by [[..]]).
						// A static array like `a = [{ b = 1 }]` is not extendable via [a.c] from outside.
						if (!structkeyexists(aotArrays, walkPath)) {
							throw(type="cfTOML.TypeError", message="Cannot define [#headerPath#]: '#walkPath#' is a static array, not an array-of-tables");
						}
						if (!arraylen(checkNode[s])) {
							throw(type="cfTOML.TypeError", message="Cannot walk into empty array '#s#' for header [#headerPath#]");
						}
						checkNode = checkNode[s][arraylen(checkNode[s])];
						continue;
					}
					if (!isStruct(checkNode[s])) {
						throw(type="cfTOML.TypeError", message="Header [#headerPath#] walks into non-table value at '#s#'");
					}
					checkNode = checkNode[s];
				}
				var leafName = headerSegs[arraylen(headerSegs)];
				if (structkeyexists(checkNode, leafName) && isArray(checkNode[leafName])) {
					throw(type="cfTOML.TypeError", message="Cannot define [#headerPath#]: '#leafName#' is already an array-of-tables");
				}
				explicitTables[headerPath] = variables.jTrue;
				currentTable = walkOrCreatePath(root, headerPath, arguments.options.spec);
				currentTablePath = headerPath;
				i++;
				if (i lte n && arguments.tokens[i].type neq "NEWLINE" && arguments.tokens[i].type neq "COMMENT") {
					throw(type="cfTOML.ParseError", message="Expected newline or end-of-input after [#headerPath#] at line #tok.line#, column #tok.col# (got '#arguments.tokens[i].type#')");
				}
				continue;
			}
			// KV pair: KEY (DOT KEY)* EQUALS <value> [NEWLINE]
			// Quoted strings (STRING_BASIC, STRING_LITERAL) and (in 1.1.0) all-digit INT tokens are also valid key segments.
			if (isKeySegmentToken(tok, arguments.options)) {
				var pathSegments = appendKeyTokenSegments([], tok, arguments.options);
				var j = i + 1;
				// Consume any DOT <key-segment> pairs
				while (j + 1 lte n
					&& arguments.tokens[j].type eq "DOT"
					&& isKeySegmentToken(arguments.tokens[j + 1], arguments.options)) {
					pathSegments = appendKeyTokenSegments(pathSegments, arguments.tokens[j + 1], arguments.options);
					j += 2;
				}
				if (j gt n || arguments.tokens[j].type neq "EQUALS") {
					throw(type="cfTOML.ParseError", message="Expected '=' after key path at line #tok.line#, column #tok.col#");
				}
				if (j + 1 gt n) {
					throw(type="cfTOML.ParseError", message="Missing value after '=' at line #arguments.tokens[j].line#");
				}
				var valTok = arguments.tokens[j + 1];
				var value = "";
				var nextIdx = 0;
				if (valTok.type eq "ARRAY_OPEN") {
					var arrayParse = parseArrayTokens(arguments.tokens, j + 1, arguments.options);
					value = arrayParse.value;
					nextIdx = arrayParse.endIdx;
				} else if (valTok.type eq "INLINE_OPEN") {
					var inlineParse = parseInlineTableTokens(arguments.tokens, j + 1, arguments.options);
					value = inlineParse.value;
					nextIdx = inlineParse.endIdx;
				} else {
					value = resolveScalarValue(valTok, arguments.options);
					nextIdx = j + 2;
				}
				// Place value at the leaf of pathSegments under currentTable
				var target = currentTable;
				if (arraylen(pathSegments) gt 1) {
					// All segments except the last are intermediate subtables
					var intermediate = [];
					for (var k = 1; k lte arraylen(pathSegments) - 1; k++) {
						arrayappend(intermediate, pathSegments[k]);
					}
					// Check each prefix of (currentTablePath + intermediate) against trackers, and
					// mark each prefix as a dotted-key-implicit table so a later [X] header is rejected.
					for (var k = 1; k lte arraylen(intermediate); k++) {
						var partial = [];
						for (var m = 1; m lte k; m++) {
							arrayappend(partial, intermediate[m]);
						}
						var partialFull = (len(currentTablePath) gt 0) ? (currentTablePath & "." & arraytolist(partial, ".")) : arraytolist(partial, ".");
						if (structkeyexists(inlineTables, partialFull)) {
							throw(type="cfTOML.TypeError", message="Cannot walk into inline table at '#partialFull#' from dotted key");
						}
						if (structkeyexists(aotArrays, partialFull)) {
							throw(type="cfTOML.TypeError", message="Cannot walk into array-of-tables at '#partialFull#' from dotted key at line #tok.line#");
						}
						if (structkeyexists(explicitTables, partialFull)) {
							throw(type="cfTOML.TypeError", message="Cannot extend explicitly-defined table '#partialFull#' via dotted keys from header '[#currentTablePath#]' at line #tok.line#");
						}
						dottedKeyTables[partialFull] = variables.jTrue;
					}
					target = walkOrCreatePathArray(currentTable, intermediate);
				}
				var leafKey = pathSegments[arraylen(pathSegments)];
				if (structkeyexists(target, leafKey)) {
					throw(type="cfTOML.DuplicateKeyError", message="Key '#leafKey#' already defined at line #tok.line#, column #tok.col#");
				}
				target[leafKey] = value;
				// Track inline-table paths so dotted keys and table headers cannot walk into them later
				if (valTok.type eq "INLINE_OPEN") {
					var fullPathParts = (len(currentTablePath) gt 0) ? listToArray(currentTablePath, ".") : [];
					for (var seg in pathSegments) {
						arrayappend(fullPathParts, seg);
					}
					inlineTables[arraytolist(fullPathParts, ".")] = variables.jTrue;
				}
				i = nextIdx;
				if (i lte n && arguments.tokens[i].type neq "NEWLINE" && arguments.tokens[i].type neq "COMMENT") {
					throw(type="cfTOML.ParseError", message="Expected newline or end-of-input after key-value pair at line #tok.line#, column #tok.col# (got '#arguments.tokens[i].type#')");
				}
				continue;
			}
			throw(type="cfTOML.ParseError", message="Unexpected token '#tok.type#' at line #tok.line#, column #tok.col#");
		}
		return root;
	}

	private boolean function isKeySegmentToken(required struct tok, required struct opts) hint="True if this token is acceptable as a key path segment: bare KEY, quoted STRING_BASIC/STRING_LITERAL, unsigned 'inf'/'nan' or bare-key-shaped FLOAT, BOOL ('true'/'false'), or an all-digit INT (valid in both TOML 1.0.0 and 1.1.0). The lexer greedily emits FLOAT/BOOL/INT even when the lexeme appears at start-of-statement, so the parser accepts those as keys here." {
		if (arguments.tok.type eq "KEY") return variables.jTrue;
		if (arguments.tok.type eq "STRING_BASIC") return variables.jTrue;
		if (arguments.tok.type eq "STRING_LITERAL") return variables.jTrue;
		if (arguments.tok.type eq "BOOL") return variables.jTrue;
		if (arguments.tok.type eq "FLOAT") {
			var v = arguments.tok.value;
			// Signed FLOATs (+3.14, -inf) are values, never keys.
			if (left(v, 1) eq "+" || left(v, 1) eq "-") return variables.jFalse;
			if (compare(v, "inf") eq 0 || compare(v, "nan") eq 0) return variables.jTrue;
			// Bare-key-shaped (`10e3`) or dotted-bare-key-shaped (`3.14`). Splitting is done by the caller.
			if (reFind("^[A-Za-z0-9_\-]+(\.[A-Za-z0-9_\-]+)*$", v) gt 0) return variables.jTrue;
			return variables.jFalse;
		}
		// All-digit INT keys are valid in TOML 1.0.0 ("Bare keys are allowed to be composed of only ASCII digits, e.g. 1234")
		// and remain valid in 1.1.0. Require unsigned, all-digit (no underscores or signs).
		if (arguments.tok.type eq "INT" && isAllDigitLexeme(arguments.tok.value)) {
			return variables.jTrue;
		}
		return variables.jFalse;
	}

	private string function tokenAsKeySegment(required struct tok, required struct opts) hint="Extract the textual key from a token that satisfies isKeySegmentToken. Basic-string keys are escape-decoded; literal-string and value-lookalike keys are passed through verbatim." {
		if (arguments.tok.type eq "STRING_BASIC") {
			return decodeBasicStringEscapes(arguments.tok.value, arguments.opts.spec);
		}
		return arguments.tok.value;
	}

	private array function appendKeyTokenSegments(required array pathSegments, required struct tok, required struct opts) hint="Append one or more key path segments from a single token. FLOAT tokens like `3.14` represent a dotted bare-key path and split into multiple segments; everything else becomes one." {
		var text = tokenAsKeySegment(arguments.tok, arguments.opts);
		if (arguments.tok.type eq "FLOAT" && find(".", text) gt 0) {
			for (var part in listToArray(text, ".")) {
				arrayappend(arguments.pathSegments, part);
			}
		} else {
			arrayappend(arguments.pathSegments, text);
		}
		return arguments.pathSegments;
	}

	private struct function walkOrCreatePath(required struct root, required string dottedPath, string spec = "1.0.0") hint="Walk a dotted path from root, creating intermediate ordered structs as needed. If a segment is an array, walk into its last element (array-of-tables semantics). spec is threaded to splitDottedPath." {
		return walkOrCreatePathArray(arguments.root, splitDottedPath(arguments.dottedPath, arguments.spec));
	}

	private struct function walkOrCreatePathArray(required struct root, required array segments) hint="Same as walkOrCreatePath but takes pre-split segments so empty quoted segments survive." {
		var node = arguments.root;
		for (var seg in arguments.segments) {
			if (!structkeyexists(node, seg)) {
				node[seg] = newDataStruct();
			}
			if (isArray(node[seg])) {
				if (!arraylen(node[seg])) {
					throw(type="cfTOML.TypeError", message="Path walks into empty array at '#seg#'");
				}
				node = node[seg][arraylen(node[seg])];
				if (!isStruct(node)) {
					throw(type="cfTOML.TypeError", message="Path walks into non-table array element at '#seg#'");
				}
				continue;
			}
			if (!isStruct(node[seg])) {
				throw(type="cfTOML.TypeError", message="Path walks into non-table value at '#seg#'");
			}
			node = node[seg];
		}
		return node;
	}

	private array function splitDottedPath(required string dottedPath, string spec = "1.0.0") hint="Split a dotted-path string into segments, respecting quoted segments. Basic-string segments are escape-decoded; literal-string segments are passed through verbatim. spec is threaded to the basic-string decoder." {
		var raw = trim(arguments.dottedPath);
		if (!len(raw)) {
			throw(type="cfTOML.ParseError", message="Empty table header path");
		}
		var n = len(raw);
		var segments = [];
		var current = "";          // bare-key content
		var quotedRaw = "";        // accumulated content inside the current quoted segment
		var inBasic = variables.jFalse;
		var inLiteral = variables.jFalse;
		var currentFromQuoted = variables.jFalse;  // true when the current segment was filled by a quoted literal (which may be empty)
		var i = 1;
		while (i lte n) {
			var c = mid(raw, i, 1);
			if (inBasic) {
				if (c eq chr(34)) {
					// Close basic-string segment - decode the raw content and append to current
					current &= decodeBasicStringEscapes(quotedRaw, arguments.spec);
					quotedRaw = "";
					inBasic = variables.jFalse;
					currentFromQuoted = variables.jTrue;
				} else if (c eq "\") {
					// Capture backslash + next char raw (decoder handles the rest)
					if (i + 1 gt n) {
						throw(type="cfTOML.ParseError", message="Truncated escape in quoted segment at position ##i##");
					}
					quotedRaw &= c & mid(raw, i + 1, 1);
					i++;
				} else if (c eq chr(10) || c eq chr(13)) {
					throw(type="cfTOML.ParseError", message="Newline in quoted segment of path '#arguments.dottedPath#'");
				} else {
					quotedRaw &= c;
				}
			} else if (inLiteral) {
				if (c eq "'") {
					current &= quotedRaw;
					quotedRaw = "";
					inLiteral = variables.jFalse;
					currentFromQuoted = variables.jTrue;
				} else if (c eq chr(10) || c eq chr(13)) {
					throw(type="cfTOML.ParseError", message="Newline in literal segment of path '#arguments.dottedPath#'");
				} else {
					quotedRaw &= c;
				}
			} else {
				if (c eq chr(34)) {
					// Whitespace between a dot and the opening quote is allowed; bare-key content before a quote is not.
					if (len(trim(current))) {
						throw(type="cfTOML.ParseError", message="Bare-key content '#trim(current)#' before quoted segment in path '#arguments.dottedPath#'");
					}
					current = "";
					inBasic = variables.jTrue;
				} else if (c eq "'") {
					if (len(trim(current))) {
						throw(type="cfTOML.ParseError", message="Bare-key content '#trim(current)#' before quoted segment in path '#arguments.dottedPath#'");
					}
					current = "";
					inLiteral = variables.jTrue;
				} else if (c eq ".") {
					var seg = currentFromQuoted ? current : trim(current);
					if (!currentFromQuoted && !len(seg)) {
						throw(type="cfTOML.ParseError", message="Empty segment in path '#arguments.dottedPath#'");
					}
					if (!currentFromQuoted) {
						validateBareKeySegment(seg, arguments.dottedPath, arguments.spec);
					}
					arrayappend(segments, seg);
					current = "";
					currentFromQuoted = variables.jFalse;
				} else if (currentFromQuoted) {
					// After a closing quote, only whitespace is allowed before the next dot (or end of path).
					if (c neq " " && c neq chr(9)) {
						throw(type="cfTOML.ParseError", message="Unexpected '#c#' after quoted segment in path '#arguments.dottedPath#'");
					}
					// Whitespace is silently consumed; do not append.
				} else {
					current &= c;
				}
			}
			i++;
		}
		if (inBasic || inLiteral) {
			throw(type="cfTOML.ParseError", message="Unterminated quoted segment in path '#arguments.dottedPath#'");
		}
		var lastSeg = currentFromQuoted ? current : trim(current);
		if (!currentFromQuoted && !len(lastSeg)) {
			throw(type="cfTOML.ParseError", message="Empty trailing segment in path '#arguments.dottedPath#'");
		}
		if (!currentFromQuoted) {
			validateBareKeySegment(lastSeg, arguments.dottedPath, arguments.spec);
		}
		arrayappend(segments, lastSeg);
		return segments;
	}

	private void function validateBareKeySegment(required string seg, required string dottedPath, required string spec) hint="Reject bare segments that contain characters outside the bare-key character class. Quoted segments are skipped by the caller." {
		var pattern = (arguments.spec eq "1.1.0") ? "^([A-Za-z0-9_\-]|[^\x00-\x7F])+$" : "^[A-Za-z0-9_\-]+$";
		if (!reFind(pattern, arguments.seg)) {
			throw(type="cfTOML.ParseError", message="Invalid bare key segment '#arguments.seg#' in path '#arguments.dottedPath#'");
		}
	}

	private any function resolveScalarValue(required struct token, required struct options) hint="Convert a value-token's raw lexeme to a CFML value per options." {
		var t = arguments.token;
		if (t.type eq "STRING_BASIC") {
			return decodeBasicStringEscapes(t.value, arguments.options.spec);
		}
		if (t.type eq "STRING_LITERAL") {
			return t.value;
		}
		if (t.type eq "STRING_ML_BASIC") {
			return decodeMultiLineBasicEscapes(t.value, arguments.options.spec);
		}
		if (t.type eq "STRING_ML_LITERAL") {
			return t.value;
		}
		if (t.type eq "INT") {
			return parseIntegerLexeme(t.value, arguments.options.int64Mode, arguments.options.strict);
		}
		if (t.type eq "FLOAT") {
			// Special-string floats: inf, +inf, -inf, nan, +nan, -nan
			if (t.value eq "inf" || t.value eq "+inf") {
				return createObject("java", "java.lang.Double").POSITIVE_INFINITY;
			}
			if (t.value eq "-inf") {
				return createObject("java", "java.lang.Double").NEGATIVE_INFINITY;
			}
			if (t.value eq "nan" || t.value eq "+nan" || t.value eq "-nan") {
				return createObject("java", "java.lang.Double").NaN;
			}
			// Normal float: strip underscores, parse via Java Double
			var clean = replace(t.value, "_", "", "all");
			return javacast("double", createObject("java", "java.lang.Double").parseDouble(clean));
		}
		if (t.type eq "BOOL") {
			return (t.value eq "true") ? variables.jTrue : variables.jFalse;
		}
		if (t.type eq "DATE_LOCAL" || t.type eq "TIME_LOCAL" || t.type eq "DATETIME_LOCAL" || t.type eq "DATETIME_OFFSET") {
			return parseRFC3339(t.value, arguments.options.dateTimeReturn, arguments.options.spec);
		}
		throw(type="cfTOML.ParseError", message="Cannot resolve token '#t.type#' as a scalar value at line #t.line#, column #t.col#");
	}

	private struct function parseArrayTokens(required array tokens, required numeric startIdx, required struct options) hint="Parse an array starting at the ARRAY_OPEN token at startIdx. Returns {value: cfml_array, endIdx: idx-after-ARRAY_CLOSE}." {
		var n = arraylen(arguments.tokens);
		if (arguments.startIdx gt n || arguments.tokens[arguments.startIdx].type neq "ARRAY_OPEN") {
			throw(type="cfTOML.ParseError", message="Expected ARRAY_OPEN at index #arguments.startIdx#");
		}
		var result = [];
		var i = arguments.startIdx + 1;
		// Track state: after [ or after , we expect a value (or ]); after a value we expect , or ].
		var expectingValue = javacast("boolean", 1);
		while (i lte n) {
			var tok = arguments.tokens[i];
			if (tok.type eq "NEWLINE" || tok.type eq "COMMENT") {
				i++;
				continue;
			}
			if (tok.type eq "ARRAY_CLOSE") {
				return ["value": result, "endIdx": i + 1];
			}
			if (tok.type eq "COMMA") {
				if (expectingValue) {
					throw(type="cfTOML.ParseError", message="Unexpected ',' in array at line #tok.line#, column #tok.col#");
				}
				expectingValue = javacast("boolean", 1);
				i++;
				continue;
			}
			if (!expectingValue) {
				throw(type="cfTOML.ParseError", message="Expected ',' or ']' in array at line #tok.line#, column #tok.col# (got '#tok.type#')");
			}
			// Value token: scalar, nested array, or inline table
			if (tok.type eq "ARRAY_OPEN") {
				var sub = parseArrayTokens(arguments.tokens, i, arguments.options);
				arrayappend(result, sub.value);
				i = sub.endIdx;
			} else if (tok.type eq "INLINE_OPEN") {
				var sub = parseInlineTableTokens(arguments.tokens, i, arguments.options);
				arrayappend(result, sub.value);
				i = sub.endIdx;
			} else {
				arrayappend(result, resolveScalarValue(tok, arguments.options));
				i++;
			}
			expectingValue = javacast("boolean", 0);
		}
		throw(type="cfTOML.ParseError", message="Unterminated array starting at index #arguments.startIdx#");
	}

	private struct function parseInlineTableTokens(required array tokens, required numeric startIdx, required struct options) hint="Parse an inline table starting at the INLINE_OPEN token at startIdx. Returns {value: ordered_struct, endIdx: idx-after-INLINE_CLOSE}." {
		var n = arraylen(arguments.tokens);
		if (arguments.startIdx gt n || arguments.tokens[arguments.startIdx].type neq "INLINE_OPEN") {
			throw(type="cfTOML.ParseError", message="Expected INLINE_OPEN at index #arguments.startIdx#");
		}
		var result = newDataStruct();
		var i = arguments.startIdx + 1;
		// Track state: after { or after , we expect a key (or } when the table is empty / trailing-comma in 1.1.0);
		// after a key=value pair we expect , or }.
		var expectingKey = javacast("boolean", 1);
		// Track full paths (chr(1)-joined) that have been assigned a value in this literal. A later dotted key
		// whose intermediate path walks through one of these is rejected (inline tables are immutable).
		var setPaths = newDataStruct();
		var sep = chr(1);
		while (i lte n) {
			var tok = arguments.tokens[i];
			// In 1.0.0 mode, inline tables are single-line - newlines throw.
			// In 1.1.0 mode, newlines and comments are permitted.
			if (tok.type eq "NEWLINE") {
				if (arguments.options.spec eq "1.0.0") {
					throw(type="cfTOML.ParseError", message="Newline inside inline table not allowed in TOML 1.0.0 at line #tok.line#. Pass { spec: '1.1.0' } to enable multi-line inline tables.");
				}
				i++;
				continue;
			}
			if (tok.type eq "COMMENT") {
				i++;
				continue;
			}
			if (tok.type eq "COMMA") {
				if (expectingKey) {
					throw(type="cfTOML.ParseError", message="Unexpected ',' in inline table at line #tok.line#, column #tok.col#");
				}
				// Look ahead past comments/newlines for the next significant token (for trailing-comma detection)
				var k2 = i + 1;
				while (k2 lte n && (arguments.tokens[k2].type eq "COMMENT" || arguments.tokens[k2].type eq "NEWLINE")) {
					k2++;
				}
				if (k2 lte n && arguments.tokens[k2].type eq "INLINE_CLOSE") {
					if (arguments.options.spec eq "1.0.0") {
						throw(type="cfTOML.ParseError", message="Trailing comma not allowed in inline table in TOML 1.0.0 at line #tok.line#. Pass { spec: '1.1.0' } to enable.");
					}
				}
				expectingKey = javacast("boolean", 1);
				i++;
				continue;
			}
			if (tok.type eq "INLINE_CLOSE") {
				return ["value": result, "endIdx": i + 1];
			}
			if (!expectingKey) {
				throw(type="cfTOML.ParseError", message="Expected ',' or '}' in inline table at line #tok.line#, column #tok.col# (got '#tok.type#')");
			}
			// Expect <key-segment> (DOT <key-segment>)* EQUALS <value>
			// Quoted strings (STRING_BASIC, STRING_LITERAL) and (in 1.1.0) all-digit INT tokens are also valid key segments.
			if (isKeySegmentToken(tok, arguments.options)) {
				var pathSegments = appendKeyTokenSegments([], tok, arguments.options);
				var j = i + 1;
				while (j + 1 lte n
					&& arguments.tokens[j].type eq "DOT"
					&& isKeySegmentToken(arguments.tokens[j + 1], arguments.options)) {
					pathSegments = appendKeyTokenSegments(pathSegments, arguments.tokens[j + 1], arguments.options);
					j += 2;
				}
				if (j gt n || arguments.tokens[j].type neq "EQUALS") {
					throw(type="cfTOML.ParseError", message="Expected '=' in inline table at line #tok.line#");
				}
				if (j + 1 gt n) {
					throw(type="cfTOML.ParseError", message="Missing value in inline table at line #tok.line#");
				}
				var valTok = arguments.tokens[j + 1];
				var value = "";
				var nextIdx = 0;
				if (valTok.type eq "ARRAY_OPEN") {
					var arrParse = parseArrayTokens(arguments.tokens, j + 1, arguments.options);
					value = arrParse.value;
					nextIdx = arrParse.endIdx;
				} else if (valTok.type eq "INLINE_OPEN") {
					var inlParse = parseInlineTableTokens(arguments.tokens, j + 1, arguments.options);
					value = inlParse.value;
					nextIdx = inlParse.endIdx;
				} else {
					value = resolveScalarValue(valTok, arguments.options);
					nextIdx = j + 2;
				}
				// Place value at the leaf of pathSegments within the inline-table result
				var target = result;
				if (arraylen(pathSegments) gt 1) {
					var intermediate = [];
					for (var k = 1; k lte arraylen(pathSegments) - 1; k++) {
						arrayappend(intermediate, pathSegments[k]);
					}
					// Reject walking through any prefix that was already SET as a value in this same literal.
					// Implicit intermediates from previous dotted keys are fine - only explicit assignments are immutable.
					var prefixKey = "";
					for (var k = 1; k lte arraylen(intermediate); k++) {
						prefixKey = (k eq 1) ? intermediate[k] : (prefixKey & sep & intermediate[k]);
						if (structkeyexists(setPaths, prefixKey)) {
							throw(type="cfTOML.DuplicateKeyError", message="Inline-table key '#arraytolist(intermediate, ".")#' was already set; cannot extend at line #tok.line#");
						}
					}
					target = walkOrCreatePathArray(result, intermediate);
				}
				var leafKey = pathSegments[arraylen(pathSegments)];
				if (structkeyexists(target, leafKey)) {
					throw(type="cfTOML.DuplicateKeyError", message="Key '#leafKey#' already defined in inline table at line #tok.line#");
				}
				target[leafKey] = value;
				// Record the full pathSegments as a "set path" for this literal so future walks through it are rejected.
				var fullKey = pathSegments[1];
				for (var k = 2; k lte arraylen(pathSegments); k++) {
					fullKey &= sep & pathSegments[k];
				}
				setPaths[fullKey] = variables.jTrue;
				i = nextIdx;
				expectingKey = javacast("boolean", 0);
				continue;
			}
			throw(type="cfTOML.ParseError", message="Unexpected token '#tok.type#' in inline table at line #tok.line#");
		}
		throw(type="cfTOML.ParseError", message="Unterminated inline table starting at index #arguments.startIdx#");
	}

	public struct function mergeOptionsForTest() hint="Helper for tests to obtain a default options struct without calling init()." {
		return mergeWithDefaults([:]);
	}

	// ----- emitter -----

	private boolean function shouldInline(required struct data, required numeric threshold) hint="True if the struct has <= threshold keys AND no nested non-AoT struct or AoT child." {
		if (structcount(arguments.data) gt arguments.threshold) {
			return variables.jFalse;
		}
		for (var key in arguments.data) {
			var val = arguments.data[key];
			if (isStruct(val) && !isArray(val)) return variables.jFalse;
			if (isAoT(val)) return variables.jFalse;
		}
		return variables.jTrue;
	}

	private string function emitTable(required struct data, required array pathPrefix, required struct options, numeric depth = 0) hint="Emit a table block. Three passes: scalars/inline-tables/arrays first, nested non-AoT tables second, arrays-of-tables third. inlineThreshold may promote small structs to inline." {
		if (!structcount(arguments.data)) {
			return "";
		}
		// Pre-process: scan all keys for null values and query objects.
		// CF2016 throws "Element is undefined" when accessing a struct key whose value is Java null,
		// so we must use try/catch to detect null values rather than isNull(struct[key]).
		// We record null keys and convert any query values, building a clean replacement struct.
		var rawKeys = structkeyarray(arguments.data);
		var nullKeys = [:];           // keys whose values are null (CF2016 null-access guard)
		var processedData = [:];    // rebuilt struct: null-free, queries converted
		for (var pkey in rawKeys) {
			var _pkeyIsNull = variables.jFalse;
			var _pkeyVal = javaCast("null", 0);
			try { _pkeyVal = arguments.data[pkey]; } catch (any _e) { _pkeyIsNull = variables.jTrue; }
			if (_pkeyIsNull || isNull(_pkeyVal)) {
				// null-valued key - record it; no entry in processedData
				nullKeys[pkey] = variables.jTrue;
			} else if (isQuery(_pkeyVal)) {
				if (structkeyexists(arguments.options, "queryAsArrayOfTables") && arguments.options.queryAsArrayOfTables) {
					var queryArr = [];
					// Use getColumnNames() (Java method) for definition order;
					// columnList returns columns alphabetically in CF2016.
					var qcols = _pkeyVal.getColumnNames();
					for (var qrow = 1; qrow lte _pkeyVal.recordCount; qrow++) {
						var rowStruct = structNew("ordered");
						for (var qcol in qcols) {
							// Column names from getColumnNames() are already lowercase.
							rowStruct[qcol] = _pkeyVal[qcol][qrow];
						}
						arrayappend(queryArr, rowStruct);
					}
					processedData[pkey] = queryArr;
				} else {
					throw(type="cfTOML.TypeError", message="Cannot emit CFML query for key '#pkey#' without queryAsArrayOfTables=true");
				}
			} else {
				processedData[pkey] = _pkeyVal;
			}
		}
		arguments.data = processedData;
		// Determine key order (use rawKeys to preserve original order including null-key positions)
		var keys = rawKeys;
		if (structkeyexists(arguments.options, "sortKeys") && arguments.options.sortKeys) {
			arraysort(keys, "textnocase");
		}
		// Indent string for this depth (only applied when depth > 0 - root is unindented)
		var indentStr = "";
		if (structkeyexists(arguments.options, "indent") && len(arguments.options.indent) && arguments.depth gt 0) {
			indentStr = repeatString(arguments.options.indent, arguments.depth);
		}
		// inlineThreshold only applies at root depth (depth=0) to promote top-level sub-structs to inline form
		var threshold = (arguments.depth eq 0 && structkeyexists(arguments.options, "inlineThreshold")) ? arguments.options.inlineThreshold : 0;
		var out = "";
		// First pass: scalars/inline-tables/arrays. Also: structs that qualify for inline emission via threshold.
		for (var key in keys) {
			if (structkeyexists(nullKeys, key)) {
				var onNullMode = structkeyexists(arguments.options, "onNull") ? arguments.options.onNull : "skip";
				if (onNullMode eq "throw") {
					throw(type="cfTOML.TypeError", message="Null value for key '#key#' (onNull='throw')");
				}
				if (onNullMode eq "emptyString") {
					out &= indentStr & quoteKey(key, arguments.options) & ' = ""' & chr(10);
				}
				// "skip" or default: omit the key
				continue;
			}
			if (!structkeyexists(arguments.data, key)) continue; // skip keys not in processedData (safety guard)
			var val = arguments.data[key];
			if (isStruct(val) && !isArray(val)) {
				// Check if inline-eligible
				if (threshold gt 0 && shouldInline(val, threshold)) {
					out &= indentStr & quoteKey(key, arguments.options) & " = " & emitInlineTable(val, arguments.options) & chr(10);
				}
				continue;
			}
			if (isAoT(val)) continue;
			out &= indentStr & quoteKey(key, arguments.options) & " = " & emitValue(val, arguments.options, arguments.depth) & chr(10);
		}
		// Second pass: nested non-AoT tables - emit [header] block and recurse
		for (var key in keys) {
			if (!structkeyexists(arguments.data, key)) continue; // null or removed keys not in processedData
			var val = arguments.data[key];
			if (!isStruct(val) || isArray(val) || isAoT(val)) continue;
			if (threshold gt 0 && shouldInline(val, threshold)) continue;  // already emitted inline
			// Skip emitting [header] for sub-tables that have ONLY sub-struct or AoT children (no scalars)
			var subHasScalars = variables.jFalse;
			for (var sk in val) {
				var sv = val[sk];
				if (!(isStruct(sv) && !isArray(sv)) && !isAoT(sv)) {
					subHasScalars = variables.jTrue;
					break;
				}
			}
			var subPath = duplicate(arguments.pathPrefix);
			arrayappend(subPath, key);
			if (subHasScalars) {
				if (len(out) gt 0) {
					out &= chr(10);
				}
				out &= "[" & dottedPathString(subPath, arguments.options) & "]" & chr(10);
			}
			out &= emitTable(val, subPath, arguments.options, arguments.depth + 1);
		}
		// Third pass: arrays-of-tables
		for (var key in keys) {
			if (!structkeyexists(arguments.data, key)) continue; // null or removed keys not in processedData
			var val = arguments.data[key];
			if (!isAoT(val)) continue;
			var aotPath = duplicate(arguments.pathPrefix);
			arrayappend(aotPath, key);
			for (var elem in val) {
				if (len(out) gt 0) {
					out &= chr(10);
				}
				out &= "[[" & dottedPathString(aotPath, arguments.options) & "]]" & chr(10);
				out &= emitTable(elem, aotPath, arguments.options, arguments.depth + 1);
			}
		}
		return out;
	}

	private string function emitValue(required any value, required struct options, numeric depth = 0) hint="Dispatch a CFML value to the appropriate emit helper based on its Java class and CFML type predicates." {
		// Order matters: java.time.* and CFML date objects first (before isNumeric, since CFML dates are numeric),
		// then Java Boolean before isNumeric (CF reports isBoolean true for both),
		// then Java Long and Double (parsers use them) before generic isNumeric.
		// java.time.* objects: detect via class name
		if (!isSimpleValue(arguments.value)) {
			try {
				var cls = arguments.value.getClass().getName();
				if (cls eq "java.time.OffsetDateTime" || cls eq "java.time.LocalDateTime" || cls eq "java.time.LocalDate" || cls eq "java.time.LocalTime") {
					return emitDateTime(arguments.value, arguments.options);
				}
			} catch (any e) {}
		}
		// CFML date object: detect via Java class name to distinguish actual date objects
		// from strings that happen to look like dates (both are isSimpleValue in ACF).
		// ACF createDateTime() returns coldfusion.runtime.OleDateTime.
		// Lucee returns lucee.runtime.type.dt.DateTimeImpl.
		// Plain strings return java.lang.String - those must NOT be emitted as datetimes.
		if (isDate(arguments.value)) {
			try {
				var dateCls = arguments.value.getClass().getName();
				if (dateCls neq "java.lang.String") {
					return emitDateTime(arguments.value, arguments.options);
				}
			} catch (any e) {}
		}
		if (isJavaBoolean(arguments.value)) {
			return arguments.value ? "true" : "false";
		}
		if (isSimpleValue(arguments.value) && isNumeric(arguments.value)) {
			// Detect Java Double - special float handling (NaN/Inf and whole-number floats)
			try {
				var numCls = arguments.value.getClass().getName();
				if (numCls eq "java.lang.Double") {
					var d = arguments.value.doubleValue();
					if (createObject("java", "java.lang.Double").isNaN(d)) return "nan";
					if (createObject("java", "java.lang.Double").isInfinite(d)) {
						return (d gt 0) ? "inf" : "-inf";
					}
					// Whole-number Doubles emit as integers. Adobe CF differentiates Long/Integer from Double
					// at the language level, so an int literal `1` arrives here as Long and an explicit float
					// `1.0` arrives as Double - we never see whole-number Doubles for integers. Lucee stores all
					// numeric literals as Double regardless of whether the source was `1` or `1.0`, so we cannot
					// distinguish; emit whole-number Doubles as integers and require callers who specifically
					// want a TOML float to pass a non-whole value or a fractional decimal string.
					if (d eq floor(d) && abs(d) lt 9007199254740992) {
						return toString(int(d));
					}
					var dStr = toString(arguments.value);
					// Ensure output has a decimal point (TOML float requires fractional part or exponent)
					if (find(".", dStr) eq 0 && find("e", lcase(dStr)) eq 0) {
						dStr &= ".0";
					}
					return dStr;
				}
			} catch (any e) {}
			// Distinguish integer from float by checking int truncation
			if (int(arguments.value) eq arguments.value) {
				return toString(int(arguments.value));
			}
			return toString(arguments.value);
		}
		// NaN/Inf Doubles aren't isNumeric in CFML - detect separately before string fallback
		if (isSimpleValue(arguments.value)) {
			try {
				var fcls = arguments.value.getClass().getName();
				if (fcls eq "java.lang.Double") {
					var fd = arguments.value.doubleValue();
					if (createObject("java", "java.lang.Double").isNaN(fd)) return "nan";
					if (createObject("java", "java.lang.Double").isInfinite(fd)) {
						return (fd gt 0) ? "inf" : "-inf";
					}
				}
			} catch (any e) {}
			return emitString(toString(arguments.value), arguments.options);
		}
		if (isArray(arguments.value)) {
			return emitArray(arguments.value, arguments.options, arguments.depth);
		}
		if (isStruct(arguments.value)) {
			return emitInlineTable(arguments.value, arguments.options);
		}
		throw(type="cfTOML.TypeError", message="Cannot emit value of unsupported type");
	}

	private string function emitString(required string value, struct options = [:]) hint="Choose a TOML string variant for value (basic with escapes, or literal). Multi-line variants reserved for future use. options.spec='1.1.0' + options.useExtendedEscapes=true emits \e and \xHH for control chars." {
		var v = arguments.value;
		var hasBackslash = (find("\", v) gt 0);
		var hasSingleQuote = (find("'", v) gt 0);
		// Literal-string form is only valid if value has no control characters
		// (tab chr(9) is allowed in literal strings; all others 0-31 and 127 are not)
		var hasControlChar = variables.jFalse;
		var i2 = 1;
		while (i2 lte len(v)) {
			var code2 = asc(mid(v, i2, 1));
			if ((code2 lt 32 && code2 neq 9) || code2 eq 127) {
				hasControlChar = variables.jTrue;
				break;
			}
			i2++;
		}
		// If value has a backslash and no single quote and no control chars, use literal-string form
		if (hasBackslash && !hasSingleQuote && !hasControlChar) {
			return "'" & v & "'";
		}
		// Otherwise basic-string form with escapes
		var out = chr(34);
		var n = len(v);
		var i = 1;
		while (i lte n) {
			var c = mid(v, i, 1);
			var code = asc(c);
			if (c eq "\") {
				out &= "\\";
			} else if (c eq chr(34)) {
				out &= "\" & chr(34);
			} else if (code eq 8) {
				out &= "\b";
			} else if (code eq 9) {
				out &= "\t";
			} else if (code eq 10) {
				out &= "\n";
			} else if (code eq 12) {
				out &= "\f";
			} else if (code eq 13) {
				out &= "\r";
			} else if (code lt 32 || code eq 127) {
				var useExt = structkeyexists(arguments.options, "useExtendedEscapes")
					&& arguments.options.useExtendedEscapes
					&& structkeyexists(arguments.options, "spec")
					&& arguments.options.spec eq "1.1.0";
				if (useExt && code eq 27) {
					out &= "\e";
				} else if (useExt) {
					out &= "\x" & lcase(right("0" & formatBaseN(code, 16), 2));
				} else {
					out &= "\u" & ucase(right("000" & formatBaseN(code, 16), 4));
				}
			} else {
				out &= c;
			}
			i++;
		}
		out &= chr(34);
		return out;
	}

	private string function emitDateTime(required any value, struct options = [:]) hint="Emit a datetime value in canonical RFC 3339 form. options.spec='1.1.0' + options.omitZeroSeconds=true drops trailing ':00' when seconds and subseconds are both zero." {
		if (!isSimpleValue(arguments.value)) {
			var cls = "";
			try {
				cls = arguments.value.getClass().getName();
			} catch (any e) {}
			if (cls eq "java.time.OffsetDateTime" || cls eq "java.time.LocalDateTime" || cls eq "java.time.LocalDate" || cls eq "java.time.LocalTime") {
				// java.time.* toString() produces canonical ISO 8601 but may omit :00 seconds.
				// e.g. 1979-05-27T07:32-08:00 instead of 1979-05-27T07:32:00-08:00.
				// Normalize by using the class's format method with explicit seconds for datetime types.
				if (cls eq "java.time.LocalDate") {
					// LocalDate has no time component - toString() is already canonical
					return arguments.value.toString();
				}
				// For OffsetDateTime, LocalDateTime, LocalTime: format explicitly to ensure HH:mm:ss
				var fmt = createObject("java", "java.time.format.DateTimeFormatter");
				if (cls eq "java.time.OffsetDateTime") {
					var hasMs = (arguments.value.getNano() neq 0);
					var omitSecs = !hasMs
						&& arguments.value.getSecond() eq 0
						&& structkeyexists(arguments.options, "omitZeroSeconds")
						&& arguments.options.omitZeroSeconds
						&& structkeyexists(arguments.options, "spec")
						&& arguments.options.spec eq "1.1.0";
					var pattern = omitSecs ? "yyyy-MM-dd'T'HH:mmXXXXX"
					           : hasMs ? "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
					                   : "yyyy-MM-dd'T'HH:mm:ssXXXXX";
					// BoxLang intercepts value.format(formatter) as the built-in format() function,
					// so call formatter.format(value) instead - same operation, different dispatch.
					var formatted = fmt.ofPattern(pattern).format(arguments.value);
					// Normalize UTC offset to canonical Z form per RFC 3339
					if (right(formatted, 6) eq "+00:00") {
						formatted = mid(formatted, 1, len(formatted) - 6) & "Z";
					}
					return formatted;
				} else if (cls eq "java.time.LocalDateTime") {
					var hasMs = (arguments.value.getNano() neq 0);
					var omitSecs = !hasMs
						&& arguments.value.getSecond() eq 0
						&& structkeyexists(arguments.options, "omitZeroSeconds")
						&& arguments.options.omitZeroSeconds
						&& structkeyexists(arguments.options, "spec")
						&& arguments.options.spec eq "1.1.0";
					var pattern = omitSecs ? "yyyy-MM-dd'T'HH:mm"
					           : hasMs ? "yyyy-MM-dd'T'HH:mm:ss.SSS"
					                   : "yyyy-MM-dd'T'HH:mm:ss";
					return fmt.ofPattern(pattern).format(arguments.value);
				} else if (cls eq "java.time.LocalTime") {
					var hasMs = (arguments.value.getNano() neq 0);
					var omitSecs = !hasMs
						&& arguments.value.getSecond() eq 0
						&& structkeyexists(arguments.options, "omitZeroSeconds")
						&& arguments.options.omitZeroSeconds
						&& structkeyexists(arguments.options, "spec")
						&& arguments.options.spec eq "1.1.0";
					var pattern = omitSecs ? "HH:mm"
					           : hasMs ? "HH:mm:ss.SSS"
					                   : "HH:mm:ss";
					return fmt.ofPattern(pattern).format(arguments.value);
				}
				return arguments.value.toString();
			}
		}
		// CFML date object: emit as DATETIME_LOCAL (zone-naive). CFML dates carry no zone information,
		// so writing them as UTC would be incorrect on a non-UTC server. Users who need a specific
		// offset should pass a java.time.OffsetDateTime instead.
		// Build the ISO string from date components directly. dateTimeFormat() masks are not portable:
		// Adobe CF and Lucee read "mm" as month and "nn" as minute in a time context, while BoxLang
		// follows Java SimpleDateFormat ("mm" is minute, "nn" doesn't exist). Component accessors
		// (year/month/day/hour/minute/second) behave consistently on every supported engine.
		var dY = year(arguments.value);
		var dMo = month(arguments.value);
		var dD = day(arguments.value);
		var dH = hour(arguments.value);
		var dMi = minute(arguments.value);
		var dS = second(arguments.value);
		return dY & "-" & numberFormat(dMo, "00") & "-" & numberFormat(dD, "00")
		     & "T" & numberFormat(dH, "00") & ":" & numberFormat(dMi, "00") & ":" & numberFormat(dS, "00");
	}

	private string function emitArray(required array arr, required struct options, numeric depth = 0) hint="Emit an array value as a comma-separated list in square brackets." {
		if (!arraylen(arguments.arr)) {
			return "[]";
		}
		var parts = [];
		for (var elem in arguments.arr) {
			arrayappend(parts, emitValue(elem, arguments.options, arguments.depth));
		}
		return "[" & arraytolist(parts, ", ") & "]";
	}

	private string function emitInlineTable(required struct data, required struct options) hint="Emit a struct as an inline table { k1 = v1, k2 = v2 }. Under spec=1.1.0 + inlineMultiline=true, switches to multi-line form when single-line exceeds 80 chars or contains multi-line values." {
		if (!structcount(arguments.data)) {
			return "{}";
		}
		var keys = structkeyarray(arguments.data);
		if (structkeyexists(arguments.options, "sortKeys") && arguments.options.sortKeys) {
			arraysort(keys, "textnocase");
		}
		var parts = [];
		for (var key in keys) {
			arrayappend(parts, quoteKey(key, arguments.options) & " = " & emitValue(arguments.data[key], arguments.options, 0));
		}
		var singleLine = "{ " & arraytolist(parts, ", ") & " }";
		var allowMulti = structkeyexists(arguments.options, "inlineMultiline")
			&& arguments.options.inlineMultiline
			&& structkeyexists(arguments.options, "spec")
			&& arguments.options.spec eq "1.1.0";
		if (!allowMulti) {
			return singleLine;
		}
		// Activate multi-line form when single-line would exceed 80 chars or any value is itself multi-line
		var hasNewlineValue = (find(chr(10), singleLine) gt 0);
		if (len(singleLine) lte 80 && !hasNewlineValue) {
			return singleLine;
		}
		// Multi-line form: one key=value per line with tab indent, closing brace on its own line
		var indent = chr(9);
		var lines = ["{"];
		for (var k in keys) {
			arrayappend(lines, indent & quoteKey(k, arguments.options) & " = " & emitValue(arguments.data[k], arguments.options, 0) & ",");
		}
		// Drop trailing comma from final entry (cleaner; trailing comma is permitted under 1.1.0 but not required)
		var last = lines[arraylen(lines)];
		if (right(last, 1) eq ",") {
			lines[arraylen(lines)] = mid(last, 1, len(last) - 1);
		}
		arrayappend(lines, "}");
		return arraytolist(lines, chr(10));
	}

	private string function quoteKey(required string key, struct options = [:]) hint="Return the key bare if it matches the TOML bare-key pattern, otherwise as a quoted-string segment with proper escaping. All-digit keys are quoted by default; 1.1.0 mode with useBareDigitKeys=true emits them bare." {
		var isAllDigit = (len(arguments.key) gt 0 && reFind("^[0-9]+$", arguments.key) gt 0);
		var allowBareDigit = isAllDigit
			&& structkeyexists(arguments.options, "spec")
			&& arguments.options.spec eq "1.1.0"
			&& structkeyexists(arguments.options, "useBareDigitKeys")
			&& arguments.options.useBareDigitKeys;
		if (isAllDigit && !allowBareDigit) {
			// Quote all-digit keys to stay 1.0.0-compatible
			return emitString(arguments.key, arguments.options);
		}
		if (len(arguments.key) gt 0 && reFind("^[A-Za-z0-9_-]+$", arguments.key)) {
			return arguments.key;
		}
		return emitString(arguments.key, arguments.options);
	}

	private boolean function isAoT(required any value) hint="True if value is an array whose every element is a struct (array-of-tables)." {
		if (!isArray(arguments.value)) {
			return variables.jFalse;
		}
		if (!arraylen(arguments.value)) {
			return variables.jFalse;  // empty array is not AoT
		}
		for (var elem in arguments.value) {
			if (!isStruct(elem)) {
				return variables.jFalse;
			}
		}
		return variables.jTrue;
	}

	private string function dottedPathString(required array segments, struct options = [:]) hint="Join path segments with '.', quoting any segment that isn't bare-key-eligible." {
		var parts = [];
		for (var seg in arguments.segments) {
			arrayappend(parts, quoteKey(seg, arguments.options));
		}
		return arraytolist(parts, ".");
	}

	private boolean function isAllDigitLexeme(required string lexeme) hint="True if the lexeme is one or more ASCII digits with no sign or separator. Used for 1.1.0 all-digit bare keys." {
		return reFind("^[0-9]+$", arguments.lexeme) gt 0;
	}

	private boolean function isJavaBoolean(required any value) hint="True if the value is a Java Boolean instance (vs an integer or numeric string that CFML's isBoolean would also accept)." {
		// CFML's isBoolean is too liberal. Inspect the Java class directly.
		if (isSimpleValue(arguments.value)) {
			try {
				var cls = arguments.value.getClass().getName();
				return cls eq "java.lang.Boolean";
			} catch (any e) {
				return variables.jFalse;
			}
		}
		return variables.jFalse;
	}

	// ----- datetime codec -----

	public any function parseRFC3339(required string raw, string mode = "cfdate", string spec = "1.0.0") hint="Parse an RFC 3339 datetime/date/time lexeme and return a value per mode: cfdate | iso8601 | javatime. spec='1.1.0' accepts seconds-less forms and synthesizes :00." {
		var src = trim(arguments.raw);
		if (arguments.spec eq "1.1.0") {
			src = normalizeSecondsLessDatetime(src);
		}
		// Detect shape via regex
		var isOffsetDateTime = reFind("^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|z|[+\-][0-9]{2}:[0-9]{2})$", src) gt 0;
		var isLocalDateTime = !isOffsetDateTime && reFind("^[0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$", src) gt 0;
		var isLocalDate = !isOffsetDateTime && !isLocalDateTime && reFind("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", src) gt 0;
		var isLocalTime = !isOffsetDateTime && !isLocalDateTime && !isLocalDate && reFind("^[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?$", src) gt 0;
		if (!isOffsetDateTime && !isLocalDateTime && !isLocalDate && !isLocalTime) {
			throw(type="cfTOML.ParseError", message="Invalid RFC 3339 lexeme: '#arguments.raw#'");
		}
		// Offset range check (the cfdate path drops the zone so it would otherwise miss out-of-range offsets like +25:00 or +12:61).
		if (isOffsetDateTime) {
			var offMatch = reFind("([+\-])([0-9]{2}):([0-9]{2})$", src, 1, true);
			if (offMatch.len[1] gt 0) {
				// reFind returns full match at index 1; capture groups follow at 2, 3, 4 (sign, hour, minute).
				var offHr = int(mid(src, offMatch.pos[3], offMatch.len[3]));
				var offMin = int(mid(src, offMatch.pos[4], offMatch.len[4]));
				if (offHr gt 23 || offMin gt 59) {
					throw(type="cfTOML.ParseError", message="Datetime offset out of range: '#arguments.raw#' (hour 00-23, minute 00-59)");
				}
			}
		}
		// Time component range check. Adobe CF's createDateTime() rejects hour 24, but Lucee accepts it as
		// midnight-rollover, so the cfdate path would silently accept invalid TOML. Validate hh/mm/ss explicitly
		// here so all engines reject the same inputs.
		if (isOffsetDateTime || isLocalDateTime || isLocalTime) {
			var timeMatch = reFind("([0-9]{2}):([0-9]{2}):([0-9]{2})", src, 1, true);
			if (timeMatch.len[1] gt 0) {
				var thh = int(mid(src, timeMatch.pos[2], timeMatch.len[2]));
				var tmm = int(mid(src, timeMatch.pos[3], timeMatch.len[3]));
				var tss = int(mid(src, timeMatch.pos[4], timeMatch.len[4]));
				if (thh gt 23 || tmm gt 59 || tss gt 60) {
					throw(type="cfTOML.ParseError", message="Datetime time component out of range: '#arguments.raw#' (hour 00-23, minute 00-59, second 00-60)");
				}
			}
		}
		if (arguments.mode eq "iso8601") {
			return src;
		}
		try {
			if (arguments.mode eq "javatime") {
				if (isOffsetDateTime) {
					// Java's parser accepts T (uppercase) but not lowercase t or space - normalize
					var normalized = replace(replace(src, " ", "T", "one"), "t", "T", "one");
					return createObject("java", "java.time.OffsetDateTime").parse(normalized);
				}
				if (isLocalDateTime) {
					var normalized = replace(replace(src, " ", "T", "one"), "t", "T", "one");
					return createObject("java", "java.time.LocalDateTime").parse(normalized);
				}
				if (isLocalDate) {
					return createObject("java", "java.time.LocalDate").parse(src);
				}
				// isLocalTime
				return createObject("java", "java.time.LocalTime").parse(src);
			}
			// cfdate mode
			// Extract milliseconds from any fractional-second component (truncate beyond 3 digits, right-pad shorter).
			// CF2016's createDateTime() lacks the millisecond argument, so the ms are applied via dateAdd("l", ms, dt)
			// after the base datetime is built.
			var ms = 0;
			var fracIdx = find(".", src);
			if (fracIdx gt 0) {
				var fracStart = fracIdx + 1;
				var fracEnd = fracStart;
				while (fracEnd lte len(src) && reFind("[0-9]", mid(src, fracEnd, 1))) {
					fracEnd++;
				}
				var frac = mid(src, fracStart, fracEnd - fracStart);
				var frac3 = (len(frac) gte 3) ? left(frac, 3) : (frac & repeatString("0", 3 - len(frac)));
				ms = int(frac3);
			}
			if (isLocalDate) {
				return createDate(int(mid(src, 1, 4)), int(mid(src, 6, 2)), int(mid(src, 9, 2)));
			}
			if (isLocalTime) {
				var ltDt = createDateTime(1970, 1, 1, int(mid(src, 1, 2)), int(mid(src, 4, 2)), int(mid(src, 7, 2)));
				if (ms) ltDt = dateAdd("l", ms, ltDt);
				return ltDt;
			}
			if (isOffsetDateTime) {
				// Convert the offset datetime to the server's local zone so the returned CFML datetime represents
				// the same INSTANT in time. (Offset datetimes are exact instants per the TOML spec.) The result's
				// wall-clock value depends on the server's timezone; the instant does not.
				var normalizedODT = replace(replace(src, " ", "T", "one"), "t", "T", "one");
				var odt = createObject("java", "java.time.OffsetDateTime").parse(normalizedODT);
				var ldt = odt.atZoneSameInstant(createObject("java", "java.time.ZoneId").systemDefault()).toLocalDateTime();
				var odtMs = int(ldt.getNano() / 1000000);
				var odtDt = createDateTime(ldt.getYear(), ldt.getMonthValue(), ldt.getDayOfMonth(),
				                           ldt.getHour(), ldt.getMinute(), ldt.getSecond());
				if (odtMs) odtDt = dateAdd("l", odtMs, odtDt);
				return odtDt;
			}
			// isLocalDateTime: preserve the wall-clock verbatim (no zone to interpret).
			var datePart = mid(src, 1, 10);
			var timePart = mid(src, 12, 8);
			var ldtDt = createDateTime(int(mid(datePart, 1, 4)), int(mid(datePart, 6, 2)), int(mid(datePart, 9, 2)),
			                           int(mid(timePart, 1, 2)), int(mid(timePart, 4, 2)), int(mid(timePart, 7, 2)));
			if (ms) ldtDt = dateAdd("l", ms, ldtDt);
			return ldtDt;
		} catch (any e) {
			// Range violations from createDate/createDateTime/java.time parse surface as Adobe Expression/Application
			// or Lucee/BoxLang equivalents. Re-throw as cfTOML.ParseError so the public contract holds.
			throw(type="cfTOML.ParseError", message="Datetime value out of range: '#arguments.raw#'. #e.message#");
		}
	}

	private string function normalizeSecondsLessDatetime(required string lexeme) hint="If a 1.1.0 datetime lexeme omits :SS, splice :00 in so 1.0.0 component-extraction stays valid." {
		// Local time without seconds: 07:32 -> 07:32:00 (also 07:32.123 -> 07:32:00.123)
		var timeMatch = reFind("^([0-9]{2}:[0-9]{2})(\.[0-9]+)?$", arguments.lexeme, 1, true);
		if (timeMatch.len[1] gt 0) {
			return mid(arguments.lexeme, 1, 5) & ":00" & mid(arguments.lexeme, 6, len(arguments.lexeme) - 5);
		}
		// Date+time without seconds: 1979-05-27T07:32 or with separator/tail (Z, .frac, +zone, etc.)
		// Match the date+time prefix followed by NOT-:-digit
		var dtMatch = reFind("^([0-9]{4}-[0-9]{2}-[0-9]{2}[Tt ][0-9]{2}:[0-9]{2})(?![:][0-9])", arguments.lexeme, 1, true);
		if (dtMatch.len[1] gt 0) {
			return mid(arguments.lexeme, 1, 16) & ":00" & mid(arguments.lexeme, 17, len(arguments.lexeme) - 16);
		}
		return arguments.lexeme;
	}

	// ----- number parsing -----

	public any function parseIntegerLexeme(required string lexeme, string int64Mode = "double", boolean strict = variables.jTrue) hint="Convert an INT token's raw lexeme to a CFML number, Java long, or decimal string per int64Mode. Applies strict-mode underscore validation." {
		var raw = arguments.lexeme;
		// Strip optional sign
		var sign = "";
		if (left(raw, 1) eq "+" || left(raw, 1) eq "-") {
			sign = left(raw, 1);
			raw = mid(raw, 2, len(raw) - 1);
		}
		// Determine base and strip prefix
		var base = 10;
		if (left(raw, 2) eq "0x") {
			base = 16;
			raw = mid(raw, 3, len(raw) - 2);
		} else if (left(raw, 2) eq "0o") {
			base = 8;
			raw = mid(raw, 3, len(raw) - 2);
		} else if (left(raw, 2) eq "0b") {
			base = 2;
			raw = mid(raw, 3, len(raw) - 2);
		}
		// Strict underscore validation
		if (arguments.strict) {
			if (left(raw, 1) eq "_" || right(raw, 1) eq "_") {
				throw(type="cfTOML.ParseError", message="Leading or trailing underscore in integer lexeme: '#arguments.lexeme#'");
			}
			if (find("__", raw) gt 0) {
				throw(type="cfTOML.ParseError", message="Consecutive underscores in integer lexeme: '#arguments.lexeme#'");
			}
		}
		// Leading-zero rejection for decimal integers (the spec allows `0` alone, but not `01`, `+01`, etc.).
		// Hex/octal/binary literals are not affected because they were already stripped of their `0x`/`0o`/`0b` prefix above.
		if (base eq 10 && len(raw) gt 1 && left(raw, 1) eq "0") {
			throw(type="cfTOML.ParseError", message="Leading zero not allowed in decimal integer '#arguments.lexeme#'");
		}
		// Strip underscores
		var digits = replace(raw, "_", "", "all");
		// Parse via java.lang.Long (more reliable than inputBaseN per spec section 4.5)
		var javaLong = createObject("java", "java.lang.Long").parseLong(sign & digits, base);
		if (arguments.int64Mode eq "javalong") {
			return javacast("long", javaLong);
		}
		if (arguments.int64Mode eq "string") {
			return javaLong.toString();
		}
		// "double" mode (default)
		return javaLong;
	}

	// ----- string escapes -----

	public string function decodeBasicStringEscapes(required string raw, string spec = "1.0.0") hint="Decode backslash escapes in a STRING_BASIC raw lexeme: named escapes (n, t, r, b, f, quote, backslash) and uXXXX/UXXXXXXXX unicode escapes. spec='1.1.0' enables \e and \xHH." {
		var out = "";
		var src = arguments.raw;
		var n = len(src);
		var i = 1;
		while (i lte n) {
			var c = mid(src, i, 1);
			if (c neq "\") {
				out &= c;
				i++;
				continue;
			}
			// We have a backslash; consume the next char as the escape code
			if (i + 1 gt n) {
				throw(type="cfTOML.ParseError", message="Truncated escape sequence at position #i#");
			}
			var esc = mid(src, i + 1, 1);
			if (esc eq "n") { out &= chr(10); i += 2; continue; }
			if (esc eq "t") { out &= chr(9); i += 2; continue; }
			if (esc eq "r") { out &= chr(13); i += 2; continue; }
			if (esc eq "b") { out &= chr(8); i += 2; continue; }
			if (esc eq "f") { out &= chr(12); i += 2; continue; }
			if (esc eq chr(34)) { out &= chr(34); i += 2; continue; }
			if (esc eq "\") { out &= "\"; i += 2; continue; }
			if (arguments.spec eq "1.1.0" && asc(esc) eq 101) {
				// \e - ESC U+001B (lowercase e, asc 101); TOML 1.1.0 only
				out &= chr(27);
				i += 2;
				continue;
			}
			if (arguments.spec eq "1.1.0" && asc(esc) eq 120) {
				// \xHH - 2-digit hex escape (lowercase x, asc 120); TOML 1.1.0 only
				if (i + 3 gt n) {
					throw(type="cfTOML.ParseError", message="Truncated \x escape at position #i#");
				}
				var hex2 = mid(src, i + 2, 2);
				if (!reFind("^[0-9A-Fa-f]{2}$", hex2)) {
					throw(type="cfTOML.ParseError", message="Invalid \x escape at position #i#: '#hex2#'");
				}
				out &= codePointToString(inputBaseN(hex2, 16));
				i += 4;
				continue;
			}
			if (asc(esc) eq 117) {
				// \u - 4-digit unicode (lowercase u, asc 117)
				if (i + 5 gt n) {
					throw(type="cfTOML.ParseError", message="Truncated \u escape at position #i#");
				}
				var hex4 = mid(src, i + 2, 4);
				if (!reFind("^[0-9A-Fa-f]{4}$", hex4)) {
					throw(type="cfTOML.ParseError", message="Invalid \u escape at position #i#: '#hex4#'");
				}
				var cp4 = inputBaseN(hex4, 16);
				if (cp4 gte 55296 && cp4 lte 57343) {
					throw(type="cfTOML.ParseError", message="Invalid \u escape at position #i#: U+#hex4# is in the surrogate range, not a valid Unicode scalar.");
				}
				out &= codePointToString(cp4);
				i += 6;
				continue;
			}
			if (asc(esc) eq 85) {
				// \U - 8-digit unicode (uppercase U, asc 85)
				if (i + 9 gt n) {
					throw(type="cfTOML.ParseError", message="Truncated \U escape at position #i#");
				}
				var hex8 = mid(src, i + 2, 8);
				if (!reFind("^[0-9A-Fa-f]{8}$", hex8)) {
					throw(type="cfTOML.ParseError", message="Invalid \U escape at position #i#: '#hex8#'");
				}
				var cp8 = inputBaseN(hex8, 16);
				if (cp8 gt 1114111) {
					throw(type="cfTOML.ParseError", message="Invalid \U escape at position #i#: U+#hex8# exceeds Unicode max U+10FFFF.");
				}
				if (cp8 gte 55296 && cp8 lte 57343) {
					throw(type="cfTOML.ParseError", message="Invalid \U escape at position #i#: U+#hex8# is in the surrogate range, not a valid Unicode scalar.");
				}
				out &= codePointToString(cp8);
				i += 10;
				continue;
			}
			throw(type="cfTOML.ParseError", message="Unknown escape sequence '\#esc#' at position #i#");
		}
		return out;
	}

	private string function codePointToString(required numeric codepoint) hint="Convert a Unicode scalar codepoint to a CFML string. Values above U+FFFF require a UTF-16 surrogate pair which CFML's chr() does not produce; delegating to Java's Character.toChars() handles both ranges correctly." {
		return createObject("java", "java.lang.String").init(createObject("java", "java.lang.Character").toChars(javacast("int", arguments.codepoint)));
	}

	public string function decodeMultiLineBasicEscapes(required string raw, string spec = "1.0.0") hint="Decode escapes in a STRING_ML_BASIC raw lexeme. Same as decodeBasicStringEscapes plus the backslash-newline line-continuation escape. spec='1.1.0' enables \e and \xHH." {
		var out = "";
		var src = arguments.raw;
		var n = len(src);
		var i = 1;
		while (i lte n) {
			var c = mid(src, i, 1);
			if (c neq "\") {
				out &= c;
				i++;
				continue;
			}
			if (i + 1 gt n) {
				throw(type="cfTOML.ParseError", message="Truncated escape sequence at position #i#");
			}
			var esc = mid(src, i + 1, 1);
			// Line-continuation: `\` followed by zero or more space/tab and then a newline.
			// The TOML spec requires the `\` to be the last non-whitespace character on its line, so
			// `\<space>x` (non-whitespace before any newline) is invalid even though `\<space><newline>` is fine.
			if (esc eq " " || esc eq chr(9) || esc eq chr(10) || esc eq chr(13)) {
				var j = i + 1;
				var sawNewline = javacast("boolean", 0);
				// Walk over space/tab until we find a newline or a non-whitespace character.
				while (j lte n) {
					var w = mid(src, j, 1);
					if (w eq chr(10) || w eq chr(13)) {
						sawNewline = javacast("boolean", 1);
						break;
					}
					if (w eq " " || w eq chr(9)) {
						j++;
						continue;
					}
					break;
				}
				if (!sawNewline) {
					throw(type="cfTOML.ParseError", message="Invalid escape '\<whitespace>' at position #i#: line-continuation requires a newline before any non-whitespace.");
				}
				// Consume the newline and any leading whitespace on subsequent lines.
				while (j lte n) {
					var w2 = mid(src, j, 1);
					if (w2 eq " " || w2 eq chr(9) || w2 eq chr(10) || w2 eq chr(13)) {
						j++;
					} else {
						break;
					}
				}
				i = j;
				continue;
			}
			// Standard escapes (same as decodeBasicStringEscapes)
			if (esc eq "n") { out &= chr(10); i += 2; continue; }
			if (esc eq "t") { out &= chr(9); i += 2; continue; }
			if (esc eq "r") { out &= chr(13); i += 2; continue; }
			if (esc eq "b") { out &= chr(8); i += 2; continue; }
			if (esc eq "f") { out &= chr(12); i += 2; continue; }
			if (esc eq chr(34)) { out &= chr(34); i += 2; continue; }
			if (esc eq "\") { out &= "\"; i += 2; continue; }
			if (arguments.spec eq "1.1.0" && asc(esc) eq 101) {
				// \e - ESC U+001B (lowercase e, asc 101); TOML 1.1.0 only
				out &= chr(27);
				i += 2;
				continue;
			}
			if (arguments.spec eq "1.1.0" && asc(esc) eq 120) {
				// \xHH - 2-digit hex escape (lowercase x, asc 120); TOML 1.1.0 only
				if (i + 3 gt n) {
					throw(type="cfTOML.ParseError", message="Truncated \x escape at position #i#");
				}
				var hex2 = mid(src, i + 2, 2);
				if (!reFind("^[0-9A-Fa-f]{2}$", hex2)) {
					throw(type="cfTOML.ParseError", message="Invalid \x escape at position #i#: '#hex2#'");
				}
				out &= codePointToString(inputBaseN(hex2, 16));
				i += 4;
				continue;
			}
			// CRITICAL: case-sensitive dispatch via asc() (CFML's eq is case-insensitive)
			if (asc(esc) eq 117) {
				// \u - 4-digit unicode (lowercase u, asc 117)
				if (i + 5 gt n) { throw(type="cfTOML.ParseError", message="Truncated \u escape at position #i#"); }
				var hex4 = mid(src, i + 2, 4);
				if (!reFind("^[0-9A-Fa-f]{4}$", hex4)) {
					throw(type="cfTOML.ParseError", message="Invalid \u escape at position #i#: '#hex4#'");
				}
				var cp4 = inputBaseN(hex4, 16);
				if (cp4 gte 55296 && cp4 lte 57343) {
					throw(type="cfTOML.ParseError", message="Invalid \u escape at position #i#: U+#hex4# is in the surrogate range, not a valid Unicode scalar.");
				}
				out &= codePointToString(cp4);
				i += 6;
				continue;
			}
			if (asc(esc) eq 85) {
				// \U - 8-digit unicode (uppercase U, asc 85)
				if (i + 9 gt n) { throw(type="cfTOML.ParseError", message="Truncated \U escape at position #i#"); }
				var hex8 = mid(src, i + 2, 8);
				if (!reFind("^[0-9A-Fa-f]{8}$", hex8)) {
					throw(type="cfTOML.ParseError", message="Invalid \U escape at position #i#: '#hex8#'");
				}
				var cp8 = inputBaseN(hex8, 16);
				if (cp8 gt 1114111) {
					throw(type="cfTOML.ParseError", message="Invalid \U escape at position #i#: U+#hex8# exceeds Unicode max U+10FFFF.");
				}
				if (cp8 gte 55296 && cp8 lte 57343) {
					throw(type="cfTOML.ParseError", message="Invalid \U escape at position #i#: U+#hex8# is in the surrogate range, not a valid Unicode scalar.");
				}
				out &= codePointToString(cp8);
				i += 10;
				continue;
			}
			throw(type="cfTOML.ParseError", message="Unknown escape sequence '\#esc#' at position #i#");
		}
		return out;
	}

	// ----- engine detection -----

	private string function detectEngine() hint="Returns 'adobe' | 'lucee' | 'boxlang'. Cached in variables.engine on init()." {
		var info = server;
		if (structkeyexists(info, "boxlang")) return "boxlang";
		if (structkeyexists(info, "lucee")) return "lucee";
		return "adobe";
	}

	private string function detectCaseSensitiveOrderedType() hint="Probe for engine support of an ordered case-sensitive structNew() type. Returns the type string or '' if no such type exists on this engine, or if the engine implements case-sensitive structs in a way that defeats the most common CFML access idiom (dot-notation). Only Adobe CF 2021+ qualifies in practice: Lucee 6/7 and BoxLang both return case-sensitive structs whose dot-notation accessor still uppercases the lookup key, so a key stored as 'title' cannot be read via .title - bracket access (struct['title']) works but breaks the principle of least surprise. Older Adobe (2016/2018), Lucee 5, and any engine without an ordered-casesensitive type return ''." {
		if (variables.engine neq "adobe") {
			return "";
		}
		var attempts = ["ordered-casesensitive", "linked-casesensitive", "casesensitive-ordered"];
		for (var t in attempts) {
			try {
				var probe = structNew(t);
				probe["aB"] = 1;
				probe["AB"] = 2;
				if (structcount(probe) eq 2) {
					return t;
				}
			} catch (any e) {
				// try next
			}
		}
		return "";
	}

	private struct function newDataStruct() hint="Create an ordered struct for parser-built TOML data. On CF2021+/BoxLang/Lucee with case-sensitive ordered support, distinct keys differing only in case ('section' vs 'Section') no longer collide. On older engines this falls back to the case-insensitive ordered '[:]' literal and the existing limitation applies." {
		if (len(variables.csOrderedType)) {
			return structNew(variables.csOrderedType);
		}
		return [:];
	}

}
