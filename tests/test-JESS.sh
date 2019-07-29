#!/bin/bash

# Test the correctness of the JESS.jq module, which must either be in a directory known to jq,
# or in the directory specified by -L PATHNAME
# Options:
# -L DIR
# --expected  # show the expected output
# --nullable  # --arg nullable true

VERSION="0.0.4"

NULLABLE=
EXPLAIN=

# Expected output:
function expected {
    cat <<EOF
[true,"correctly determined failure"]
["correctly determined failure","string"]
["DEBUG:","WARNING: null:0: unknown filter: goosub(a|b;A)"]
EOF
}

case "$1" in
    -L ) LOCATION="-L \"$2\""
	 shift 2
	 ;;
    --expected ) expected
	 exit
	 ;;
    --explain ) EXPLAIN="--arg explain true"
	shift
	;;
    --nullable ) NULLABLE="--arg nullable true"
	 shift
	 ;;
esac



jq -nc $LOCATION $NULLABLE $EXPLAIN 'include "JESS";
  def assert(value; msg):
    if value // false then empty else msg end;

  # An array of [INPUT, CONSTRAINT] pairs that are expected to fail
  def fail: [
    [ "correctly determined failure", "string"],

    [null,                            "nonnull"],                # whether nullable or not
    [true,                            false],

    [ 1,                              true],
    [ 1.5,                            2],
    [ {"a": [1,2,3,4]},               {a: [[], {unique: [1,2,3]}]}],
    [ {"answer": "YES"},              {"answer": ["&", {"enumeration": ["yes", "no", "NA"]}]} ],

    [ [true],                         ["foobar"] ],
    [ "b",                            ["&", {ascii_upcase: [[], {enumeration: ["A"]}]}] ],
    [ "b",                            ["&", {ascii_upcase: "A"}] ], 
    [ {id:"a", name:"b"} ,            ["&", {"has": "id"}, {"has": "name", "conforms_to": {"id": "string", name:"integer" } }]],
    [ {id:"a", name:0, "extra":0 },   ["&", {"includes": {id: "string", name: "string"}}] ],
    [ {id:"a"} ,                      ["&", {"includes": {id: "string", name: "string"}}] ],
    [ {id:"a"} ,                      ["&", { "::>=":    {id: "string", name: "string"}}] ],

    # check we get a WARNING:
    [ "a",                 ["&", {forall: {pipeline: ["goosub(a|b;A)" ]}, enumeration: ["A","B"]}] ],

    # [*1] compare below:
    ["c",       ["&", {forall: {pipeline: ["sub(\"a|b\";\"A\")" ]}, enumeration: ["A","B"]}] ],
    ["c",       ["&", {forall: {pipeline: ["sub(a|b;A)" ]}, enumeration: ["A","B"]}] ],

    ["-12",     "N" ],  # N is for naturals only

    [{"name":1, "id": 0},   ["&", {ifcond: {"has": "name"}, then: {"name": "string", "id": "integer"}} ]],

    ({id: 1, noname: "Name"}
     |
       [., [ "&", "object", {"if": ["&",  {has: "id"}], then: ["&", {has: "name"} ] }]] 
    )
  ];


  # An array of [INPUT, CONSTRAINT] pairs that are expected to pass
  def pass: [
    [true,              "correctly determined failure"],

    [null,              ["+", "null", "integer"]],                  # whether nullable or not

    [ 1.5,              1.5                                    ],
    [ [1,2],            ["integer"]                            ],   # ARRAY OF INTEGER
    [ 1,                [[], {"min":1}, "integer", "number"]   ],   # CONJUNCTION
    [ 1,                [[], {"and": ["integer", "number"]}]   ],   # CONJUNCTION
    [ [false, 1],       [[], {"length": 2}]                    ],   # LENGTH==2
    [ [false, 1],       ["integer", "boolean"]                 ],   # DISJUNCTION
    [ [false, 1],       [[], {"length": 2}, ["integer", "boolean"] ]],  # integer/boolean ARRAY OF LENGTH 2

    [ [],               [ "JSON" ]],
    [ [],               "array"],

    # array of (boolean or (integer and number))
    [[1,2],             ["boolean", [[], {"and": ["integer", "number"]}] ]],

    [ {a: 1},           {a: ["&", {enumeration: [1,2]} ] } ],
    # equivalent to:
    [ {a: 1},           {a: ["+", 1,2] } ],

    [ [{a: 1}, {a:2}],  ["&", { forall: ".[][]", max: 2}] ],
    [ {a: 1},           ["&", {forall: ".[a]", enumeration: [1,2] } ] ],

    [ ["08550", "08550"],   [ "/^[0-9]{5}$/" ] ],
    [ "X",             "/x/i" ],
    ["12",             "N" ],    # cf. above

    [ [{a: 1}, {a:2}],  ["&", {setof: ".[]|.[a]", enumeration: [[1,2]] } ] ],
    [ [{a: 1}, {a:2}],  ["&", {setof: ".[]|.[a]", subsetof: [1,2] } ] ],
    [ [{a: 1}, {a:2}],  ["&", {setof: ".[]|.[a]", subsetof: [2,1] } ] ],

    [ "a|b",            ["&", { "forall": {"pipeline": ["splits(\"|\")" ]},  "ascii_downcase": true } ] ],
    [ "a,b",            ["&", { "forall": "splits(\",\")",  "ascii_downcase": true } ] ],

    [{"a":"X"},         ["&", {ifcond: {"has": "a"}, then: {"a": "string"} } ] ],

    [1,                 ["&", {forall: {pipeline: [3, 2]}, enumeration: [2]}] ],
    [1,                 ["&", {forall: "2|3.5", enumeration: [3.5]}] ],

  # Compare [*1] above
   (("a","b") |  
      [.,       ["&", {forall: {pipeline: ["sub(\"a|b\";\"A\")" ]}, enumeration: ["A","B"]}] ],
      [.,       ["&", {forall: {pipeline: ["sub(a|b;A)" ]}, enumeration: ["A","B"]}] ] 
   ),

   [ "a",               ["&", {forall: {pipeline: [".", "sub(a|b;A)" ]}, enumeration: ["A","B"]}] ],

   [{"a": [null] },     {a: ["null", "number"] }               ],   # ARRAY OF - DISJUNCTION
   [{"a": 1},           {a: [[], {min:0, max:10} ]}            ],

   [{"a": 1},           {a: [[], {min:0, max:10}, "integer"]}  ],

   [{"a": [1,2,3]},     {a: [[], {distinct: true}]}            ],
   [{"a": [1,2,3]},     {a: [[], {unique: [1,2,3]}]}           ],
   [ ["&", {}, "boolean"],  "constraint"                       ],
   [ [[], {}, ["boolean"]], "constraint"                       ],
   [ {"answer": "yes"}, {"answer": ["&", {"enumeration": ["yes", "no", "NA"]}]} ],

   [1,                  ["&", {if: "number", then: ["+", 0, 1]}] ],

   # When a string, .enumeration computes the array of the values produced by the pipeline and so is more like "enumeration of"
   [ {"enumeration": [1,2], "a":1},   ["&", {"forall": ".[a]", "enumeration": ".[enumeration][]" }] ],

   # An integrity constraint:
   [ {objects: [{id: 1, name: "A"}, {id:2, name: "B"},  {id:3, name: "C"} ],
      relations: [[1,2], [2,3]] },
      ["&", {setof: ".[relations][][]|integers", subsetof: ".[objects][]|.[id]"}] ],

  ({id: 1, name: "Name"}
    | [., [ "&", "object", {"if": ["&",  {has: "id"}], then: ["&", {has: "name"} ] }]] 
  )

  ];

  ### Proceed:
  (pass[] | . as [$in, $c]  | assert($in | conforms_to($c); .)),
  (fail[] | . as [$in, $c]  | assert($in | conforms_to($c) | not; .)),

  # "$ARGS.named.nullable is \($ARGS.named.nullable)",

  (if $ARGS.named.nullable
   then ([null, "integer"] | . as [$in, $c] | assert($in | conforms_to($c); .)),
        ([null, "/ab/"   ] | . as [$in, $c] | assert($in | conforms_to($c); .))
   else
        ([null, "integer"] | . as [$in, $c] | assert($in | conforms_to($c) | not; .)),
        ([null, "/ab/"   ] | . as [$in, $c] | assert($in | conforms_to($c) | not; .)),
        ([null, ["+", "null", "integer"]] | . as [$in, $c]  | assert($in | conforms_to($c); .))
   end )
'
