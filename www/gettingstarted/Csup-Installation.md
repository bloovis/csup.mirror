# Csup installation

Note that I have only tested building Csup on Ubuntu 22.04, Linux Mint 21,
Linux Mint 22, and Fedora 42.
It may work on other distros, but I have not tried them.

Install the Crystal language according to [these instructions](https://crystal-lang.org/install/).

Make sure you have the libncursesw, libcrypto, and libssl development
libraries installed.  On Debian/Ubuntu/Mint do this:

    sudo apt install libncursesw5-dev libssl-dev

On Fedora, do this:

    sudo dnf install ncurses-devel openssl-devel

Fetch the source code repository and check it out in one step using:

    fossil clone https://www.bloovis.com/fossil/home/marka/fossils/csup

Change to the `csup` directory and build it:

    cd csup
    shards install
    make

Copy the binary (`csup`) to some place in your PATH.
