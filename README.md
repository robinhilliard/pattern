# Pattern
Pattern is a CFC that supports pattern-based assignment,
assertions and flow control. It's like the love-child of `<cfset>`, `<cfif>`
and `<cfswitch>` with super powers. The idea is not new - I first encountered
it in the [Erlang][1] and more recently [Elixir][2] programming languages, but it
has been implemented in many other languages, usually of the functional or
declarative kind.

When I'm using languages other than Erlang I find that this is the feature I
miss the most, which is why I created this library. It was developed on Railo 4
but should work with any of the closure-supporting CFML engines with minor
tweaks. There is an extensive MX-Unit test case included if you want to migrate
to another engine - I'll gratefully accept any contributions provided.

_Robin Hilliard_

_email: robin\[at\][rocketboots.com][4]_

_twitter: [@robinhilliard][3]_

## Basic Assignment
The following two cfscript code examples have the same effect:

	message = "hello";

and

	p = new Pattern();
	p.match("message", "hello", variables);

The first argument is the pattern string, in this case a variable name. The second
argument is the value we are trying to match, and the third argument is the scope
we want to add our matches to.

## Tuple (Array) Assignments
Languages like Python allow multiple variable names on the left side of an equals
sign, which are matched up with corresponding parts of a list on the right side of
sign. So where we might normally write:

	a = 1;
	b = 2;

We can use pattern like this (leaving the instance creation out of this and
following examples for now):

	p.match("[a, b]", [1, 2], variables);
	
## Tail Assignments
If you want to glob all the array elements after a point into a single array
variable, you can write:

	p.match("a, b | tail]", [1, 2, 3, 4], variables);
	// a = 1, b = 2, tail = [3, 4]

## Struct Assignments
This also works for structures:

	s = {a = 1, b = 2};
	c = s.a;
	d = s.b;

can be written:

	p.match("{a = c, b = d}", {a = 1, b = 2}, variables);

## Nested Assignments
Patterns can be arbitrarily deep combinations of arrays and structs:

	s = {odd = [1, 3, 5], even = [2, 4, 6]};
	a = s.odd[1];
	b = s.even[1];
	c = s.odd[2];
	d = s.even[2];
	e = s.odd[3];
	f = s.even[3];

can be written:

	p.match("   {odd = [a, c, e], even = [b, d, f]}",
				{odd = [1, 3, 5], even = [2, 4, 6]},
				variables);

## A Note About Performance
Most of the work done by `match` involves the initial parsing of the pattern.
Once the parsing is done the pattern is cached for quick retrieval the next
time we encounter it. If using the cache a call similar to the nested assignment
example above will take under 70&#181;s to execute on a 2.3GHz i7 MacBook Pro.

To ensure you get the maximum performance benefit from the cache:

- Cache your Pattern instance in a shared scope so that the cache persists between
requests. The library is (intended to be) thread-safe
- Avoid constructing dynamic patterns if possible

## Ignoring Parts of the Source
Often you will not want to assign part of the source to a variable. The special
variable name `_` allows you to ignore part of the source:

	p.match("[a, _, b]", [1, 2, 3], variables); // set a = 1, b = 3

_Note for Erlang developers: only '\_' is ignored. Variables that start with an
underscore are not ignored because they are commonly used in CFML programs._

## Changing the Scope of the Result
To this point we have always passed `variables` as the third argument, but this
could be any scope that a variable can be added to, such as the `local` var scope
in a CFC method, or a structure you create:

	s = {a = 1, b = 2};
	t.c = s.a;
	t.d = s.b;

can be written:

	t = {};
	p.match("{a = c, b = d}", {a = 1, b = 2}, t);

The third argument is optional. If provided `match` returns the third argument,
if not `match` will default to returning a new struct containing the matches.
This means we can also write the last example as:

	t = p.match("{a = c, b = d}", {a = 1, b = 2});

## Basic Assertions
In the examples so far everything in the pattern has been a variable name. If we
put a literal value in the pattern, the match will only work if it matches the
corresponding element in the source. We can write:

	if ("hello" neq "hello")
		throw(errorCode = "NO_MATCH");

as:

	 // Note extra quotes in pattern marking literal
	p.match("'hello'", "hello");   

Assertions can be mixed together with assignments, so that we can check our
assumptions about the sources we're extracting data from. For example while
processing an array of people structs we might want to confirm that their status
was "member":

	p.match("{type = 'member',
		firstname = firstName,
		surname = surname}",
		people[i],
		variables);

If the type is member then the variables `firstname` and `surname` will be set,
otherwise a `NO_MATCH` exception will be thrown.

