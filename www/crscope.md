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

Like cscope, crscope can also search for files, using a partial match of the term you enter, and
can also search using regular expressions.

Crscope attempts to define method and class names using a qualified
syntax of the form `Class1.Class2[...].MethodName`, where nested
classes are separated with periods.  This is slightly different from
the scoping syntax used in Crystal, but it allows for a consistent and
simple naming scheme.

## New features

Crscope has several features that are missing in cscope:

* **Completions**:  If you
press ?  while entering a search field, crscope will display a list of
possible names, and will also insert as many characters as necessary
to give the longest possible match.  Completions are *not* allowed
for regular expression searches.

* **Search fields editing**: You can use EMACS-style keys for editing
search fields, such as `C-a` for beginning of line, `C-e` for end of line, etc.
The entry fields are persistent, and won't be erased if you hit Enter to
do a search, which allows you to edit them after a search.

* **Go forward and back in search results**.  In cscope, you could only
go forward in the search results by hitting Space.  In crscope, you can also
go back by hitting Backspace.

## Curses-based interface

Aside from completions and search field editing, the default curses-based user interface is
as close to cscope as possible, including key bindings and
display format.

The screen is divided into two sections: a large top section that contains
the search results, and a smaller bottom section that contains the search
entry fields.  Switch between the two sections using the Tab (`C-i`) key.
In each section, you can move from one line to another using
the Down, Up, `C-n`, and `C-p` keys.

In the search results section, hit the Enter key to run your editor on
the selected file and jump to the selected line number.  You can also
type the letter shown on the left column to edit that file and line.

In the search entry fields, you can use Emacs-style editing keys.  Hit
the ? key to show possible completions.  Hit Enter to perform a search.

There are four search entry fields:

* **Inexact name search**: Use this to find a name without having to specify
  its class or module qualifications.  For example, search for `initialize`
  to find all methods called `initialize`, regardless of enclosing class.
* **Exact name search**: Use this to find a fully-qualified name.  For example,
  search for `Class1.initialize` to find the `initialize` method in the
  class `Class1`.
* **Regexp search**: Use this to perform an egrep (grep -E) search.  This
  is useful for finding all occurrences of a particular method, since
  crscope doesn't do that in its name searches.
* **File search**: Use this to search for all filenames containing the specified string.
  This is handy if you can't remember the exact name or full path for a particular file.

Press `C-d` (Control-D) to quit.

## Line-oriented interface

Crscope has a line-oriented mode whose interface is identical to cscope's, but with
a limited set of search types.  Start the line-oriented mode with the `-l` option.
This mode is used by MicroEMACS, and it could possibly be used other editors
that have cscope integration.  This mode implements only the following search types:

* 0 - non-exact name search (partially-qualified or unqualified names)
* 1 - exact name search (fully-qualified names)
* 6 - regular expression search
* 7 - file search

## Files

Crscope uses two files:

* `crscope.files`: an optional file that contains a
  list of files to search.  If this file doesn't exist, crscope will parse the
  files you specify on the command line.  Unlike cscope, crscope will
  not automatically search files in the current directory if you don't
  specify any files on the command line or in `crscope.files`.
* `crscope.out`: the file that crscope creates to save the result of its file parsing.
  It is a plain text file that you can edit if
  necessary.  Use the `-d` option to prevent crscope from rebuilding
  this file at startup.

## Environment Variables

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

## Build

Build crscope using:

    make crscope

Then copy the binary to some place in your PATH.
