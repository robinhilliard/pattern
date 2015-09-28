/**
	Pattern is a library that supports pattern-based assignment,
	assertions and flow control. See the README for usage.

	(c) RocketBoots Pty Limited 2014

	This file is part of Pattern.

    Pattern is free software: you can redistribute it and/or modify
    it under the terms of the GNU Lesser General Public License as
    published by the Free Software Foundation, either version 3 of
    the License, or (at your option) any later version.

    Pattern is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Lesser General Public License for more details.

    You should have received a copy of the GNU Lesser General Public
    License along with Pattern.  If not, see
    <http://www.gnu.org/licenses/>.
 **/

component {

	// Useful character constants for clarity
	SINGLE_QUOTE = "'";
	DOUBLE_QUOTE = '"';
	FORWARD_SLASH = "/";
	BACKSLASH = "\";

	// Values for __pattern_type key in parse tree nodes
	LITERAL_STRING_TYPE = 0;    // Literal string
	LITERAL_NUMBER_TYPE = 1;    // Literal number
	LITERAL_RE_TYPE = 2;        // Regular expression
	LITERAL_RE_I_TYPE =3        // Regular expression with ignore case
	BIND_TYPE = 4;              // Variable name in scope
	BIND_RE_TYPE = 5;           // Regular expression with array to
								// bind group values to


	// Storage for parsed patterns
	_cache = {};

	// Can match overwrite existing variables?
	_mutableScope = true;

	// Factory for creating compiled patterns
	_regexPatternClass = createObject("java", "java.util.regex.Pattern");



	/**
		Constructor

		@param      boolean mutableScope (default true)
		@returns    instance

	 **/
	public Pattern function init(boolean mutableScope = true) {
		setMutableScope(mutableScope);
		return this;
	}



	/**
		If mutable scope is true, match() can assign new values from the
		source to existing variables in the destination scope.

		If mutable scope is false, existing variables in the destination
		scope become values to match against. If the values are not the
		same a NO_MATCH exception will be thrown, if they are the same
		match() does nothing.

		@param boolean mutableScope
	 **/
	public void function setMutableScope(boolean mutableScope) {
		_mutableScope = mutableScope;
	}



	/**
		Match the source to a pattern, throwing an exception if they do not match.
		If mutableScope is true, match binds variables in the scope to parts of the
		source so that the pattern matches. If mutableScope is false match compares
		the existing values in the scope with the source, and throws an exception if
		they do not match. See README for usage.

		@param      string patternCondition    pattern [when condition]
		@param      any source value to compare against pattern
		@param      any scope (optional) struct, local, variable, session, application
		@throws     NO_MATCH
		@throws     INVALID_PATTERN
		@returns    scope argument, or a new structure containing matched variables
		            if no scope was passed
	 **/
	public any function match(string patternCondition, any source, any scope = structNew()) {
		var pattern = "";
		var condition = "";
		var patternCondition = parsePatternConditionString(patternCondition);
		var tempScope = {};

		// The pattern has already been parsed
		pattern = patternCondition.pattern;
		condition = patternCondition.condition;

		if (condition eq "") {
			// without a condition we just do a regular _match()
			return _match(pattern, source, scope);

		} else {
			// Before we can assign variables to the real scope we
			// have to check the condition. Create a temporary scope,
			// copying values from original scope if it's immutable
			// so that _match() can check the existing values

			if (!_mutableScope)
				structAppend(tempScope, scope, true);

			_match(pattern, source, tempScope);
			tempScope.__pattern_condition = condition;

			// Now we can check the condition using the variables in
			// our temporary scope, and update the original if the
			// condition passed

			if (evaluateCondition(argumentCollection = tempScope)) {
				structDelete(tempScope, "__pattern_condition");
				structAppend(scope, tempScope, true);
				return scope;

			} else {
				throw(
					errorCode = "NO_MATCH",
					message = "Guard condition failed: #condition#"
				);
			}
		}
	}



	/**
		Helper function for match() which descends recursively through the parsed
		pattern, matching pattern components against the corresponding source element.

		The pattern is made up of "nodes" created by parsePatternString() and
		restoreLiterals(). Each node is a struct with a __pattern_type key set to
		one of the *_TYPE constants.

		@param      any pattern
		@param      any source value to compare against pattern
		@param      any scope struct, local, variable, session, application
     **/
	private any function _match(any pattern, any source, any scope) {
		var index = 0;
		var cacheKey = 0;
		var nextPattern = 0;
		var matcher = 0;
		var ins = 0;
		var groups = 0;

		if (isArray(pattern) and isArray(source)) {

			// Handle arrays

			for (index = arrayLen(pattern); index gt 0; index--) {

				// Check for tail syntax "| variableName" at end of array

				if (isStruct(pattern[index])
								and structKeyExists(pattern[index], "__pattern_type")
								and pattern[index].__pattern_type eq BIND_TYPE
								and left(pattern[index].__pattern_var, 1) eq "|") {
					if (index lt arrayLen(pattern)) {
						throw(
							errorCode = "INVALID_PATTERN",
							message = "Tail pattern #pattern[index].__pattern_var# must be in last position of array"
						);

					} else {
						if (arrayLen(source) lt index) {
							// Empty tail
							mutateScope(scope, listFirst(pattern[index].__pattern_var,"|"), []);
						} else {
							// One or more values remaining, copy to tail variable in scope
							mutateScope(scope, listFirst(pattern[index].__pattern_var,"|"),
								source.subList(index - 1, arrayLen(source)));
						}
					}
				} else {
					// Source array may be shorter than pattern
					if (index gt arrayLen(source)) {
						throw(
							errorCode = "NO_MATCH",
							message = "No match for array index #index#"
						);

					} else {
						// Match the pattern and source at index position
						_match(pattern[index], source[index], scope);
					}
				}
			}
		} else if (isStruct(pattern) and structKeyExists(pattern, "__pattern_type")) {

			// Handle structs, which may be real structs or parser "nodes"

			if (pattern.__pattern_type eq BIND_TYPE) {

				// Variable name to bind, ignore single underscores, but variables
				// starting with "_" are ok because CFML doesn't have Erlang convention

				if (pattern.__pattern_var neq "_")
					mutateScope(scope, pattern.__pattern_var, source);

			} else if (pattern.__pattern_type eq LITERAL_STRING_TYPE or
						pattern.__pattern_type eq LITERAL_NUMBER_TYPE) {

				// Check that literal values match

				if (pattern.__pattern_value neq source) {
					throw(
						errorCode = "NO_MATCH",
						message = "No match for literal #pattern.__pattern_value#"
					)
				}
			} else if (pattern.__pattern_type eq LITERAL_RE_TYPE or
						pattern.__pattern_type eq LITERAL_RE_I_TYPE) {

				// It's a literal regular expression with no bindings
				// Check that the source value matches the regex

				matcher = pattern.__pattern_compiled_regex.matcher(source);
				ins = pattern.__pattern_type eq LITERAL_RE_I_TYPE ? "in" : "";

				if (!matcher.matches()) {
						throw(
						errorCode = "NO_MATCH",
						message = "No match for case #ins#sensitive regex: #pattern.__pattern_value# source: #source#"
					)
				}

			} else if (pattern.__pattern_type eq BIND_RE_TYPE) {

				// It's a regular expression with a group binding array. Regex details
				// are inside the __pattern_re key (was easier to parse this way)

				matcher = pattern.__pattern_re.__pattern_compiled_regex.matcher(source);
				ins = pattern.__pattern_re.__pattern_type eq LITERAL_RE_I_TYPE ? "in" : "";

				if (!matcher.matches()) {
						throw(
						errorCode = "NO_MATCH",
						message = "No match for case #ins#sensitive regex: #pattern.__pattern_re.__pattern_value# source: #source#"
					)
				} else {

					// We need to get the group values from the matcher, copy them
					// into an array, and then match the array with bindings in
					// the pattern as if it were a regular array

					groups = [];

					for (index = matcher.groupCount(); index ge 0; index --)
						groups[index + 1] = matcher.group(index);

					_match(pattern.__pattern_group_bindings, groups, scope);
				}
			}

		} else if (isStruct(pattern) and (isStruct(source) or isObject(source))) {

			// Just a regular struct from the pattern, not a node

			for (index in pattern) {
				_match(pattern[index], source[index], scope);
			}
		}
		return scope;
	}



	/**
		Taking a source variable and a paired list of patterns and closures
		guard() finds a pattern matching the source and calls the paired
		closure, passing any bound variables from the pattern as arguments
		to the closure. See README for usage.

		@param any source to match against
		@param cases array of paired pattern strings and closures
		@throws PATTERN_EXPECTED
		@throws CLOSURE_EXPECTED
		@returns Return value from matching closure
	 **/
	public any function guard(any source, array cases) {
		var index = 1;
		var pattern = 0;
		var condition = 0;
		var bFound = 0;
		var len = 0;
		var pos = 0;
		var matched = 0;
		var closure = 0;

		// Iterate through pattern-closure pairs in cases array

		while (index le arrayLen(cases)) {
			if (not isSimpleValue(cases[index])) {
				throw (
					errorCode = "PATTERN_EXPECTED",
					message = "'pattern [when condition]' string expected in item #index#"
				);
			}

			pattern = cases[index];
			index++;

			// Catch NO_MATCH exceptions
			try {

				matched = match(pattern, source);

				if (not isClosure(cases[index])) {
					throw (
						errorCode = "CLOSURE_EXPECTED",
						message = "Closure expected in case item #index#"
					);

				} else {

					// Pass the matched variables to the closure
					// and return the result from the closure
					closure = cases[index];
					return closure(argumentCollection = matched);
				}

			} catch (error) {

				if (error.errorCode neq "NO_MATCH") {
					rethrow;
				}
			}

			index++;
		}
	}



	/**
		Convert the pattern string into a parsed tree of arrays, structs and
		nodes and cache the result (parsing is much slower than matching).

		@param patternCondition "pattern [when condition]"
		@returns parsed pattern (array or struct)
	 **/
	private any function parsePatternConditionString(patternCondition) {
		var cacheKey = hash(patternCondition);
		var el = "";
		var result = "";
		var originalPattern = "";
		var regexPattern = "";

		if (not structKeyExists(_cache, cacheKey)) {

			// Protect contents of literals from interpretation or modification
			el = escapeLiterals(patternCondition);
			patternCondition = el.template;

			// Separate "when" clause, if any - this is why "when" is reserved
			// result = {len = [bFound | len], pos = [_ | pos]}
			result = reFindNoCase("(.+?)\s+when\s+(.*)", patternCondition, 1, true);
			bFound = result.len[1];

			if (bFound eq 0) {

				// No "when" condition
				pattern = patternCondition;
				condition = "";

			} else {

				// There was a "when" condition
				pattern = mid(patternCondition, result.pos[2], result.len[2]);
				condition = mid(patternCondition, result.pos[3], result.len[3]);

				// Restore the original text of the literals in the condition
				condition = restoreLiterals(condition, el.escapedLiterals, true);
			}

			// Save for error message
			originalPattern = pattern;

			// Clean up white space in tail expressions
			pattern = reReplaceNoCase(pattern,  "\|\s+([a-z_]+)",
												",|\1",
												"all");

			// Re-arrange regular expressions with group binding arrays
			pattern = reReplaceNoCase(pattern,  "(##@@@@[0-9]\[[0-9]+\]##)\s+(\[[^]]+\])",
												"{__pattern_type = #BIND_RE_TYPE#, __pattern_re = \1, __pattern_group_bindings = \2}",
												"all");

			// Replace plain variable names with assignment nodes, leaving struct keys untouched
			pattern = reReplaceNoCase(pattern,
				"([a-z_|]+)\b(?!\s*=)",
				'{__pattern_type = #BIND_TYPE#, __pattern_var = "\1"}\2',
				"all");

			// Bring back string and numeric literals as "nodes"
			pattern = restoreLiterals(pattern, el.escapedLiterals);

			// Try to convert it back into structs, arrays etc for use during matching
			try {
				pattern = deserializeJSON(pattern);

			} catch (error) {
				throw (errorCode = "INVALID_PATTERN",
						message = "Could not parse pattern: #originalPattern#");
			}

			// Pre-compile any regular expressions using Java libraries
			// (wrap in struct in case top level is array)

			structFindKey({p = pattern}, "__pattern_type", "all").each(
				function(result) {
					var node = result.owner;
					try {
						switch(node.__pattern_type) {
							case 2: // LITERAL_RE_TYPE
								node.__pattern_compiled_regex =
									_regexPatternClass.compile(node.__pattern_value);
								break;

							case 3: // LITERAL_RE_I_TYPE (ignore case)
								node.__pattern_compiled_regex =
									_regexPatternClass.compile(node.__pattern_value,
										_regexPatternClass.CASE_INSENSITIVE);
								break;
						}
					} catch (error) {
						throw (errorCode = "INVALID_PATTERN",
								message = "Could not parse regular expression: #node.__pattern_value#");
					}
				}
			);

			// Cache all our hard (and slow) work
			_cache[cacheKey] = { pattern = pattern, condition = condition};
		}

		// Here's one we prepared earlier
		return _cache[cacheKey];
	}



	/**
		Replace string, number and regex literals in a string with distinct
		markers using a state machine, and return the modified string and
		an array of the replaced literals. All string literals are converted
		to double-quote delimiters to make later handling easier.

		The marker format is #@@@@T[I]# where T = type and I = index.

		This could be written more efficiently but the results are cached
		so it's not a high priority.

		@param  string source containing literals delimited by ', " and /
				characters, with \ used to escape delimiters embedded in
				literal
		@returns {template = 'string with markers', [value1, value2, ...]}
	 **/
	private struct function escapeLiterals(string source) {
		var c = "";
		var content = [];
		var output = [];
		var literals = [];
		var state = "OUTSIDE";
		var sourceIndex = 1;
		var sourceLength = len(source);

		source = listToArray(source, "");

		while (true) {
			if (sourceIndex > sourceLength) {

				// Return template and array of literals
				return {template = output.toList(""), escapedLiterals = literals};

			} else {
				c = source[sourceIndex];

				switch(state) {

					case "OUTSIDE":

						// Outside any literals

						if (c eq SINGLE_QUOTE) {
							content = [];
							state = "INSIDE_SINGLE";

						} else if (c eq DOUBLE_QUOTE) {
							content = [];
							state = "INSIDE_DOUBLE";

						} else if (c eq FORWARD_SLASH) {
							content = [];
							state = "INSIDE_RE";

						} else if ("-0123456789" contains c) {

							// Numbers are messier because they can finish without
							// a delimiter

							// Check for single character number edge-case

							if (sourceIndex < sourceLength) {
								content = [c];
								state = "NUMBER";

							} else {
								literals.append(content.toList("") & c);
								listToArray("##@@@@#LITERAL_NUMBER_TYPE#[#literals.len()#]##", "").each(function(s) {output.append(s)});
							}

						} else {
							output.append(c);
						}
						break;

					case "INSIDE_SINGLE":

						// In single quotes literal

						if (c eq SINGLE_QUOTE) {
							literals.append(DOUBLE_QUOTE & content.toList("") & DOUBLE_QUOTE); // All strings become double quoted
							listToArray("##@@@@#LITERAL_STRING_TYPE#[#literals.len()#]##", "").each(function(s) {output.append(s)});
							state = "OUTSIDE";

						} else if  (c eq BACKSLASH) {
							state = "INSIDE_SINGLE_ESCAPED";
						} else {
							content.append(c);
						}
						break;

					case "INSIDE_DOUBLE":

						// In double quotes literal

						if (c eq DOUBLE_QUOTE) {
							literals.append(DOUBLE_QUOTE & content.toList("") & DOUBLE_QUOTE); // All strings become double quoted
							listToArray("##@@@@#LITERAL_STRING_TYPE#[#literals.len()#]##", "").each(function(s) {output.append(s)});
							state = "OUTSIDE";
						} else if  (c eq BACKSLASH) {
							state = "INSIDE_DOUBLE_ESCAPED";
						} else {
							content.append(c);
						}
						break;

					case "INSIDE_RE":

						// In regular expression

						if (c eq FORWARD_SLASH) {
							literals.append(DOUBLE_QUOTE & content.toList("") & DOUBLE_QUOTE); // Still double quote RE pattern

							if (sourceIndex < sourceLength and lCase(source[sourceIndex + 1]) eq "i") {
								listToArray("##@@@@#LITERAL_RE_I_TYPE#[#literals.len()#]##", "").each(function(s) {output.append(s)});
								sourceIndex++; // skip "i"

							} else {
								listToArray("##@@@@#LITERAL_RE_TYPE#[#literals.len()#]##", "").each(function(s) {output.append(s)});
							}
							state = "OUTSIDE";

						} else if (c eq BACKSLASH) {
							content.append(c);
							state = "INSIDE_RE_ESCAPED";

						} else if (c eq DOUBLE_QUOTE) {
							listToArray("##DOUBLE_QUOTE##", "").each(function(s) {content.append(s)}); // Have to escape

						} else {
							content.append(c);
						}
						break;

					// Following cases are for ignoring character after a '\'

					case "INSIDE_SINGLE_ESCAPED":
						content.append(c);          // Don't need to escape, string being converted to double-quotes
						state = "INSIDE_SINGLE";
						break;

					case "INSIDE_DOUBLE_ESCAPED":
						listToArray("##DOUBLE_QUOTE##", "").each(function(s) {content.append(s)}); // Have to escape
						state = "INSIDE_DOUBLE";
						break;

					case "INSIDE_RE_ESCAPED":
						content.append(c);
						state = "INSIDE_RE";
						break;

					case "NUMBER":

						// In number literal

						// This code is repeated from above

						if ("0123456789.E+-" contains c) {

							// Check for last character number edge-case

							if (sourceIndex < sourceLength) {
								content.append(c);

							} else {
								literals.append(content.toList("") & c);
								listToArray("##@@@@#LITERAL_NUMBER_TYPE#[#literals.len()#]##", "").each(function(s) {output.append(s)});
							}

						} else {
							literals.append(content.toList(""));
							listToArray("##@@@@#LITERAL_NUMBER_TYPE#[#literals.len()#]##", "").each(function(s) {output.append(s)});
							state = "OUTSIDE";
							sourceIndex--; // Rewind non-number character
						}
				}
			}

			sourceIndex++;
		}
	}



	/**
		Re-interpolate literal values into a string containing markers created
		by escapeLiterals(). Either the original values or parse tree nodes will be
		inserted.

		@param  string template  string containing markers
		@param  array el escaped literals corresponding to marker indexes
		@param  boolean originalText if true replace markers with original text instead
				of parse nodes.
		@returns string where markers have been replaced

	 **/
	private string function restoreLiterals(string template, array el, originalText = false) {
		var exp = "";
		if (!el.len())
			return template;

		if (originalText)
			exp = "'#reReplace(template, "##@@@@[0-9]\[([0-9]+)\]##", "##el[\1]##", "ALL")#'";
		else
			exp = "'#reReplace(template, "##@@@@([0-9])\[([0-9]+)\]##", "{__pattern_type = \1, __pattern_value = ##el[\2]##}", "ALL")#'";

		// Replace the ##el[]## with values from the array
		return evaluate(exp);
	}



	/**
		Handle mutable and immutable scope processing differences.

		@param scope being updated
		@param key of variable in scope
		@param value new value
	 **/
	private void function mutateScope(any scope, string key, any value) {
		var i = 0;

		if (_mutableScope or not structKeyExists(scope, key)) {

			// Scope is mutable or key doesn't exist, no problems updating

			scope[key] = value;

		} else {

			// strict Erlang version - this is now a match with the value already in
			// the scope, not an assignment. We will compare simple values and arrays
			// only, anything else will be considered a non-match.

			if (isSimpleValue(scope[key]) and isSimpleValue(value) and scope[key] neq value) {
				throw(
					errorCode ="NO_MATCH",
					message ="Value '#value#' does not match existing value of #key# '#scope[key]#'"
				);

			} else if (isArray(scope[key]) neq isArray(value)) {
				throw(
					errorCode ="NO_MATCH",
					message ="Array and non-array values of #key# do not match"
				);

			} else if (isArray(scope[key]) and isArray(value)) {
				if (arrayLen(scope[key]) neq arrayLen(value)) {
					throw(
						errorCode ="NO_MATCH",
						message ="Array length #arrayLen(value)# of #key# does not match existing length #arrayLen(scope[key])#"
					);
				}

				for (i = value.len(); i > 0; i--)
					mutateScope({"#key#[#i#]" = scope[key][i]}, "#key#[#i#]", value[i]);

			} else if  (!isSimpleValue(scope[key]) or !isSimpleValue(value)) {
				throw(
					errorCode = "NO_MATCH",
					message = "Complex values of #key# will always be considered as non-matching"
				);
			}

		}
	}



	/**
		Evaluate condition in a closed context containing only
		the variables passed as arguments. The condition itself
		is passed in __pattern_condition argument.

		@params input variables to evaluate condition, and
				the condition in a __pattern_condition key.

		@returns boolean result of condition
	 **/
	private boolean function evaluateCondition() {
		return evaluate(arguments.__pattern_condition);
	}

}