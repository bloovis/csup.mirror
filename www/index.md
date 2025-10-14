# Csup User Guide

## Introduction to Csup

Csup is a terminal-based email client for Linux,
written in [Crystal](https://crystal-lang.org/).  It is a partial port of
[Sup-notmuch](https://www.bloovis.com/fossil/home/marka/fossils/sup-notmuch/home), a large
Ruby program, which is in turn
a fork of the original [Sup mail client](https://github.com/sup-heliotrope/sup).
It uses [Notmuch](https://notmuchmail.org/) for mail storage, searching, and tagging.
Much of this guide is based on the [Sup-notmuch Guide](https://www.bloovis.com/supguide/).

There are some important differences between Csup and Sup-notmuch:

* The hook system is very different, and Csup has very few hooks.
* Csup does not have any asynchronous behavior.  For example, it will not load
thread data in the background.
* Crypto (GPG) support is entirely missing.
* Csup has built-in SMTP and SMTP2GO API clients for sending email.
* Csup is a single compiled binary, instead of a large collection of Ruby scripts, so it
uses much less memory and is easier to deploy.

To clone this repository:

```
fossil clone https://www.bloovis.com/fossil/home/marka/fossils/csup
```

## More Information About Csup

* [Getting Started and Basic Configuration](gettingstarted/index.md)
* [Advanced Usage](advancedusage/index.md)
* [Developer Notes](developernotes/index.md)


# Crscope

This repository also includes crscope, a source code browsing tool
for Crystal.  It is partial reimplementation of
[cscope](https://cscope.sourceforge.net/), the venerable source code browing tool for C.

Crscope has only the features I needed for use in
my MicroEMACS variant: the ability to find the definitions of:

* methods
* classes
* modules
* constants

Crscope uses rough heuristics to find these things, and doesn't attempt to do a full parse or to find
all uses of a symbol.

Crscope can also search for files, using a partial match of the term you enter, and
can also search using regular expressions.

Crscope has a completion feature that is missing in cscope.  If you
press ?  while entering a search term, crscope will display a list of
possible names, and will also insert as many characters as necessary
to give the longest possible match.

Aside from completions, the default curses-based user interface is
nearly as identical to cscope as possible, including key bindings and
display.

Crscope also has line-oriented mode that is identical to cscope's, but with
a limited set of search types.  Start the line-oriented mode with the `-l` option.
This mode is used by MicroEMACS, and it could possibly be used other editors
that I'm not aware of that have cscope integration.  This mode implements only the following search types:

* 0 - non-exact name search
* 1 - exact name search (i.e, you must enter a fully qualified name)
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
  files you specify on the command line.
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
