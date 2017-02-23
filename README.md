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

You should ensure that you export the following environment variables correctly. Their
existence is tested by the script.

    $ export CLOUDNS_API_ID=<your_auth-id>
    $ export CLOUDNS_PASSWORD=<your_auth-password>

The script does not currently support sub-auth-id, etc. See Limitations at the end of
this document. This does allow us to operate globally on your account. Ensure you
run this script from a trusted host, `unset` your envionment variables when done, 
remove the assignments from your history (`history -d <offset>`), and have appropriate
IP restrictions in place on your auth-id (configurable via the ClouDNS web UI).

Using the script
----------------

### General options ###

The `-d` option will cause `cloudns_api.sh` to act verbosely and print debug messages as it goes.

### listzones ###

#### Description ####

List the zones under your account, and their type.

#### Usage #####

    $ cloudns_api.sh listzones

#### Example ####

    $ cloudns_api.sh listzones
    testzone1.com:master
    testzone2.com:master

### addzone ###

#### Description ####

Add a new zone to your account.

#### Usage ####

    $ cloudns_api.sh addzone <zonename>

#### Example ####

    $ cloudns_api.sh addzone foo.com
    Thu Feb 23 19:43:12 AEDT 2017: New zone [foo.com] added

### delzone ###

Delete a zone from your account. `delzone` treats you like an idiot, as deleting an
entire zone is a big deal. You cannot force this operation (with `-f`). You will be
asked to enter a string, exactly, as well as wait for a 5 second timeout (to give
you time to hit CTRL-C) prior to the zone being removed forever.

#### Usage ####

    $ cloudns_api.sh delzone <zonename>

#### Example ####

    $ cloudns_api.sh delzone foo.com
    Are you sure you want to delete zone [foo.com]?
    You must type I-AM-SURE, exactly: I-AM-SURE
    Okay. Waiting 5s prior to removal. CTRL-C now if unsure!
    Thu Feb 23 19:43:39 AEDT 2017: Zone [foo.com] deleted

### checkzone ###

#### Description ####

Check whether domains are managed under this account.

#### Usage ####

    $ cloudns_api.sh checkzone <zone1> [<zone2> ... <zonen>]

#### Example ####

    $ cloudns_api.sh checkzone foo.com bar.com
    foo.com:present
    bar.com:absent

### dumpzone ###

#### Description ####

Dump an entire zone in BIND (RFC 1035) format, ideal for redirecting to a file.

#### Usage ####

    $ cloudns_api.sh dumpzone <zonename>

#### Example ####

    $ cloudns_api.sh dumpzone foo.com
    $TTL 3600
    @           IN  SOA  ns1.cloudns.net. support.cloudns.net. 2017022309 7200 1800 1209600 3600
    @     3600  IN  NS   ns1.cloudns.net.
    ....

### zonestatus ###

#### Description ####

Check whether a zone is updated on all nameservers.

#### Usage ####

    $ cloudns_api.sh zonestatus <zone1> [<zone2> ... <zonen>]

#### Example ####

    $ cloudns_api.sh zonestatus foo.com bar.com tokitest.com
    foo.com:up-to-date
    bar.com:not-valid
    tokitest.com:out-of-date

### nsstatus ###

#### Description ####

View the zone update status per nameserver.

#### Usage ####

    $ cloudns_api.sh nsstatus <zonename>

#### Example ####

    $ cloudns_api.sh nsstatus tokitest.com
    ns1.cloudns.net:true
    ns2.cloudns.net:false
    ns3.cloudns.net:true
    ns4.cloudns.net:true
    pns1.cloudns.net:true
    pns2.cloudns.net:true
    pns3.cloudns.net:true
    pns4.cloudns.net:true

### addrecord ###

#### Description ####

#### Usage ####

#### Example ####

### delrecord ###

#### Description ####

#### Usage ####

#### Example ####

### modify ###

#### Description ####

#### Usage ####

#### Example ####

### getsoa ###

#### Description ####

#### Usage ####

#### Example ####

### setsoa ###

#### Description ####

#### Usage ####

#### Example ####

### helper ###

#### Description ####

#### Usage ####

#### Example ####

Limitations
-----------

Current limitations. I may further develop the functionality offered by the script if
I receive enough interest.

- does not support sub-auth-id
- only supports master zones
- only supports forward zones
- only supports creation/modification of SUPPORTED_RECORD_TYPES  

`SUPPORTED_RECORD_TYPES=( "A" "CNAME" "MX" "NS" "SPF" "SRV" "TXT" )`
