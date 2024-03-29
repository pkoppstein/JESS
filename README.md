# JESS - JSON Extended Structural Schemas

> The JESS language, the JESS.jq conformance checker, and the JESS script

The "J" in JESS stands for JSON, and the ESS stands for "Extended Structural Schema".
JESS is so-named because it extends a simple structural schema language
in which every schema mirrors the structure of its conforming documents.

A JESS schema for one or more JSON texts is itself a JSON document or
a collection of such documents.

This repository contains:

* a specification of the JESS language for JSON schemas (also available as the [Wiki Home Page](https://github.com/pkoppstein/jess/wiki/Home) of this repository)
* JESS.jq, a reference implementation of a conformance checker, written in [jq](https://stedolan.github.io/jq/) 
* JESS, a wrapper script for JESS.jq
* supporting documentation and test cases.

## Table of Contents

  - [Highlights](#highlights)
  - [Installation](#installation)
  - [Usage](#usage)
    - [Using JESS.jq at the command-line](#using-jessjq-at-the-command-line)
      - [With a single schema and one or more preludes:](#with-a-single-schema-and-one-or-more-preludes)
      - [With multiple schemas and one or more preludes:](#with-multiple-schemas-and-one-or-more-preludes)
    - [Examples](#examples)
  - [jq functions](#jq-functions)
    - [check](#check)
    - [check(stream)](#checkstream)
    - [check_schemas](#check_schemas)
    - [check_schemas(stream)](#check_schemasstream)
    - [conforms_to(schema)](#conforms_toschema)
  - [Experimental Aspects of the JESS Language](#experimental-aspects-of-the-jess-language)
  - [Contributing](#contributing)
  - [License](#license)

## Highlights

JESS extends the simplest possible all-JSON structural schema language in which the JSON schema for a set of documents is a single JSON document such that:

* JSON objects are specified by objects, or generically by "object"
* JSON arrays are specified by arrays, or generically by "array"
* the type of each scalar other than a string is itself
* "string" is the string type
* "boolean" is the boolean type
* "scalar" includes all scalars
* "JSON" is the type of all JSON documents.

The main extensions follow naturally or are based closely on the purely functional components
of the [jq](https://stedolan.github.io/jq/) language.

These extensions include:

* compound array types, e.g. [0,1] is the schema for arrays of 0-1 values;
* union types, e.g. ["+", 0,1] is the schema for 0 or 1;
* subtypes of "string" defined by regular expressions;
* support for complex constraints, including referential integrity constraints, and recursive constraints;
* user-defined named types, e.g. for different date formats.

Modularity is supported by allowing both the prelude (in which
user-defined named types are defined) and the schema proper to be
written as multiple JSON documents in different files.

## Installation

Running the conformance checker requires [jq](https://stedolan.github.io/jq/) version 1.5 or newer.

It is recommended that the JESS directory be placed in your ~/.jq/ directory so that jq will automatically be able to find it.

One way to do so is to check out this repository to directory `~/.jq/`:

~~~sh
mkdir ~/.jq
cd ~/.jq
hg clone https://github.com/pkoppstein/JESS.git
# You may wish also to create a symlink to the JESS script, e.g. by executing:
ln -s ~/.jq/JESS/bin/JESS ~/bin
~~~

Or use the "Clone" button, or use the "Downloads" link to dowload the .zip file to ~/.jq/ 

Another option would be to download the JESS.jq and JESS files individually, e.g.:

~~~sh
mkdir -p JESS ~/bin
cd JESS
wget -N https://raw.githubusercontent.com/pkoppstein/JESS/master/JESS.jq
wget -N https://raw.githubusercontent.com/pkoppstein/JESS/master/bin/JESS
chmod +x JESS
ln -s $(pwd)/JESS ~/bin
~~~

If the JESS.jq module is not in a standard location known to jq, it
may be necessary to specify the location of the JESS.jq file, e.g. on
the jq or JESS command-line.

## Usage

For help regarding the wrapper script, run `JESS -h`.

An overview of the main functions provided by JESS.jq for conformance
checking is given below. For details, see the documentation in the doc
folder, or this repository's [Wiki](https://github.com/pkoppstein/jess/wiki).

See [jq manual](https://stedolan.github.io/jq/manual/#Modules) for how to use jq modules in general.

### Using JESS.jq at the command-line

#### With a single schema:
~~~sh
jq -n --argfile schema PATHNAME 'include "JESS"; check' INPUT.json ...
~~~

#### With a single schema in nullable mode:
~~~sh
jq -n --arg nullable true --argfile schema PATHNAME 'include "JESS"; check' INPUT.json ...
~~~

#### With a single schema and one or more preludes:
~~~sh
# jq -n --argfile schema PATHNAME --slurpfile PATHNAME 'include "JESS"; check' INPUT.json ...
~~~

#### With multiple schemas and one or more preludes:
~~~sh
 jq -n --argfile schema PATHNAME --slurpfile PATHNAME 'include "JESS"; check_schemas'
~~~

You may also wish to put your jq commands in a file, say check.jq that begins with an include or import statement. Here is an example of such a file:

~~~sh
include "JESS" {search: "path/to/module"};

"Abc" | conforms_to("/a/i")
~~~

Invocation would then be along the lines of:
~~~sh
jq -n -f check.jq
~~~
or
~~~sh
jq -f check.jq INPUT.json ...
~~~

### Examples

The "doc" directory includes a simple example combining a preface, a
schema, and a conforming JSON document. Assuming JESS.jq is in an
appropriate location and that a bash or similar shell is available,
then one way to check conformance would be to run the JESS script
along the following lines:

~~~sh
 cd JESS
 PREFIX=doc/schema-with-unconstrained-keys
 ./JESS --prelude $PREFIX.prelude.json --schema $PREFIX.schema $PREFIX.json
~~~

Alternatively, one could use jq directly, along these lines:

~~~sh
PREFIX=doc/schema-with-unconstrained-keys
jq -n --slurpfile prelude $PREFIX.prelude.json --slurpfile schema $PREFIX.schema 'include "JESS"; check' $PREFIX.json 
~~~

 
## jq functions

The "check" family of jq functions provide details about non-conforming entities, such as the corresponding file name.

"conforms_to(schema)" is the jq function intended for programmers to use. 

### check
~~~json
check # defined as check(inputs)
~~~
Checks the standard input stream against a single schema entity in $schema.

### check(stream)
~~~json
check(stream)
~~~
Checks the given stream against a single schema entity in $schema.

### check_schemas
~~~json
check_schemas # defined as check_schemas(inputs)
~~~
Checks the standard input stream against one or more schema entities in $schema (an array).

### check_schemas(stream)
~~~json
check_schemas(stream)
~~~
Checks the given stream against one or more schema entities in $schema (an array).

### conforms_to(schema)
~~~json
conforms_to(schema)
~~~

For each input, `conforms_to(schema)` simply emits true or false depending on whether that input
conforms to the given schema entity.

## Experimental Aspects of the JESS Language

The definitions of the following named types are experimental and subject to change:

* base64
* ISO8601Date

## Contributing

The source code is hosted at <https://github.com/pkoppstein/jess/>

Bug reports and feature requests [are welcome](https://github.com/pkoppstein/JESS/issues)

## License

Made available under the MIT License by Peter Koppstein.
