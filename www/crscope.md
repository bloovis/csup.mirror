# Crscope

Crscope is a source code browsing tool
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

## How crscope is different from cscope

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

Crscope's search types are more limited than cscope's:

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

## Curses-based interface

Aside from completions and search field editing (described below),
the default curses-based user interface is as close to cscope as possible, including key bindings and
display format.

The screen is divided into two sections:

* a large top section that contains the search results.
* a smaller bottom section that contains the search entry fields.

Switch between the two sections using the Tab (`C-i`) key.
In each section, you can move from one line to another using
the Down, Up, `C-n`, and `C-p` keys.

In the search results section, hit the Enter key to run your editor on
the selected file and jump to the selected line number.  You can also
type the letter shown on the left column to run the editor edit on that file and line.

In the search entry fields, you can use Emacs-style editing keys.  Hit
the ? key to show possible matches in the search results, or hit Enter to perform a
more precise search.

Press `C-d` (Control-D) at any point to quit.

## Line-oriented interface

Crscope has a line-oriented mode whose interface is identical to cscope's, but with
a limited set of search types.  Start the line-oriented mode with the `-l` option:

```
crscope -l
```

This mode is used by MicroEMACS, and it could possibly be used other editors
that have cscope integration.  This mode implements only the following search types:

* 0 - inexact name search (partially-qualified or unqualified names)
* 1 - exact name search (fully-qualified names)
* 6 - regular expression search
* 7 - file search

Crscope will repreatedly prompt with ">> ", and read a line from standard input.
The first character of the line is the search type, as described above.  The
rest of the line is the string to search.

In response, Crscope will respond with a line containing the number of
matches found, followed the matches, one on each line.  For example,
here is a session where I asked cscope to do an inexact search for `initialize`:

```
>> 0initialize
cscope: 89 lines
./lib/ncurses/src/ncurses/mouse_event.cr NCurses.initialize 9 def initialize(event : LibNCurses::MEVENT)
./lib/ncurses/src/ncurses/mouse_event.cr NCurses.initialize 15 def initialize(@device_id, @coordinates, @state)
./lib/ncurses/src/ncurses/window.cr NCurses.Window.initialize 12 def initialize(height = nil, width = nil, y = 0, x = 0)
./lib/ncurses/src/ncurses.cr NCurses.Window.initialize 31 def initialize(@window : LibNCurses::Window)
./lib/email/src/email/address.cr EMail.Address.initialize 31 def initialize(mail_address : String, mailbox_name : String? = nil)
./lib/email/src/email/concurrent_sender.cr EMail.ConcurrentSender.initialize 45 def initialize(@config)
./lib/email/src/email/concurrent_sender.cr EMail.ConcurrentSender.initialize 51 def initialize(*args, **named_args)
./lib/email/src/email/header.cr EMail.Header.initialize 70 def initialize(field_name : String)
./lib/email/src/email/header.cr EMail.Header.Date.initialize 183 def initialize
./lib/email/src/email/header.cr EMail.Header.MimeVersion.initialize 218 def initialize(@version : String = "1.0")
./lib/email/src/email/header.cr EMail.Header.ContentType.initialize 232 def initialize(@mime_type : String, @params = Hash(String, String).new)
... [remainder of lines omitted]
```

Note that the first line says "cscope" instead of "crscope".  This is done to ensure
compatiblity with editors (such as MicroEMACS) that expect "cscope" in the response..

Each line contains four fields, separated by a space:

* Filename
* Symbol name
* Line number
* Context (the line where the symbol is defined)

Press `C-d` (Control-D) at the prompt to quit.

## Files

Crscope uses two files:

* `crscope.files`: an optional file that contains a
  list of files to search.  If this file doesn't exist, crscope will parse the
  files you specify on the command line.  Unlike cscope, crscope will
  not automatically search files in the current directory if you don't
  specify any files on the command line or in `crscope.files`.
* `crscope.out`: the symbol table file that crscope creates to save the result of its file parsing.
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

## Running crscope

Crscope takes the following options:

* `-d`: Don't rebuild `crscope.out`.
* `-l`: Run line-oriented interface.
* `-v`: Print extremely verbose debug messages.
* `-t tabsize`: Specify the size of a tab in source files (default 8).
  Crscope uses the tabsize to determine indentation, which is crucial
  to its heuristics for determining class scope.
* `-k`: Ignored for cscope compatibility

If you don't specify `-l`, crscope will start the curses-based interface.

You can specify filenames after any options; crscope will search those files
for symbols.  If you don't specify any filenames, crscope will read `crscope.files`
to get the names of files to read.

Each time you run crscope *without* the `-d` option, it will reparse all specified
files, and reconstruct the symbol file `crscope.out` from scratch.
On the ancient machines of the 80s, this would have been a very expensive operation;
hence, cscope had several ways to optimize this, by only parsing those files
that had changed, and by modifying only the parts of the symbol database for
those changed files.  These optimizations are unnecessary on today's fast machines;
crscope should be fast enough even with its brute force strategy.

## Build

Build crscope using:

    make crscope

Then copy the binary to some place in your PATH.
