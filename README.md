cloudns-api
===========

This script has been developed to provide a simple-to-use command line interface
to the JSON API provided by ClouDNS (http://cloudns.net).

Installation
------------

    $ git clone https://github.com/tokiwinter/cloudns-api.git
    $ sudo cp cloudns-api/bin/cloudns_api.sh /usr/local/bin
    $ sudo chmod +x /usr/local/bin/cloudns_api.sh

You should ensure that the paths to the various executables defined by the 
script are available. You should also install `jq` if you don't have it
already.

Steps for OpenSUSE Leap 42, for example:

Install `jq` if you don't already have it:

    $ which jq 2>/dev/null || sudo zypper --non-interactive install jq

Ensure all required binary paths are correct:

    $ grep -E '^[A-Z]+="[^"]+"' /usr/local/bin/cloudns_api.sh |\
    >   grep -Fv builtin |\
    >   sed 's/^.*="\([^"][^"]*\)"$/\1/' |\
    >   xargs ls -l

If they are not, update them:

    $ sudo vi /usr/local/bin/cloudns_api.sh

Usage
-----

    Usage: cloudns_api.sh [-dfhjs] command [options]
           -d   run in debug mode (lots of verbose messages)
           -f   force delrecord operations without confirmation
           -h   display this help message
           -j   return listrecords output in JSON format
           -s   skip testing authentication prior to attempting API operations
    
       Commands:
           listzones  - list zones under management
           addzone    - add a new zone
           delzone    - delete an existing zone
           checkzone  - check that a zone is managed
           dumpzone   - dump a zone in BIND zonefile format
           zonestatus - check whether a zone is updated on all NS
           nsstatus   - view a breakdown of zone update status by NS
           addrecord  - add a new DNS record to a zone
           delrecord  - delete a DNS record from a zone
           modify     - modify an existing DNS record
           getsoa     - get SOA record parameters for a zone
           setsoa     - set SOA record parameters for a zone
           helper     - call a helper function directly
    
       Environment:
         Ensure that the following two environment variables are exported:
           CLOUDNS_API_ID   - your ClouDNS API ID (auth-id)
           CLOUDNS_PASSWORD - your ClouDNS API password (auth-password)

Environment
-----------

Limitations
-----------

Current limitations. I may further develop the functionality offered by the script if
I receive enough interest.

- does not support sub-auth-id
- only supports master zones
- only supports forward zones
- only supports creation/modification of SUPPORTED_RECORD_TYPES
  SUPPORTED_RECORD_TYPES=( "A" "CNAME" "MX" "NS" "SPF" "SRV" "TXT" )