## When Assertions
Sometimes we'd like to assert something more complex than equality about the
source. For this we can add a conditional statement using the 'when' keyword:

	p.match("key when key gt 1", 2, variables);    // key = 2
	p.match("key when key gt 1", 1, variables);    // throws NO_MATCH
	
The condition can be anything you could write in CFML that results in a
boolean true/false result. 'When' can be added to any pattern.

## Immutable Scope Assertions
In the assignment examples, if the variable we were assigning to already existed
in the scope it would have been overwritten:

	surname = "Jekyl";
	p.match("surname", "Hyde", variables); // name = "Hyde"

We call surname 'mutable' because we were able to change (mutate) its value. However
we can change the behaviour of our Pattern instance to more closely mimic Erlang's
single, 'immutable' variable assignment by setting our Pattern instance's
mutableScope (default true) to false, either in the constructor argument or with
a setter:

	surname = "Jekyl";
	p.setMutableScope(false);
	
	// throws NO_MATCH because Jekyl != Hyde
	p.match("surname", "Hyde", variables); 

Here if the variable is already assigned in the scope, the assignment becomes a
match. Pattern will match simple values and arrays, anything else will be considered
a non-match. This is a way to make pattern matching dynamic without having to
recompile the pattern expression:

	// Set mutable scope to false in constructor
	p = new Pattern(false); 
	
	 // Set type in our scope to match against
	type = "member";       

	 // This will throw NO_MATCH if type != "member"
	p.match("{type = type,
		firstname = firstName,
		surname = surname}",
		people[i],
		variables);    

## Bonus: Regular Expressions
This is actually something Erlang doesn't do with patterns that seemed just too good
to leave out. We can make assertions about string sources with regular expressions:

	// NO_MATCH, case sensitive
	p.match("/P.TT..N/", "pattern", variables);  
	   
	// add 'i' for case insensitive
	p.match("/P.TT..N/i", "pattern", variables);    
	
Regular expression literals are delimited with forward slashes and an optional trailing
`i` for a case-insensitive search. We can also assign matching regex groups to
variables by appending an array to the regex:

	p.match("/\+([0-9]+)\s++([0-9]+)\s+([0-9 ]+)/
		[_, country, area, number]",
		"+61 2 9323 2500",
		variables);    
	
	// country = "61", area = "2", number = "9323 2500"
		
Note that we discard the first group which contains the entire match. All the other
stuff discussed so far (e.g. nesting, immutable scopes, tail, when) works with regular expression
groups - effectively the string is converted into an array of groups, and match
continues as if it was always an array.

Regular Expressions, if used, are pre-compiled along with the rest of the pattern,
so performance-wise they should actually be faster than the built-in CFML regex
functions on second and subsequent (cached) calls.

## Guards, Guards!
The third and final use of patterns in Erlang is for control flow, where patterns are 
used as function signatures and to control flow inside a function, like a switch
statement. A block of code only executes if the pattern at its head is satisfied, and
while it does it has access to local variables assigned from parts of the pattern.

Pattern provides a `guard()` method for this purpose. In CFML with closures this is
like a switch statement on steroids:
	
	people.each(
		function(person) {
			p.guard(person, [
				"{type = 'member',
				name =  /(Mr|Mrs|Ms) ([a-z]+) ([a-z])/i
						[_, title, _, surname]}",
				function() {
					writeLog(
					"Greetings #title# #surname#, your table is ready.");
				},
				"{type = 'banned',
				name =  /(Mr|Mrs|Ms) ([a-z]+) ([a-z])/i
						[_, _, first, _]}",
				function() {
					writeLog(
					"Get out of here #first# or I'll call the constabulary!");
				}
			]);
		}
	);
	
The `guard()` method takes two arguments: 

1. The source to match
2. An array containing pairs of pattern strings and closures to execute when the preceding
pattern is matched. All the assigned variables are passed as arguments to the closure, and do
not exist outside the closure.

Note that patterns are checked in order top to bottom, and that if none of the patterns match
guard will return nothing. It is standard practice to put some sort of catch-all pattern in
the final position to act as a default clause.

## Roadmap
- Custom tag versions of match and guard
- Bitfield patterns

## Troubleshooting
- Have you remembered to pass `variables` or `local` as the third argument if you're
expecting these scopes to update?
- `NO_MATCH` exceptions contain descriptions of why the match didn't work, have you
checked the description for clues?
- The word "when" is reserved and cannot be used as a variable name.
- The prefix "__pattern" is reserved and cannot be used to start a variable name.
- Are the unit tests passing?

[1]: http://www.erlang.org  "Erlang Programming Language"
[2]: http://elixir-lang.org "Elixir Programming Language"
[3]: http://twitter.com/robinhilliard "Robin on Twitter"
[4]: http://rocketboots.com "RocketBoots Website"