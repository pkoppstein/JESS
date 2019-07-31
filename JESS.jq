module {
  "name": "JESS",
  "description": "Conformance checker for JSON Extended Structural Schemas",
  "version": "0.0.1.10",
  "homepage": "",
  "license": "MIT",
  "author": "pkoppstein at gmail dot com",
  "repository": {
    "type": "hg", 
    "url":  "https://bitbucket.org/pkoppstein/JESS",
  }
};

# JESS - JSON Extended Structural Schemas
# Date: 2019-07-25
# For documentation, see JESS.txt

# Requires: jq 1.5 or higher

# The main entry points are defined at the end of this file and include:

# check                       # check(inputs)
# check(stream)               # presupposes $schema
# check_schemas               # check_schemas(inputs)
# check_schemas(stream)       # multiple schemas specified in $schema
# conforms_to(t)              # JSON objects must conform exactly
# inclusively_conforms_to(t)  # JSON objects may have additional keys

# Usage examples:
# jq --argfile schema MYSCHEMA.JSON 'include "JESS"; check' STREAM_OF_JSON_DOCUMENTS
# jq --argfile schema MYSCHEMA.JSON --argfile prelude PRELUDE.json 'include "JESS"; check' STREAM_OF_JSON_DOCUMENTS

# WARNING: The specification of the named types "base64" and "ISO8601Date" is subject to change.

# NEWS:
# 1.5 | conforms_to(1.5)
# .ifcond # can be specified as an alternative to, or in addition to, .if
# "scalar"
# $nullable
# .[M:N]
# numerous jq filters added, including range/1, range/2, range/3
# "||" for parallel evaluation

# NOTE: if pipelines can only be formed from strings but in certain
#       contexts, an object with a "pipeline" key can be specified:
#       .enumeration .subsetof .equals_setof .supersetof

#################################

def nullable:
  $ARGS.named.nullable;

def assert($assertion; etc):
  if $assertion then .
  elif $ARGS.named.explain
  then etc | debug
  else .
  end
  | $assertion;

def assert($assertion; $msg; $v1):
  assert($assertion; "\($msg): \($v1)");

def assert($assertion; $msg; $v1; $v2):
  assert($assertion; "\($msg): \($v1):")
  | assert($assertion; $v2);

def expecting($type; $condition):
  assert($condition;
         "expecting type \($type) but got"; .);

