PkgDiff 1.8
===========

Package Changes Analyzer (pkgdiff) — a tool for visualizing changes in Linux software packages (RPM, DEB, TAR.GZ, etc).

Contents
--------

1. [ About   ](#about)
2. [ Install ](#install)
3. [ Usage   ](#usage)

About
-----

The tool is intended for Linux maintainers who are interested in ensuring compatibility of old and new versions of packages. The tool can compare directories as well (with the help of the -d option).

Sample report: https://abi-laboratory.pro/tracker/package_diff/libssh/0.6.5/0.7.0/report.html

The tool is developed by Andrey Ponomarenko.

Install
-------

    sudo make install prefix=/usr

###### Requires

* Perl 5
* GNU Diff
* GNU Wdiff
* GNU Awk
* GNU Binutils
* Perl-File-LibMagic

###### Suggests

* ABI Compliance Checker 1.99.1 or newer: https://github.com/lvc/abi-compliance-checker/
* ABI Dumper 0.97 or newer: https://github.com/lvc/abi-dumper

Usage
-----

    pkgdiff PKG1 PKG2 [options]

###### Example

    pkgdiff libssh-0.6.5.tar.xz libssh-0.7.0.tar.xz

###### Compare directories

    pkgdiff -d DIR1/ DIR2/ [options]

###### Useful options

| Option              | Meaning                                      |
|---------------------|----------------------------------------------|
| -hide-unchanged     | Don't show unchanged files in the report     |
| -list-added-removed | Show content of added and removed text files |
| -skip-pattern REGEX | Don't check files matching REGEX             |
| -tmp-dir DIR        | Use custom temp directory                    |
| -d/-directories     | Compare directories instead of packages      |

###### Adv. usage

For advanced usage, see output of -help option.
