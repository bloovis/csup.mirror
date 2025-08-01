# Csup User Guide

## What Is This?

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
* Csup has a built-in SMTP client for sending email.
* Csup is a single compiled binary, instead of a large collection of Ruby scripts, so it
uses much less memory and is easier to deploy.

To clone this repository:

```
fossil clone https://chiselapp.com/user/bloovis/repository/Csup Csup.fossil
```

## What's Here

* [Getting Started and Basic Configuration](gettingstarted/index.md)
* [Advanced Usage](advancedusage/index.md)
* [Developer Notes](developernotes/index.md)
