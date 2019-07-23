# JESS - JSON Extended Structural Schemas

> The JESS language, the JESS.jq conformance checker, and the JESS script

The "J" in JESS stands for JSON, and the ESS stands for "Extended Structural Schema".
A JESS schema for one or more JSON texts is itself a JSON document or
a collection of such documents.

JESS is so-named because it extends a simple structural schema language
in which every schema mirrors the structure of its conforming documents.

This repository contains:

* a specification of the JESS language for JSON schemas (also available
as the [Wiki Home Page](https://bitbucket.org/pkoppstein/jess/wiki/Home) of 
this repository)
* JESS.jq, a reference implementation of a conformance checker, written in [jq](https://stedolan.github.io/jq/) 
* JESS, a wrapper script for JESS.jq.

## Table of Contents

* [Highlights](#highlights)
* [Installation](#installation)
* [Usage](#usage)
* [API](#api)
** [check](#check)
** [check_schemas](#check_schemas)
** [check(stream)](#check_stream)
** [check_schemas(stream)](#check_schemas(stream))
** [conforms_to(schema)](#conforms_to_schema)
* [Contributing](#contributing)
* [License](#license)

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
hg clone ssh://hg@bitbucket.org/states50/nominate"
# You may wish also to create a symlink to the JESS script, e.g.
ln -s ~/.jq/JESS/bin/JESS ~/bin
~~~

Or use the "Clone" button, or use the "Downloads" link to dowload the .zip file to ~/.jq/ 

Another option would be to download the JESS.jq and JESS files individually, e.g.:

~~~sh
mkdir -p JESS ~/bin
cd JESS
wget -N https://bitbucket.org/pkoppstein/jess/src/default/JESS.jq
wget -N https://bitbucket.org/pkoppstein/jess/src/default/bin/JESS
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
folder, or this repository's [Wiki](https://bitbucket.org/pkoppstein/jess/wiki).

See [jq manual](https://stedolan.github.io/jq/manual/#Modules) for how to use jq modules in general.

### Using JESS.jq at the command-line

####With a single schema:
~~~sh
jq -n --argfile schema PATHNAME 'include "JESS"; check' INPUT.json ...
~~~

#### With single schema and one or more preludes:
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

Using the prelude, schema, and JSON data file in the doc directory:

~~~sh
PREFIX=schema-with-unconstrained-keys.schema
JESS --prelude $PREFIX.prelude.json --schema $PREFIX.schema $PRELUDE.json
~~~

or:
~~~sh
PREFIX=schema-with-unconstrained-keys.schema
jq -n --slurpfile $PREFIX.prelude.json --slurpfile schema $PREFIX.schema 'include "JESS"; check' $PRELUDE.json 
~~~

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

## Contributing

The source code is hosted at <https://bitbucket.org/pkoppstein/jess/>

Bug reports and feature requests [are welcome](https://bitbucket.org/pkoppstein/jess/issues)

## License

Made available under the MIT License by Peter Koppstein.
