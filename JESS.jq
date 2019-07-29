module {
  "name": "JESS",
  "description": "Conformance checker for JSON Extended Structural Schemas",
  "version": "0.0.1.9",
  "homepage": "",
  "license": "MIT",
  "author": "pkoppstein at gmail dot com",
  "repository": {
    "type": "hg", 
    "url":  "https://bitbucket.org/pkoppstein/JESS",
  }
};

# JESS - JSON Extended Structural Schemas
# Date: 2019-07-24
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
# If `pipeline` is an array, the array elements specify the sequence of filters to be applied.
# If `pipeline` is a string, the pipe-character "|" serves to delimit the filters, and therefore
# the pipe character cannot be used within any argument of any filter specified this way.
# If `pipeline` is an object, then it should contain an array-valued key named "pipeline",
# and pipe(pipeline.pipeline) is evaluated.
# If unrecognized filters are specified, the schema is regarded as invalid,
# and an error condition may be raised.
# Any other type of error encountered during evaluation will result in a value of null.
#
# The recognized filters are of the following four types:
# 1. References to well-known jq filters of arity 0, e.g. "ascii_downcase", "debug"
# 2. References to certain jq filters of arity greater than 0: split splits sub gsub
# 3. Specially-defined filters with the semantics defined by jq expressions, e.g.
#    "first" : if type == "string" then .[0:1] else first end
#    "last"  : if type == "string" then .[-1:] else last end
#    and similarly for "integers", "numbers", "nonnull"
# 4. Any of the above followed by one or more occurrences of `[]`.
# 5. `.`, `..`, `.[]`, .[keyname], .[integer], [M: ], [ :N], [M:N]
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

  # sub/2, sub/3, gsub/2, gsub/3
  def sub_or_gsub(f):
    (f | capture( "^(?<g>g?)sub[(] *\"(?<a>" + jsonstring + ")\" *; *\"(?<b>" + jsonstring + ")\" *(; *(?<c>" + jsonstring + ")\")? *[)]$" )
      // capture( "^(?<g>g?)sub[(](?<a>"     + jsonstring +         ");(?<b>" + jsonstring +       ")(;(?<c>" + jsonstring +     "))?[)]$" )
      // null ) as $p
    | if $p
      then if $p.g == "g" 
           then if $p.c then gsub($p.a; $p.b; $p.c) else gsub($p.a; $p.b) end
           else if $p.c then  sub($p.a; $p.b; $p.c) else  sub($p.a; $p.b) end
	   end
      else null
      end 
      // null
      ;

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
    elif (f|type) == "array"
    then if f == [] then . else eval(f[0]) | eval( f[1:] ) end
    elif (f|type) == "object"
    then if f.pipeline == null then . else pipe(f.pipeline) end
    elif f == "." or f == "" then .
    elif f == "[]" then []              # perhaps should be an error
    elif f == ".[]" then .[]
    elif f == ".." then ..
    elif f == "add" then add
    elif f == "all" then all
    elif f == "any" then any
    elif f == "arrays" then arrays
    elif f == "ascii_downcase" then ascii_downcase
    elif f == "ascii_upcase" then ascii_upcase
    elif f == "debug" then debug
    elif f == "first" then if type == "string" then .[0:1] else first end
    elif f == "fromjson" then fromjson
    elif f == "integers" then select( (type=="number") and (floor == .) )
    elif f == "keys" then keys
    elif f == "last" then if type == "string" then .[-1:] else last end
    elif f == "length" then length  # serves to compute abs
    elif f == "max" then max
    elif f == "min" then min
    elif f == "not" then not
    elif f == "nonnull" then select(. != null)
    elif f == "numbers" then select(type == "number")
    elif f == "objects" then objects
    elif f == "paths" then paths
    elif f == "scalars" then scalars
    elif f == "sort" then sort
    elif f == "strings" then strings
    elif f == "tojson" then tojson
    elif f == "tonumber" then tonumber
    elif f == "tostring" then tostring
    elif f == "to_entries" then to_entries
    elif f == "type" then type
    elif f == "unique" then unique
    elif f == "values" then values
    elif f | endswith("[]") then eval(f[:-2]) | .[]
    else (f | capture( "^(?<split>splits?)[(] *\"(?<x>.*)\"\\ *[)]$" ) 
           // capture( "^(?<split>splits?)[(](?<x>.*)[)]$" )
           // null) as $p
    | if $p
      then if $p.split == "splits" then splits( $p.x )
           else split( $p.x )
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
	     // ("WARNING: \(input_filename):\(input_line_number): unknown filter: \(f)" | debug | not )
        end
      end
    end ;

    # START OF BODY of def pipe
    if (pipeline|type == "object")
    then if pipeline.pipeline
         then (pipeline.pipeline | map(trim)) as $p | pipe($p)
         else .
	 end
    elif (pipeline|type == "array") then eval(pipeline|map(trim))
    elif (pipeline|type == "string")
    then (if pipeline|index("|")
             then pipeline|split("|") | map(trim)
             else pipeline|trim
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
    (type == "string")    # the nullable possibility should be handled elsewhere
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

  # c is an object-defined constraint, possibly with a .forall
  def conforms_with_constraint(c):

    # arrays are potentially evaluable too, but here we need a predicate for use with keys that are normally arrays
    def isEvaluable:
      type == "string" or type == "object";
      
    def when(cond;action): if cond? // false then action? // false else true end;

    def conforms_with_constraint_ignore_pipeline:
      # ("conforms_with_constraint entry: \(.)" | debug) as $debug |
      
      when (c.if or c.ifcond; conforms_with_conditional(c))
      and when(c.length; length == c.length)
      and when(c.schema; conforms_to(c.schema))
      and when(c.minLength; length >= c.minLength)
      and when(c.maxLength; length <= c.maxLength)
      and when(c.max; . <= c.max)
      and when(c.min; . >= c.min)
      and when(c.maxExclusive; . < c.maxExclusive)
      and when(c.minExclusive; . > c.maxExclusive)

      and when(c.conforms_to; conforms_to(c.conforms_to))
      and when(c.includes; conforms_with_object_inclusively(c.includes))  # ::>=  # redundant
      and when(c["::>="]; conforms_with_object_inclusively(c["::>="]))    # ::>=
      and when(c["::<="]; conforms_with_object_minimally(c["::<="]))      # ::<=
      and when(c.keys; c.keys | unique == keys)
      and when(c.keys_unsorted; c.keys_unsorted == keys_unsorted)
 
      and when(c.ascii_upcase == true; . == ascii_upcase)
      and when(c.ascii_upcase | type == "string"; c.ascii_upcase == ascii_upcase )

      and when(c.ascii_downcase == true; . == ascii_downcase)
      and when(c.ascii_downcase | type == "string"; c.ascii_downcase == ascii_downcase)

      # allow c.ascii_upcase and c.ascii_downcase to be a CONJUNCTION 
      and when(c.ascii_upcase | isConjunction; ascii_upcase | conforms_to(c.ascii_upcase))
      and when(c.ascii_downcase | isConjunction; ascii_downcase | conforms_to(c.ascii_downcase))

      and when(c.oneof;       . as $in | c.oneof | index([$in]))  # isin
      and when(c.enumeration; . as $in | any(c.enumeration[]; . == $in))
      and when(c.distinct == true; sort == unique)         # {distinct: true}
      and when(c.unique   == true; sort == unique)         # {unique: true}
      and when(c.unique and (c.unique|type) == "array"; (sort == unique) and (. - c.unique) == [])

      and when( (c.has) and (c.has|type)=="string"; has(c.has))
      and when(c.has and (c.has|type)=="array"; . as $in | all(c.has[]; . as $key | $in | has($key)))

      and when(c.first; if type=="string" then c.first == .[0:1] else c.first == first end)
      and when(c.last ; if type=="string" then c.last  == .[-2:] else c.last  == last  end)

      and when(c.startswith; startswith(c.startswith))
      and when(c.endswith; endswith(c.endswith))

      and when(c.base64 == true; . ==  try (@base64d | @base64) // false)

      and when(c.equal; . == c.equal)
      and when(c["=="]; . == c["=="])
      and when(c.notequal; . != c.notequal)
      and when(c["!="]; . != c["!="])
      
      and when(c["<="]; . <= c["<="])
      and when(c[">="]; . >= c[">="])

      and when(c.subsetof;  (unique - (c.subsetof|unique) == []) )

      and when(c.equals_setof; (c.equals_setof|unique) == unique)
      and when(c.supersetof; (c.supersetof|unique) - unique == [])
      and when(c.sub | (type == "array" and length == 3);
               if c.sub[2] | type == "string"
	       then sub(c.sub[0]; c.sub[1]) == c.sub[2]
	       else sub(c.sub[0]; c.sub[1]) | conforms_to(c.sub[2])
	       end )
      and when(c.sub | (type == "array" and length > 3);
               if c.sub[2] | type == "string"
	       then sub(c.sub[0]; c.sub[1]; c.sub[2]) == c.sub[3]
	       else sub(c.sub[0]; c.sub[1]; c.sub[2]) | conforms_to(c.sub[3])
	       end )

      and when(c.gsub | (type == "array" and length == 3);
               if c.gsub[2] | type == "string"
	       then gsub(c.gsub[0]; c.gsub[1]) == c.gsub[2]
	       else gsub(c.gsub[0]; c.gsub[1]) | conforms_to(c.gsub[2])
	       end )
      and when(c.gsub | (type == "array" and length > 3);
               if c.gsub[2] | type == "string"
	       then gsub(c.gsub[0]; c.gsub[1]; c.gsub[2]) == c.gsub[3]
	       else gsub(c.gsub[0]; c.gsub[1]; c.gsub[2]) | conforms_to(c.gsub[3])
	       end )

      and when(c.test | type=="string"; test(c.test))
      and when(c.test | type=="object" and (.not|type=="string");
               test(c.test.not) | not )

      and when(c.regex;
          if c.modifier then test(c.regex; c.modifier)
          else test(c.regex)
          end )
      and when(c.add; add == c.add)
      and when(c.and;  # conjunction
               . as $in | all(c.and[]; . as $c | $in | conforms_to($c))) ;

    # If .subsetof is a string or object, then evaluate it with respect to `.`
    if c.subsetof | isEvaluable
    then ([pipe(c.subsetof)] | unique) as $set
    | conforms_with_constraint(c | (.subsetof = $set) )
    # similarly with .equals_setof
    elif c.equals_setof | isEvaluable
    then ([pipe(c.equals_setof)] | unique) as $set
    | conforms_with_constraint(c | (.equals_setof = $set) )
    elif c.supersetof | isEvaluable
    then ([pipe(c.supersetof)] | unique) as $set
    | conforms_with_constraint(c | (.supersetof = $set) )
    elif c.enumeration | isEvaluable
    then [pipe(c.enumeration)] as $set
    | (c | (.enumeration = $set) ) as $cprime
    | conforms_with_constraint($cprime)

    elif c.oneof | isEvaluable
    then [pipe(c.oneof)] as $set
    | conforms_with_constraint(c | (.oneof = $set) )

    elif c.forall 
    # if the pipeline emits nothing, there is nothing to be checked
    then all( pipe(c.forall)? ; conforms_with_constraint_ignore_pipeline)

    # c.setof is a special case:
    elif c.setof
    then [ pipe(c.setof)? ] | unique | conforms_with_constraint(c | del(.setof) )
    else conforms_with_constraint_ignore_pipeline
    end ;

  # c is assumed to be a CONJUNCTION
  def conforms_with_conjunction(c):
    . as $in
    | all( c[1:][];
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

