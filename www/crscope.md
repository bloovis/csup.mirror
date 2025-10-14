# Crscope

Crscope a source code browsing tool
for Crystal and Ruby.  It is a partial reimplementation of
[cscope](https://cscope.sourceforge.net/), the venerable source code browing tool for C.

Crscope has only the features I needed for use in
my MicroEMACS variant: the ability to find the definitions of:

* methods (`def`)
* classes (`class`)
* modules (`module`)
* constants (UPPER_CASE_NAMES = ...)
* libraries (`lib`)

Crscope uses rough heuristics to find these things, and doesn't attempt to do a full parse or to find
all uses of a symbol.  These heuristics involve the use of regular expressions,
and assumptions about the indentation of blocks.  In particular, the indentation of
`end` must match that of the opening `class`, `def`, etc., except
in the case of one-liner class and method definitions, with `end` on
the same line.

Crscope can also search for files, using a partial match of the term you enter, and
can also search using regular expressions.

Crscope has two features that are missing in cscope:

* **Completions**:  If you
press ?  while entering a search field, crscope will display a list of
possible names, and will also insert as many characters as necessary
to give the longest possible match.  Completions are *not* allowed
for regular expression searches.

* **Search fields editing**: You can use EMACS-style keys for editing
search fields, such as `C-a` for beginning of line, `C-e` for end of line, etc.
The entry fields are persistent, and won't be erased if you hit Enter to
do a search, which allows you to edit them after a search.

Aside from completions and search field editing, the default curses-based user interface is
as close to cscope as possible, including key bindings and
display format.

Crscope also has a line-oriented mode that is identical to cscope's, but with
a limited set of search types.  Start the line-oriented mode with the `-l` option.
This mode is used by MicroEMACS, and it could possibly be used other editors
that I'm not aware of that have cscope integration.  This mode implements only the following search types:

* 0 - non-exact name search (partially-qualified or unqualified names)
* 1 - exact name search (fully-qualified names)
* 6 - regular expression search
* 7 - file search

Crscope attempts to define method and class names using a qualified
syntax of the form `Class1.Class2[...].MethodName`, where nested
classes are separated with periods.  This is slightly different from
the scoping syntax used in Crystal, but it allows for a consistent and
simple naming scheme.

Crscope uses two files:

* The optional file `crscope.files`, which contains a
  list of files to search.  If this file doesn't exist, crscope will parse the
  files you specify on the command line.  Unlike cscope, crscope will
  not automatically search files in the current directory if you don't
  specify any files on the command line or in `crscope.files`.
* Crscope writes the result of its file parsing
  to `crscope.out`, which is a plain text file that can be edited if
  necessary.  Use the `-d` option to prevent crscope from rebuilding
  this file at startup.

Crscope uses the following environment variables:

* `EDITOR` contains the name of the editor.
* `VISUAL` contains the name of the editor if `EDITOR` is not defined.
* `CRSCOPE_EDITOR` contains the format string that crscope uses to
  construct the editor command line.  In this string, use the following
  format specifiers:
  - `%e` is replaced by the editor name
  - `%l` is replaced by the line number
  - `%f` is replaced by the filename 
* If `CRSCOPE_EDITOR` is not defined, crscope uses the format string
  "`%e +%l %f`".

Build crscope using:

    make crscope
