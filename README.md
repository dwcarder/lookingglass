# lookingglass
Looking Glass Router Proxy

## Requirements
- any of the login expect scripts from [rancid](http://www.shrubbery.net/rancid/) or [clogin2](https://github.com/dwcarder/clogin2)
- timeout(1) from [GNU coreutils](https://www.gnu.org/software/coreutils/coreutils.html)

## Installation prerequisites

Ubuntu/Debian pacakges to install:
```
apt-get install libconfig-general-perl libtie-ixhash-perl libjson-xs-perl \
        libregexp-common-perl libregexp-ipv6-perl
```

Centos packages to install:
```
yum install perl-Config-General.noarch perl-Tie-IxHash.noarch perl-JSON-XS.x86_64 \
        perl-Regexp-Common.noarch perl-Regexp-IPv6.noarch
```

## Licensing, etc.
- Apache 2.0 see the included file LICENSE for details
- Portions Copyright (c) the Trustees of Indiana University
- Portions Copyright (c) The University of Wisconsin Board of Regents


## Changelog / lineage (that I know of):
- Inspired by DIGEX, and the Looking Glass by Ed Kern, ejk@digex.net
- [Rewritten by Jesper Skriver, jesper@skriver.dk circa 2000](http://www.nanog.org/mailinglist/mailarchives/old_archive/2000-11/msg00551.html)
- Initially Adapted for use at the University of Wisconsin by Dale W. Carder and Dave Plonka, 2003-12-01
- Modified to include timestamping feature & html cleanup by Dale W. Carder
- lockfile mechanism from checkLastRun() in GRNOC's proxy-output.cgi by Clinton Wolfe, clwolfe@indiana.edu, May 2001 Somewhat based on the original Abilene Router Proxy by Mark Meiss w/ Additional changes by Grover Browning, February 2002.
- Major Feature addition for diff counters by Dave Plonka, 2004-07-18
- Maintenance over 10+ years & a major refactoring by Charles Thomas
- Updated to use clogin instead of Skriver's cisco telnet function, 
- added some code clean up & safety additions to make suitable for public use.
- html, javascript, and documentation updates by Chris Wopat from WiscNet


