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

component extends="mxunit.framework.TestCase" {

	SINGLE_QUOTE = "'";
	DOUBLE_QUOTE = '"';



	function setup() {
		p = new Pattern();
	}



	function teardown() {
		structDelete(variables, "p");
	}



	function testInstance() {
		assert(isInstanceOf(p, 'Pattern'));
	}



	function testPerformance() {
		var start = getTickCount();

		for (i = 1000; i > 0; i--) {
			p.match('{one = one, two = "two", three = [three]}', {one = 1, two = 'two', three = [3]});
		}

		assert((getTickCount() - start) / 1000 < 0.07); // average less than 70µs per call
	}



	function testUnderscoreMatchesAny() {
		assert(structKeyList(p.match("_", "value")) eq "");
		assert(structKeyList(p.match("_", {key = "value"})) eq "");
		assert(structKeyList(p.match("_", ["value"])) eq "");
	}



	function testMatchLiteralString() {
		assert(structKeyList(p.match("'value'", "value")) eq "");
		assert(structKeyList(p.match('"value"', "value")) eq "");
	}



	function testDoesntMatchLiteralString() {
		assertThrows(
			function () {p.match("'value'", "other value")},
			"NO_MATCH");

		assertThrows(
			function () {p.match('"value"', "other value")},
			"NO_MATCH");
	}



	function testMatchLiteralNumber() {
		assert(structKeyList(p.match(7, 7)) eq "");
		assert(structKeyList(p.match(-7, -7)) eq "");
		assert(structKeyList(p.match(7.0, 7)) eq "");
	}



	function testDoesntMatchLiteralNumber() {
		assertThrows(
			function () {p.match(7, 8)},
			"NO_MATCH");

		assertThrows(
			function () {p.match(-7, -8)},
			"NO_MATCH");

		assertThrows(
			function () {p.match(7.0, 8.0)},
			"NO_MATCH");
	}



	function testMatchLiteralArray() {
		assert(structKeyList(p.match("[1,2,3]", [1,2,3])) eq "");
		assert(structKeyList(p.match("['a','b','c']", ["a","b","c"])) eq "");
	}



	function testSingleAssignment() {
		assert(p.match("key", "value").key eq "value");
	}



	function testSingleAssignmentToScope() {
		scope = {};
		p.match("key", "value", scope);
		assert(scope.key eq "value");
	}



	function testSingleAssignmentToVariables() {
		p.match("key", "value", variables);
		assert(key eq "value");
	}



	function testSingleAssignmentToLocal() {
		p.match("key", "value", local);
		assert(key eq "value");
	}



	function testMultipleArrayAssignment() {
		result = p.match("[one, 'two', three, four]", [1, "two", 3, 4]);
		assert(result.one eq 1);
		assert(result.three eq 3);
		assert(result.four eq 4);
		result = p.match('[one, "two", three, four]', [1, "two", 3, 4]);
		assert(result.one eq 1);
		assert(result.three eq 3);
		assert(result.four eq 4);
	}



	function testMultipleStructAssignment() {
		result = p.match("{one = one, two=two, three= three, four =four}", {one = 1, two = 2, three = 3, four = 4});
		assert(result.one eq 1);
		assert(result.two eq 2);
		assert(result.three eq 3);
		assert(result.four eq 4);
	}



	function testNestedArrayStruct() {
		result = p.match("[one, 'two', {three = three}]", [1, 'two', {three = 3}]);
		assert(result.one eq 1);
		assert(result.three eq 3);
	}



	function testNestedStructArray() {
		result = p.match('{one = one, two = "two", three = [three]}', {one = 1, two = 'two', three = [3]});
		assert(result.one eq 1);
		assert(result.three eq 3);
	}



	function testTail() {
		result = p.match("[one, two | tail]", [1, 2, 3, 4]);
		assert(result.one eq 1);
		assert(result.two eq 2);
		assert(result.tail[1] eq 3);
		assert(result.tail[2] eq 4);
	}



	function testWhen() {
		result = p.match("key when key gt 1", 2);
		assert(result.key eq 2);

		assertThrows(
			function () {p.match("key when key gt 1", 1)},
			"NO_MATCH",
			"Guard condition failed: key gt 1"
		);
	}



	function testRegex() {
		p.match("/PHONE [0-9]+ [0-9 ]+/i",
				"phone 0123 456 789");

		assertThrows(
			function () {p.match("/PHONE/", "phone")},
			"NO_MATCH",
			"No match for case sensitive regex: PHONE source: phone"
		);

		assertThrows(
			function () {p.match("/[0-9]+ [0-9 ]+/i", "0123 4X6 789")},
			"NO_MATCH",
			"No match for case insensitive regex: [0-9]+ [0-9 ]+ source: 0123 4X6 789"
		);
	}



	function testRegexBinding() {
		p.match("/([0-9]+) ([0-9 ]+)/ [_, area, number]",
				"0123 456 789",
				variables);

		assert(area eq "0123");
		assert(number eq "456 789");

		assertThrows(
			function () {p.match("/[0-9]+ [0-9 ]+/ [_, area, number]", "0123 4X6 789")},
			"NO_MATCH",
			"No match for case sensitive regex: [0-9]+ [0-9 ]+ source: 0123 4X6 789"
		);
	}



	function testGuard() {
		person = {type = "member", name="Mr Robin Hilliard"};

		result = p.guard(person, [

				"{type = 'member',
				name = /(Mr|Mrs|Ms) ([a-z]+) ([a-z]+)/i [_, title, _, surname]}",
				function() {
					return "Greetings #title# #surname#, your table is ready.";
				},

				"{type = 'banned',
				name = /(Mr|Mrs|Ms) ([a-z]+) ([a-z]+)/i [_, _, first, _]}",
				function() {
					return "Get out of here #first# or I will call the constabulary!";
				}
			]);

		assert(result eq "Greetings Mr Hilliard, your table is ready.");

		person = {type = "banned", name="Mr Robin Hilliard"};

		result = p.guard(person, [

				"{type = 'member',
				name = /(Mr|Mrs|Ms) ([a-z]+) ([a-z]+)/i [_, title, _, surname]}",
				function() {
					return "Greetings #title# #surname#, your table is ready.";
				},

				"{type = 'banned',
				name = /(Mr|Mrs|Ms) ([a-z]+) ([a-z]+)/i [_, _, first, _]}",
				function() {
					return "Get out of here #first# or I will call the constabulary!";
				}
			]);

		assert(result eq "Get out of here Robin or I will call the constabulary!");
	}



	// Private Methods

	function testParsePatternConditionString() {
		p = makePublic(p, "parsePatternConditionString", "_parsePatternConditionString");
		result = p._parsePatternConditionString("a when b");
		assert(result.pattern.__pattern_var eq "a");
		assert(result.condition eq "b");
	}



	function testEscapeLiterals() {
		p = makePublic(p, "escapeLiterals", "_escapeLiterals");

		result = p._escapeLiterals("a 'single quoted i.e. \' character' value");
		assert(result.template eq "a ##@@@@0[1]## value");
		assert(result.escapedLiterals.len() eq 1);
		assert(result.escapedLiterals[1] eq '"single quoted i.e. #SINGLE_QUOTE# character"');

		result = p._escapeLiterals('a "double quoted i.e. \" character" value');
		assert(result.template eq "a ##@@@@0[1]## value");
		assert(result.escapedLiterals.len() eq 1);
		assert(result.escapedLiterals[1] eq '"double quoted i.e. ##DOUBLE_QUOTE## character"');

		result = p._escapeLiterals(7);
		assert(result.template eq "##@@@@1[1]##");
		assert(result.escapedLiterals.len() eq 1);
		assert(result.escapedLiterals[1] eq 7);

		result = p._escapeLiterals("7 -13.92 3922.292E4");
		assert(result.template eq "##@@@@1[1]## ##@@@@1[2]## ##@@@@1[3]##");
		assert(result.escapedLiterals.len() eq 3);
		assert(result.escapedLiterals[1] eq 7);
		assert(result.escapedLiterals[2] eq -13.92);
		assert(result.escapedLiterals[3] eq 3922.292E4);
	}



	function testRestoreLiterals() {
		p = makePublic(p, "restoreLiterals", "_restoreLiterals");

		result = p._restoreLiterals("##@@@@0[1]## ##@@@@0[2]##", ["'restored'", 7]);
		assert(result eq "{__pattern_type = 0, __pattern_value = 'restored'} {__pattern_type = 0, __pattern_value = 7}");

		result = p._restoreLiterals("##@@@@0[1]##", ['"restored"']);
		assert(result eq '{__pattern_type = 0, __pattern_value = "restored"}');
	}



	function testMutateEmptyScope() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {};
		p._mutateScope(scope, "key", "value");
		assert(scope.key eq "value");

	}



	function testMutateMatch() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = "value"};
		p._mutateScope(scope, "key", "value");
		assert(scope.key eq "value");

	}



	function testMutateNoMatch() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = "another value"};

		assertThrows(
			function() {p._mutateScope(scope, "key", "value");},
			"NO_MATCH"
		);

	}



	function testMutateArrayNotArray() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = "value"};

		assertThrows(
			function() {p._mutateScope(scope, "key", ["value"]);},
			"NO_MATCH",
			"Array and non-array values of key do not match"
		);

		scope = {key = ["value"]};

		assertThrows(
			function() {p._mutateScope(scope, "key", "value");},
			"NO_MATCH",
			"Array and non-array values of key do not match"
		);

	}



	function testMutateArrayLengths() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = [1, 2]};

		assertThrows(
			function() {p._mutateScope(scope, "key", [1]);},
			"NO_MATCH",
			"Array length 1 of key does not match existing length 2"
		);

	}



	function testMutateArrayMatch() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = [1, "two", 3, "four"]};
		p._mutateScope(scope, "key", [1, "two", 3, "four"]);
		assert(scope.key[1] eq 1);
		assert(scope.key[2] eq "two");
		assert(scope.key[3] eq 3);
		assert(scope.key[4] eq "four");
	}



	function testMutateArrayNoMatch() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = [1, "bazinga", 3, "four"]};

		assertThrows(
			function() {p._mutateScope(scope, "key", [1, "two", 3, "four"]);},
			"NO_MATCH",
			"Value 'two' does not match existing value of key[2] 'bazinga'"
		);

	}



	function testMutateComplex() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = {}};

		assertThrows(
			function() {p._mutateScope(scope, "key", "value");},
			"NO_MATCH",
			"Complex values of key will always be considered as non-matching"
		);

		scope = {key = "value"};

		assertThrows(
			function() {p._mutateScope(scope, "key", {});},
			"NO_MATCH",
			"Complex values of key will always be considered as non-matching"
		);

	}



	function testMutateNestedArrayMatch() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = [1, "two", [3, "four"], 5]};
		p._mutateScope(scope, "key", [1, "two", [3, "four"], 5]);
		assert(scope.key[1] eq 1);
		assert(scope.key[2] eq "two");
		assert(scope.key[3][1] eq 3);
		assert(scope.key[3][2] eq "four");
		assert(scope.key[4] eq 5);
	}



	function testMutateNestedArrayNoMatch() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = [1, "two", [3, "bazinga"], 5]};

		assertThrows(
			function() {p._mutateScope(scope, "key", [1, "two", [3, "four"], 5]);},
			"NO_MATCH",
			"Value 'four' does not match existing value of key[3][2] 'bazinga'"
		);

	}


	function testMutateNestedComplex() {
		p = makePublic(p, "mutateScope", "_mutateScope");
		p.setMutableScope(false);

		scope = {key = [1, "two", [3, {}], 5]};

		assertThrows(
			function() {p._mutateScope(scope, "key", [1, "two", [3, "bazinga"], 5]);},
			"NO_MATCH",
			"Complex values of key[3][2] will always be considered as non-matching"
		);

		scope = {key = [1, "two", [3, "bazinga"], 5]};

		assertThrows(
			function() {p._mutateScope(scope, "key", [1, "two", [3, {}], 5]);},
			"NO_MATCH",
			"Complex values of key[3][2] will always be considered as non-matching"
		);

	}



	// Test helper methods

	private function assertThrows(testFunction, string errorCode, message = "") {
		try {
			testFunction();
			fail("Did not throw #errorCode#");

		} catch (error) {
			if (error.errorCode neq errorCode) {
				fail("Threw #error.errorCode# instead of #errorCode#");
			}
			if (message neq "" and (error.message neq message)) {
				fail("Error message text incorrect: #error.message#");
			}

		}
	}


}