# Csup - a Crystal port of the Sup mail client that uses notmuch

(*Note*: If you are reading this on Github, you can find the
original Fossil repository [here](https://www.bloovis.com/fossil/home/marka/fossils/csup/home)).

This is a port of the [Sup mail client](https://github.com/sup-heliotrope/sup)
to [Crystal](https://crystal-lang.org/).
I call it by the unoriginal and unpronounceable name Csup.
It uses [notmuch](https://notmuchmail.org/)
as the mail store and search engine.  I based this work on Ju Wu's
notmuch-enabled variant of Sup, which I call Sup-notmuch.
You can find my fork of this Sup-notmuch variant
[here](https://www.bloovis.com/fossil/home/marka/fossils/sup-notmuch/home)
([Github mirror](https://github.com/bloovis/sup-notmuch.mirror)).

As of this writing (2024-03-09), Csup has nearly all of of the
functionality of Sup-notmuch, but is missing:

* GPG crypto support
* most of Sup's hooks
* a few lesser-used commands (such as "kill") that will be added as needed

Most of Csup is a port of code from Sup-notmuch, except for the
message threading code, which I rewrote to use notmuch not just for
determining the structure of the message thread trees, but also for
obtaining the headers and content of the messages.  This avoids most
instances where Csup has to read the raw message files.

I also eliminated the parallel processing that Sup-notmuch used to load thread
data in the background, which required many mutexes and a confusing control flow.

Csup has a built-in SMTP client *and* an SMTP2GO API client for sending email,
so it does not depend on an external program like `sendmail`
for this purpose.

The result is a mail client that looks and behaves almost identically
to Sup but is a bit faster (in most cases) and uses much less memory.  It is also
easier to deploy, being a single compiled binary.

## Documentation

See the [User Guide](www/index.md) for information
on how to set up notmuch and Csup.

## Acknowledgements

Csup is built on the work of other, smarter people, including (but not limited to) the following:

* William Morgan and the Sup developers
* Carl Worth and the notmuch developers
* Jun Wu for the original notmuch-enabled Sup
* arcage for the Crystal email shard
* Samual Black and Joakim Reinert for the Crystal ncurses shard
* The creators of the beautiful Crystal programming language

# Crscope

This repository also includes crscope, a source code browsing tool
for Crystal.  It is partial reimplementation of
[cscope](https://cscope.sourceforge.net/), the venerable source code browing tool for C.
For more information about crscope, go [here](www/crscope.md).