# Customization is via an object provided e.g. via --slurpfile prelude prelude.json
# The object might look like:
# {
#   "metadata": {...},
#    "types" {
#      "Date": "^(-?(?:[1-9][0-9]*)?[0-9]{4})-(1[0-2]|0[1-9])-(3[01]|0[1-9]|[12][0-9])T(2[0-3]|[01][0-9]):([0-5][0-9]):([0-5][0-9])([.,][0-9]+)?(Z)?$",
#      "md5": "^[a-f0-9]{32}$"
#    }
# }
#
# Always return an object
def prelude:
  # add objects but raise an error if different values are found at any one key:
  def safelyAdd:
    def sa: .[0] as $a | .[1] as $b
      | reduce ($b|keys_unsorted[]) as $k ($a;
          if has($k) and ($b|has($k)) and (.[$k] != $b[$k])
          then "safelyAdd found different values at key \"\($k)\": \(.[$k]) vs \($b[$k])" | error
          else .[$k] = $b[$k]
          end) ;
     reduce (.[]) as $x (null; [., $x]|sa) ;
  def safelyAddTypes:
     (map( {types} ) | safelyAdd | .types) as $types
     | add
     | .types = $types ;
    
  ($ARGS.named.prelude | select(. != "" ) // {})
  | if type == "object" then . else safelyAddTypes end ;

# Always return an object 
def preludeTypes:
  prelude.types // {};

# Notable points:
# T and the decimal fraction are optional;
# a valid time-zone can be specified;
# a period rather than a comma must be used as the decimal marker;
# the specification is currently purely syntactic.
def is_ISO8601Date:
  test("^(-?([1-9][0-9]*)?[0-9]{4})-(1[0-2]|0[1-9])-(3[01]|0[1-9]|[12][0-9])[T ](2[0-3]|[01][0-9]):([0-5][0-9]):([0-5][0-9])(\\.[0-9]+)?"
       + "(Z|[-+][0-9][0-9](:?[0-9][0-9])?)?" );


# pipe(pipeline) evaluates a pipeline of filters specified by the argument, which may
# be a string, an array, or an object.
#
# The filters are limited to those explicitly recognized by this function, as described below.
#
# If `pipeline` is an array, the array elements specify the filters to be applied.

# If the first item in the array is "||", then the remaining items are all evaluated in parallel,
# and the result is assembled into an array, e.g.

# {"a": 0, "b": 1 } | pipe( ["||", ".[a]", ".[b]" ] )             #=> [0,1]

# {"a": 0, "b": 1 } | pipe( ["||", {"x": ".[a]", "y": ".[b]"} ] ) #=> [{"x": 0, "y": 1}]

# Otherwise, evaluation of the items, say p1, p2, ..., is as if by `p1 | p2 | ...`
# except that if any of these elements, say pi, is itself an array, 
# then the result of evaluating pi is an array of the items produced by the pipeline
# composed of the elements of pi.  Here are two examples:
#
#    "abc" | pipe( [[ "split(\"\")" ]] ) is equivalent to the jq expression `"abc" | [ split("") ]`
#
#    "abc" | pipe( [ ["split(\"\")"], "length"] ) evaluates to 1

# If `pipeline` is a string, the pipe-character "|" is used to split
# the string naively, and so the pipe character cannot be used within
# any argument of any filter specified this way.

# If `pipeline` is a JSON object, it is simply returned.  This makes
# it possible to insert JSON strings and JSON arrays into the pipeline
# as well.  For example,

# `pipe( [{"s": "LITERAL"}, ".[s]"])` would  evaluate to `"LITERAL"`.

# A literal JSON string may also be included within a pipeline directly
# by adding escaped double-quotation marks, e.g.
# `"0|\"LITERAL\""` would evaluate to `"LITERAL"`;
#
# If unrecognized filters are specified, the schema is regarded as invalid,
# and an error condition may be raised.
# Any other type of error encountered during evaluation will result in a value of null.
#
# The recognized filters are of the following four types:
# 1. References to well-known jq filters of arity 0, e.g. "ascii_downcase", "debug", "$ARGS"
# 2. References to most jq filters of arity greater than 0 that have string arguments,
#    e.g. split, splits, sub, gsub, etc
# 3. range/0, range/1, range/2
# 4. Specially-defined filters with the semantics defined by jq expressions, e.g.
#    "first" : if type == "string" then .[0:1] else first end
#    "last"  : if type == "string" then .[-1:] else last end
#    and similarly for "integers", "numbers", "nonnull"
# 5. Any of the above followed by one or more occurrences of `[]`.
# 6. `.`, `..`, `.[]`, .[keyname], .[integer], [M: ], [ :N], [M:N]
#
def pipe(pipeline):

  def jsonstring: "(((?<=\\\\)\")|[^\"])*"; # excluding the outer quotation marks

  def trim: if type == "string" then sub("^ +";"") | sub(" +$";"") else . end;

  def parseMcolonN:
    def ton: if type == "string" and test("[0-9]") then tonumber else . end;
    capture( "^ *(?<m>-? *[0-9]*) *: *(?<n>-? *[0-9]*) *$" ) // false
    | if .
      # avoid the bug in map_values when ? is used
      then map_values(ton)
      else .
      end ;

  def slice($m; $n):
    if $m|type == "number"
    then if $n|type == "number" then .[$m : $n ] else .[$m : ] end
    else if $n|type == "number" then .[ : $n ] else .[0: ] end
    end;

  # capture one arg, making the use of string quotation marks somewhat optional
  def captureArg($functor):
        capture("^ *(?<f>" + $functor + ")[(] *\"(?<x>" + jsonstring + ")\" *[)]$" )
     // capture("^ *(?<f>" + $functor + ")[(](?<x>"     + jsonstring +     ")[)]$" )
     // null;

  # capture two or three args, making the use of string quotation marks somewhat optional
  def captureArgs($functor):
        capture("^ *(?<f>" + $functor + ")[(] *\"(?<a>" + jsonstring + ")\" *; *\"(?<b>" + jsonstring + ")\" *(; *(?<c>" + jsonstring + ")\")? *[)]$" )
     // capture("^ *(?<f>" + $functor + ")[(](?<a>"     + jsonstring +         ");(?<b>" + jsonstring +       ")(;(?<c>" + jsonstring +     "))?[)]$" )
     // null;
  
  # sub/2, sub/3, gsub/2, gsub/3
  def sub_or_gsub(f):
    (f | captureArgs("sub|gsub")) as $p
    | if $p.f  == "gsub" then if $p.c then gsub($p.a; $p.b; $p.c) else gsub($p.a; $p.b) end
      elif $p.f == "sub" then if $p.c then  sub($p.a; $p.b; $p.c) else  sub($p.a; $p.b) end
      else null
      end ;

  def range_numbers(f):
    def num: "[0-9]+([.][0-9]*)?";
    (f | capture("^ *range[(] *(?<a>\(num)) *(; *(?<b> *\(num)) *(; *(?<c> *\(num)))?)? *[)]" ) // null) as $p
    | if $p
      then if   $p.c then range($p.a | tonumber; $p.b | tonumber; $p.c | tonumber)
           elif $p.b then range($p.a | tonumber; $p.b | tonumber)
           else           range($p.a | tonumber)
	   end
      else null
      end ;

  # workaround for bug in jq 1.6
  def isnumber:
    type == "number"
    or (type == "string" and try (tonumber | true) catch false) ;

  def eval(f):
    # (f|debug) as $debug
    # | debug |
    if f == "true" then true
    elif f == "false" then false
    elif f | type | (. == "boolean" or . == "null" or . == "number") then f
    elif f|isnumber then f|tonumber
    elif (f|type) == "array" and (f[0]|type == "array") then [ pipe(f[0]) ] | eval( f[1:] )
    elif (f|type) == "array"
    then if f == [] then . else eval(f[0]) | eval( f[1:] ) end
    elif (f|type) == "object" then f
    elif f == "." or f == "" then .
    elif f == "[]" then []              # perhaps should be an error
    elif f == ".[]" then .[]
    elif f == ".." then ..
    elif f == "$ARGS" then $ARGS
    elif f == "add" then add
    elif f == "all" then all
    elif f == "any" then any
    elif f == "arrays" then arrays
    elif f == "ascii_downcase" then ascii_downcase
    elif f == "ascii_upcase" then ascii_upcase
    elif f == "booleans" then booleans
    elif f == "ceil" then ceil
    elif f == "combinations" then combinations
    elif f == "debug" then debug
    elif f == "empty" then empty
    elif f == "exp" then exp
    elif f == "exp10" then exp10
    elif f == "explode" then explode
    elif f == "fabs" then fabs
    elif f == "finites" then finites
    elif f == "first" then if type == "string" then .[0:1] else first end
    elif f == "flatten" then flatten
    elif f == "floor" then floor
    elif f == "from_entries" then from_entries
    elif f == "fromdate" then fromdate
    elif f == "fromdateiso8601" then fromdateiso8601
    elif f == "fromjson" then fromjson
    elif f == "gmtime" then gmtime
    elif f == "implode" then implode
    elif f == "infinite" then infinite
    elif f == "integers" then select( (type=="number") and (floor == .) )
    elif f == "isfinite" then isfinite
    elif f == "isinfinite" then isinfinite
    elif f == "isnan" then isnan
    elif f == "isnormal" then isnormal
    elif f == "iterables" then iterables
    elif f == "keys" then keys
    elif f == "keys_unsorted" then keys_unsorted
    elif f == "last" then if type == "string" then .[-1:] else last end
    elif f == "length" then length  # serves to compute abs
    elif f == "log" then log
    elif f == "log10" then log10
    elif f == "log1p" then log1p
    elif f == "log2" then log2
    elif f == "logb" then logb
    elif f == "max" then max
    elif f == "min" then min
    elif f == "mktime" then mktime
    elif f == "normals" then normals
    elif f == "not" then not
    elif f == "nonnull" then select(. != null)
    elif f == "nulls" then nulls
    elif f == "numbers" then numbers
    elif f == "objects" then objects
    elif f == "paths" then paths
    elif f == "pow10" then pow10
    elif f == "reverse" then reverse
    elif f == "round" then round
    elif f == "scalars" then scalars
    elif f == "sort" then sort
    elif f == "sqrt" then sqrt
    elif f == "strings" then strings
    elif f == "to_entries" then to_entries
    elif f == "todate" then todate
    elif f == "todateiso8601" then todateiso8601
    elif f == "tojson" then tojson
    elif f == "tonumber" then tonumber
    elif f == "tostring" then tostring
    elif f == "transpose" then transpose
    elif f == "trunc" then trunc
    elif f == "type" then type
    elif f == "unique" then unique
    elif f == "utf8bytelength" then utf8bytelength
    elif f == "values" then values
    elif f | endswith("[]") then eval(f[:-2]) | .[]

    # arity-1 functions
    else (f|captureArg("capture|endswith|has|join|ltrimstr|match|rstrimstr|scan|splits?|startswith|test")) as $p
    | if $p then
                   if   $p.f == "capture"    then capture( $p.x )
                   elif $p.f == "endswith"   then endswith( $p.x )
                   elif $p.f == "has"        then has( $p.x )
                   elif $p.f == "join"       then join( $p.x )		   
                   elif $p.f == "ltrimstr"   then ltrimstr( $p.x )
                   elif $p.f == "match"      then match( $p.x )
                   elif $p.f == "rtrimstr"   then rtrimstr( $p.x )
                   elif $p.f == "scan"       then scan( $p.x )		   
                   elif $p.f == "split"      then split( $p.x )
                   elif $p.f == "splits"     then splits( $p.x )
                   elif $p.f == "startswith" then startswith( $p.x )
                   elif $p.f == "test"       then test( $p.x )
		   else "internal error processing arity-1 functions: $p is \($p)" | debug
                   end
      # .[foo] or .[N] or .[M:N] etc, without ignoring spaces within the square brackets
      else (f | capture( "^ *[.]\\[(?<x>.+)\\] *$") // null) as $p
      | if $p
        then if type == "array" and ($p.x | test("^-?[0-9]+$"))
             then .[ $p.x | tonumber ]
             else ($p.x | parseMcolonN) as $q
             | if $q then slice($q.m; $q.n)
               else .[ $p.x ]
               end
             end
        else sub_or_gsub(f)
        // range_numbers(f)
        // ("WARNING: \(input_filename):\(input_line_number): unknown filter: \(f)" | debug | not )
        end
      end
    end ;

    # If $x is an object, then process its values in parallel, otherwise just run pipe($x)
    def inparallel($x):
     . as $in
     | if ($x|type) == "object" then $x | map_values(. as $p | $in | pipe($p))
       else pipe($x)
       end;

    # START OF BODY of def pipe
    if (pipeline|type == "object") then .
    elif (pipeline|type == "array") then
      if (pipeline|.[0]) == "||" then [ (pipeline|.[1:][]) as $p | inparallel($p) ]
      else eval(pipeline|map(trim))
      end
    elif (pipeline|type == "string")
    then (pipeline|trim) as $p
    | (if ($p|index("|")) then $p | split("|") | map(trim)
       else $p
       end ) as $p
    | eval($p)
    else pipeline|error // null
    end ;


# If type == "object" and (t|type) == "object" then
# `conforms_to(t; true)` is true only if the conformity is exact.
# 
def conforms_to(t; exactly):
  # Within this function, conforms_to(t) is dependent on `exactly`:
  def conforms_to(t): conforms_to(t; exactly);

  # Does . have the form of an array-defined constraint?
  def isConjunction: type == "array" and (.[0] | . == {} or . == [] or . == "&");

  # Does . have the form of a disjunction?
  def isDisjunction: (type == "array") and length > 0 and (isConjunction|not);

  def isUnion: type == "array" and length>1 and .[0] == "+" ;

  def isCompound: isConjunction or isDisjunction or isUnion;
  
  # Does . have the form of a JESS type?
  # isExtendedType returns true for strings since any string is potentially a type name.
  def isExtendedType:
    if type == "string" then true
    elif isConjunction or isUnion then all(.[1:][]; isExtendedType)
    elif type =="array" then all(.[]; isExtendedType)
    else true
    end ;

  def isRegexType:
    type == "string" and startswith("/") and test("/[mix]*$");
      
  # Use the ^/.../[mix]$ convention
  def conforms_with_regex_type(t):
    def parseAsRegex:
      if endswith("/") then { re: .[1:-1], m: "" }
      else capture("/(?<re>.*)/(?<m>[^/]*)$")
      end // null;
    # the nullable possibility should be handled elsewhere
    (type == "string")
    and (t | parseAsRegex) as $p
    | $p and if $p.m then test($p.re; $p.m) else test($p.re) end ;

  # ::==
  # . and t are both assumed to be objects and t is to be interpreted as a structural constraint
  def conforms_with_object_exactly(t):
    . as $in
    | (keys == (t|keys)) and
      all(keys[]; . as $k | $in[$k] | conforms_to(t[$k]));

  # ::>= i.e. . might have more keys than t
  # . and t are both assumed to be objects and t is to be interpreted as a structural constraint
  def conforms_with_object_inclusively(t):
    . as $in
    | ((t|keys) - keys) == [] and
      all(t|keys_unsorted[]; . as $k | $in[$k] | conforms_to(t[$k]));

  # ::<= i.e. t might have more keys than .
  def conforms_with_object_minimally(t):
    . as $in
    | all(keys[]; . as $k | (t | has($k))) and
      all(keys[]; . as $k | $in[$k] | conforms_to(t[$k]));

  # {if: TYPE, ifcond: COND, then: TYPE, else: TYPE}
  def conforms_with_conditional($c):
    def conforms_with_constraint($constraint): conforms_to(["&", $constraint]);

    def check($cond):
       if $cond
       then conforms_to($c.then)
       elif $c.else then conforms_to($c.else)
       else true  # modus ponens
       end;

    ($c.if == null or (conforms_to($c.if) as $cond | check($cond)))
    and ($c.ifcond == null or (conforms_with_constraint($c.ifcond) as $cond | check($cond))) ;

  # $c is an object-defined constraint, possibly with a .forall
  def conforms_with_constraint($c):

    # Is . directly evaluable as a pipeline?
    def isEvaluable:
      type == "string" or type == "array";

    def stringOrObject: type == "string" or type == "object";

    def when(cond; action): if cond? // false then action? // false else true end;

    # resolve_pipeline/2 is a helper function for { enumeration: X } etc.
    # It returns $c with .[$key] set to the resolved value,
    # but if $arrayp then the resolved value must be an array.
    # If $c[$key] is a string, it is evaluated as a pipeline;
    # if $c[$key] is an object, it should have a "pipeline" key;
    # if $c[$key] is an array, $c is returned.
    def resolve_pipeline($c; $key; $arrayp):
      def magic($p):
        [pipe($p)] as $set
	| if $arrayp 
          then if ($set | (length == 1 and (.[0]|type == "array")))
               then ($c | .[$key] = $set[0])
               else "run-time error at .\($key): pipeline did not yield an array" | debug | null
	       end
	  else ($c | .[$key] = $set)
          end ;
      $c[$key] as $x
      | if    $x|type == "string"                  then magic($x)
        elif ($x|type == "object") and $x.pipeline then magic($x.pipeline)
        elif $x|type == "array"  then $c
        else "run-time error at .\($key) with value \($x) with type \($x|type)" | debug | null
        end;

    def conforms_with_constraint_ignore_pipeline:
      # ("conforms_with_constraint entry: \(.)" | debug) as $debug |
      when ($c.if or $c.ifcond; conforms_with_conditional($c))
      and when($c.length; length == $c.length)
      and when($c.schema; conforms_to($c.schema))
      and when($c.minLength; length >= $c.minLength)
      and when($c.maxLength; length <= $c.maxLength)
      and when($c.max; . <= $c.max)
      and when($c.min; . >= $c.min)
      and when($c.maxExclusive; . < $c.maxExclusive)
      and when($c.minExclusive; . > $c.maxExclusive)

      and when($c.conforms_to; conforms_to($c.conforms_to))
      and when($c.includes; conforms_with_object_inclusively($c.includes))  # ::>=  # redundant
      and when($c["::>="]; conforms_with_object_inclusively($c["::>="]))    # ::>=
      and when($c["::<="]; conforms_with_object_minimally($c["::<="]))      # ::<=
      and when($c.keys; $c.keys | unique == keys)
      and when($c.keys_unsorted; $c.keys_unsorted == keys_unsorted)
 
      and when($c.ascii_upcase == true; . == ascii_upcase)
      and when($c.ascii_upcase | type == "string"; $c.ascii_upcase == ascii_upcase )

      and when($c.ascii_downcase == true; . == ascii_downcase)
      and when($c.ascii_downcase | type == "string"; $c.ascii_downcase == ascii_downcase)

      # allow $c.ascii_upcase and $c.ascii_downcase to be a CONJUNCTION 
      and when($c.ascii_upcase | isConjunction; ascii_upcase | conforms_to($c.ascii_upcase))
      and when($c.ascii_downcase | isConjunction; ascii_downcase | conforms_to($c.ascii_downcase))

      and when($c.oneof;       . as $in | $c.oneof | index([$in]))  # isin
      and when($c.enumeration; . as $in | any($c.enumeration[]; . == $in))
      and when($c.distinct == true; sort == unique)         # {distinct: true}
      and when($c.unique   == true; sort == unique)         # {unique: true}
      and when($c.unique and ($c.unique|type) == "array"; (sort == unique) and (. - $c.unique) == [])

      and when( ($c.has) and ($c.has|type)=="string"; has($c.has))
      and when($c.has and ($c.has|type)=="array"; . as $in | all($c.has[]; . as $key | $in | has($key)))

      and when($c.first; if type=="string" then $c.first == .[0:1] else $c.first == first end)
      and when($c.last ; if type=="string" then $c.last  == .[-2:] else $c.last  == last  end)

      and when($c.startswith; startswith($c.startswith))
      and when($c.endswith; endswith($c.endswith))

      and when($c.base64 == true; . ==  try (@base64d | @base64) // false)

      and when($c.equal; . == $c.equal)
      and when($c["=="]; . == $c["=="])
      and when($c.notequal; . != $c.notequal)
      and when($c["!="]; . != $c["!="])
      
      and when($c["<="]; . <= $c["<="])
      and when($c[">="]; . >= $c[">="])

      and when($c.subsetof;  (unique - ($c.subsetof|unique) == []) )

      and when($c.equals_setof; ($c.equals_setof|unique) == unique)
      and when($c.supersetof; ($c.supersetof|unique) - unique == [])
      and when($c.sub | (type == "array" and length == 3);
               if $c.sub[2] | type == "string"
	       then sub($c.sub[0]; $c.sub[1]) == $c.sub[2]
	       else sub($c.sub[0]; $c.sub[1]) | conforms_to($c.sub[2])
	       end )
      and when($c.sub | (type == "array" and length > 3);
               if $c.sub[2] | type == "string"
	       then sub($c.sub[0]; $c.sub[1]; $c.sub[2]) == $c.sub[3]
	       else sub($c.sub[0]; $c.sub[1]; $c.sub[2]) | conforms_to($c.sub[3])
	       end )

      and when($c.gsub | (type == "array" and length == 3);
               if $c.gsub[2] | type == "string"
	       then gsub($c.gsub[0]; $c.gsub[1]) == $c.gsub[2]
	       else gsub($c.gsub[0]; $c.gsub[1]) | conforms_to($c.gsub[2])
	       end )
      and when($c.gsub | (type == "array" and length > 3);
               if $c.gsub[2] | type == "string"
	       then gsub($c.gsub[0]; $c.gsub[1]; $c.gsub[2]) == $c.gsub[3]
	       else gsub($c.gsub[0]; $c.gsub[1]; $c.gsub[2]) | conforms_to($c.gsub[3])
	       end )

      and when($c.test | type=="string"; test($c.test))
      and when($c.test | type=="object" and (.not|type=="string");
               test($c.test.not) | not )

      and when($c.regex;
          if $c.modifier then test($c.regex; $c.modifier)
          else test($c.regex)
          end )
      and when($c.add; add == $c.add)
      and when($c.and;  # conjunction
               . as $in | all($c.and[]; . as $c | $in | conforms_to($c))) ;

    # START OF BODY of conforms_with_constraint
    # If .subsetof is a string or object, then evaluate it with respect to `.`
    if $c.subsetof | stringOrObject
    then resolve_pipeline($c; "subsetof"; false) as $cprime
    | if $cprime then conforms_with_constraint($cprime) else null end    
    # ... and similarly with .equals_setof etc
    elif $c.equals_setof | stringOrObject
    then resolve_pipeline($c; "equals_setof"; false) as $cprime
    | if $cprime then conforms_with_constraint($cprime) else null end    
    elif $c.supersetof | stringOrObject
    then resolve_pipeline($c; "supersetof"; false) as $cprime
    | if $cprime then conforms_with_constraint($cprime) else null end    

    # .enumeration should be evaluated with respect to the original input,
    # so checking .enumeration should PRECEDE checking .forall
    elif $c.enumeration | stringOrObject
    then resolve_pipeline($c; "enumeration"; true) as $cprime
    | if $cprime then conforms_with_constraint($cprime) else null end

    elif $c.forall
    # if the pipeline emits nothing, there is nothing to be checked
    then all( pipe($c.forall)? ; conforms_with_constraint_ignore_pipeline)

    # $c.setof is a special case:
    elif $c.setof
    then [ pipe($c.setof)? ] | unique | conforms_with_constraint($c | del(.setof) )
    else conforms_with_constraint_ignore_pipeline
    end ;

  # $c is assumed to be a CONJUNCTION
  def conforms_with_conjunction($c):
    . as $in
    | all( $c[1:][];
          . as $constraint
	  | if type == "object" # objects here are interpreted as constraint objects
	      then $in | conforms_with_constraint($constraint)
	    else # preserve full generality
              $in | conforms_to($constraint)
            end) ;

  # DISJUNCTION:
  # If t is [] then there is no constraint, otherwise check if . is in any of t[]
  def in_any(t):
    (t|length == 0) or
    . as $x | any( t[]; . as $type | $x | conforms_to($type)) ;

  # START OF BODY of conforms_to
  if type == t then true
  elif t == "nonnull" then . != null                           # check "nonnull" early
  elif . == null and nullable and (t|isCompound|not) then true # so regex-defined types would be nullable too
  elif (t == true or t == false or t == null) then . == t      # boolean values and null can represent themselves
  elif t == "number" or t == "boolean" or t == "string" or t == "object" or t == "array" or t == "null" then type == t
  elif (t | type) == "number" then t == .                      # numbers also represent themselves
  elif t == "JSON" then true
  elif t == "nonnegative" then (type == "number" and . >= 0)
  elif t == "positive" then (type == "number" and . >= 0)
  elif t == "integer" then (type == "number" and floor == .)
  elif t == "N" then (type == "string" and test("^[1-9][0-9]+$")) # naturals
  elif t == "Z" then (type == "string" and test("^-?[0-9]+$"))    # integers
  elif t == "numeric" then (type == "string" and (tonumber|tostring) == .)
  elif t == "nonNegativeInteger" then (type == "number" and floor == . and . >= 0)
  elif t == "positiveInteger" then  (type == "number" and floor == . and . > 0)
  elif t == "scalar" then  (type | (. != "object" and . != "array"))
  elif t == "ISO8601Date" then is_ISO8601Date
  elif t == "token" then (test("[\n\r\t]")|not) and (test("^ ")|not) and (test(" $")|not) and (test(" ")|not)
  elif t == "constraint" then isExtendedType  # TODO - elaborate
  elif t | isRegexType then conforms_with_regex_type(t)
  elif (t|type) == "string"
    then preludeTypes[t] as $pt
    | if $pt|type == "string" then test($pt)
      elif $pt|isExtendedType then conforms_to($pt)
#      elif $pt|isConjunction then conforms_to($pt)
#      elif $pt | (type == "object" and .pipeline)
#      then ($pt.pipeline) as $pipe
#      | if pipe($pipe) then true else false end
      else "invalid prelude at \(t)" | debug | not
      end
  elif t|isUnion       then in_any(t[1:])
  elif t|isConjunction then conforms_with_conjunction(t)

  elif type == "object" and (t|type) == "object" then
    if exactly
    then conforms_with_object_exactly(t)
    else conforms_with_object_inclusively(t)
    end
  elif type == "array" and (t|type) == "array" then
    # DISJUNCTION
    all(.[]; in_any(t))
  else false
  end ;

#### Main entry points

def conforms_to(t): conforms_to(t; true);

def inclusively_conforms_to(t): conforms_to(t; false);

def check(stream):
  foreach stream as $in ({n: 0, error: 0, this: false};
    .n+=1
    | .this=false
    | if $in|conforms_to($schema) then . else .this=true | .error+=1 end;
    select(.this)
    | "Schema mismatch #\(.error) at \(input_filename):\(input_line_number): entity #\(.n):", $in ) ;

def check: check(inputs);

# Multiple schemas
def conforms_to_schemas(schemas; exactly):
  . as $in | all(schemas; . as $schema | $in | conforms_to($schema; exactly));

def conforms_to_schemas(schemas):
  conforms_to_schemas(schemas; true);

# check against $schemas -- an array of schemas
def check_schemas(stream):
  conforms_to_schemas($schemas[]; true);
  
def check_schemas: check_schemas(inputs);

