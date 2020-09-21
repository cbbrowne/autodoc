* PostgreSQL Autodoc

This is a utility which will run through PostgreSQL system tables and
returns HTML, DOT, and several styles of XML which describe the
database.

As a result, documentation about a project can be generated quickly
and be automatically updatable, yet have a quite professional look if
you do some DSSSL/CSS work.

** Requirements

This program requires the following perl modules:
- DBI
- HTML::Template
- Term::ReadKey
- DBD::Pg

** Installation

*** Ubuntu

(Debian should be similar/identical)

**** from the universe repository

~$ sudo apt install postgresql-autodoc~

**** from github

~$ sudo apt install libdbi-perl libhtml-template-perl libterm-readkey-perl libdbd-pg-perl~

~$ git clone https://github.com/cbbrowne/autodoc.git~

~$ cd autodoc~

~$ sudo make install~

*** Docker

Install [Docker](https://www.docker.com/)

Create a Docker Image:

~$ docker build . -t autodoc~

Running Docker:

Create an env file by copying the example file and filling in details:

~$ cp env-example env~

Run a Docker container (with default command in Dockerfile):

~$ docker run --mount src=`pwd`,target=/app,type=bind --network=host --env-file ./env -v $pwd:/app autodoc~

Note: --network=host is for accessing a database on localhost

Run a custom container (see Usage below; if you want the files to appear in current directory, use the `--mount` arg above):

~$ docker run autodoc postgresql_autodoc [options]~

** Usage

  ~postgresql_autodoc [options]~

** Options

 - ~−d~ :: <dbname> - Specify database name to connect to (default: current user)
 - ~−f~ :: <file> Specify output file prefix (default: current user)
 - ~−h~ :: <host> Specify database server host (default: localhost)
 - ~−p~ :: <port> Specify database server port (default: 5432)
 - ~−u~ :: <username> Specify database username (default: current user)
 - ~−−password=<pw>~ :: Specify database password (default: blank)
 - ~−w~ :: Use ~/.pgpass for authentication (overrides all other password options)
 - ~−l~ :: <path> Path to the templates (default: @@TEMPLATE-DIR@@)
 - ~−t~ :: <output> Type of output wanted (default: All in template library)
  + _html_ :: The HTML is human readable (via web browser), representing
         the entire schema within a single HTML document, and includes
         referenceable labels for each object.
  + _dia_ :: This remaps the schema into XML using the XML schema of
             [[https://git.gnome.org/browse/dia/][Dia]], an interactive diagramming tool.  It does not do any
             automated layout, so making the diagram usable would
             require manual work, so this is often not terribly useful.
  + _xml_ :: The second type of XML is similar to HTML, but is in DocBook
         4 format. It enables you to mix schema documentation with
         other DocBook documentation via the XREFs, generating PDFs,
         HTML, RTF, or other formatted documents.  Object references
         can be made between these tools and JavaDoc with use of 
         appropriate XREFs (see ~xreflabel~ elements in the XML).
  + _neato_ :: This generates the schema in the form accepted by GraphViz
            ~neato~, which draws the schema as an undirected graph
  + _zigzag.dia_ :: This generates a diagram for Dia in another form
 - ~−s~ :: <schema> Specify a specific schema to match. Technically this is a regular expression but anything other than a specific name may have unusual results.
 - ~−m~ :: <regexp> Show only tables/objects with names matching the specified regular expression.
 - ~−−table=<args>~ :: Tables to export. Multiple tables may be provided using a comma-separated list, i.e. table,table2,table3.
 - ~−−statistics~ :: In 7.4 and later, with the contrib module pgstattuple installed we can gather statistics on the tables in the database (average size, free space, disk space used, dead tuple counts, etc.) This is disk intensive on large databases as all pages must be visited.
 - ~--comment-filter=<program>~ :: Processes comments with a program. This is useful when comments are written using some markup languague (wiki/markdown), it allows conversion of structured text to desired output format. For each comment is executed command <program> <output> <tmp_file>, where <output> is the desired output format as specified by -t, <tmp_file> is path to file with original comment text. Processor should read this file, do processing and write result to standard output.

** AUTHOR

Originally, this code base was derived from the [[http://pgfoundry.org/scm/?group_id=1000009][CVS repository on
pgFoundry]], shifted to GitHub due to the popularity of maintenance via
Git.

The presence of further contributions to the codebase seems to confirm
that this was a decent idea.

Rod Taylor <autodoc@rbt.ca>

