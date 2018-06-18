cloudns-api
===========

[![License: GPL](https://img.shields.io/badge/License-GPL-blue.svg)](https://www.gnu.org/licenses/gpl.html)

This script has been developed to provide a simple-to-use command line interface
to the JSON API provided by ClouDNS (http://cloudns.net).

Installation
------------

    $ git clone https://github.com/tokiwinter/cloudns-api.git
    $ sudo cp cloudns-api/bin/cloudns_api.sh /usr/local/bin
    $ sudo chmod +x /usr/local/bin/cloudns_api.sh

You should also install `jq` if you don't have it already.

Usage
-----

    Usage: cloudns_api.sh [-dfhjs] command [options]
           -d   run in debug mode (lots of verbose messages)
           -f   force delrecord operations without confirmation
           -h   display this help message
           -j   return listrecords output in JSON format
           -s   skip testing authentication prior to attempting API operations
    
       Commands:
           listzones    - list zones under management
           addzone      - add a new zone
           delzone      - delete an existing zone
           checkzone    - check that a zone is managed
           dumpzone     - dump a zone in BIND zonefile format
           dumpallzones - dump all zones in BIND zonefile format
           zonestatus   - check whether a zone is updated on all NS
           nsstatus     - view a breakdown of zone update status by NS
           addmaster    - add new master server in domain zone
           delmaster    - delete master server by ID in domain zone
           listmaster   - list master servers in the domain zone
           addrecord    - add a new DNS record to a zone
           delrecord    - delete a DNS record from a zone
           listrecords  - list zones under management
           modify       - modify an existing DNS record
           getsoa       - get SOA record parameters for a zone
           setsoa       - set SOA record parameters for a zone
           helper       - call a helper function directly
           test         - perform an authentication test
    
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
The `-s` option will cause `cloudns_api.sh` to skip testing authentication prior to each API call.

### test ###

You can execute an authentication test, to check that your environment is correctly configured, as
follows:

    $ cloudns_api.sh test
    Thu Feb 23 20:33:11 AEDT 2017: Login test successful

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

### dumpallzones ###

#### Description ####

Similar to `dumpzone`, except it dumps **all** zones into a particular directory.
This is useful for backing up your entire account. The output directory will be
created if it does not already exist.

#### Usage ####

   $ cloudns_api.sh dumpzone <output directory>

#### Example ####

   $ cloudns_api.sh dumpzone /var/backup/zones/


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

### listmaster ###

#### Description ####

List master ips on slave zones. IDs are not shown by default, specify `showid=true` to
display them.

#### Usage #####

    $ cloudns_api.sh listmaster <zonename> [showid=<true|false>]

#### Example ####

    $ cloudns_api.sh listmaster example.com showid=true
    1.2.3.4 ; id=567890
    5.6.7.8 ; id=123456

### addmaster ###

#### Description ####

Add master ip to slave zones.

#### Usage #####

    $ cloudns_api.sh addmaster <zonename> <masterip>

#### Example ####

    $ cloudns_api.sh addmaster example.com 1.2.3.4
    Wed Nov  8 16:50:40 CET 2017: Master IP was added successfully to zone [example.com]

### delmaster ###

#### Description ####

Remove master ip from slave zones. You will be asked to confirm the operation. You
can avoid this, and force the removal, with `-f`. Obtain the record id using the `listmaster`
command.

#### Usage #####

    $ cloudns_api.sh delmaster <zonename> <masterid>

#### Example ####

    $ cloudns_api.sh delmaster example.com id=567890
    Are you sure you want to delete master with id [567890]? [y|n]: y
    Wed Nov  8 16:51:18 CET 2017: Master successfully deleted

### addrecord ###

#### Description ####

Add a new resource record to a zone.

#### Usage ####

Options required depend upon the record type being added. The key=value pairs can appear
in any order.

For A, AAAA, NS, CNAME, SPF, TXT:

    $ cloudns_api.sh addrecord <zonename> type=<type> host=<host> record=<record> ttl=<ttl>

SPF and TXT records are a special case. As their record data could include whitespace and
other characters, you should create a single-line file containing the record data. See Examples
below.

For MX:

    $ cloudns_api.sh addrecord <zonename> type=MX host=<host> record=<record> ttl=<ttl> priority=<priority>

For SRV:

    $ cloudns_api.sh addrecord <zonename> type=SRV host=<host> record=<record> ttl=<ttl> priority=<priority> weight=<weight> port=<port>

If you want an apex record, specify `host=@`.

#### Example ####

For non-SPF/TXT records, here a CNAME (some limited validation of values occurs in the script,
and then the API does its own validation):

    $ cloudns_api.sh addrecord foo.com type=CNAME host=testing record=cnametarget.foo.com. ttl=60
    Thu Feb 23 20:01:20 AEDT 2017: Record successfully added with id [24135067]

For SPF/TXT records, add your record data to a file, on a single line, without enclosing quotes.
Reference that in the `record=<filename>` key=value pair:

    $ echo "This isn't text. Oh, it is actually" > /var/tmp/txt.txt
    $ cloudns_api.sh addrecord foo.com type=TXT host=testtext record=/var/tmp/txt.txt ttl=60
    Thu Feb 23 20:02:51 AEDT 2017: Record successfully added with id [24135071]
    $ rm -f /var/tmp/txt.txt

### delrecord ###

#### Description ####

Delete a resource record from a zone by id. You will be asked to confirm the operation. You
can avoid this, and force the removal, with `-f`. Obtain the record id using the `listrecords`
command.

#### Usage ####

    $ cloudns_api.sh [-f] delrecord <zonename> id=<id>

#### Example ####

    $ cloudns_api.sh delrecord foo.com id=24135071
    Are you sure you want to delete record with id [24135071]? [y|n]: y
    Thu Feb 23 20:05:46 AEDT 2017: Record successfully deleted

### modify ###

#### Description ####

Modify an existing resource record. You must specify at least one attribute to modify. You
must know the record id (use the `listrecords` command to obtain this). The key=value pairs
are the same as with `addrecord`. You cannot modify a record's `type`, so don't try that.
If you want to change `record` for an SPF or TXT record, the same loading-from-file
mechanism as with `addrecord` applies to `modify` too.

You can modify as many attributes as you want in a single invocation. If you specify the
same attribute twice, the latest specification will be used. The order of attribute specification
does not matter.

#### Usage ####

    $ cloudns_api.sh modify <zonename> id=<id> key=<value> [key=<value> ...]

#### Example ####

    $ cloudns_api.sh modify foo.com id=24135067 ttl=3600 record=newcnametarget.foo.com.
    Thu Feb 23 20:11:24 AEDT 2017: Record successfully modified

### listrecords ###

#### Description ####

List records for a specified zone in either BIND (RFC 1035) format or JSON. If you want
apex records, specify `host=@`. IDs are not shown by default, specify `showid=true` to
display them, as a BIND-style comment.

#### Usage ####

    $ cloudns_api.sh [-j] listrecords <zonename> [host=<host>] [type=<type>] [showid=<true|false>]

#### Example ####

    $ cloudns_api.sh listrecords foo.com host=@ type=NS showid=true
    @  3600  IN  NS  ns1.cloudns.net.  ; id=24134077
    @  3600  IN  NS  ns2.cloudns.net.  ; id=24134078
    ...

### getsoa ###

#### Description ####

Display SOA record details for a specified zone.

#### Usage ####

    $ cloudns_api.sh getsoa <zonename>

#### Example ####

    $ cloudns_api.sh getsoa foo.com
    serialNumber:2017022315
    primaryNS:ns1.cloudns.net
    adminMail:support@cloudns.net
    refresh:7200
    retry:1800
    expire:1209600
    defaultTTL:3600

### setsoa ###

#### Description ####

Modify the SOA record for a specified zone. You can modify one or more parameters in the same
invocation. Order does not matter.

#### Usage ####

    $ cloudns_api.sh setsoa <zonename> key=value [key=<value> ...]

Valid keys are: 

    primary-ns admin-mail refresh retry expire default-ttl

#### Example ####

    $ cloudns_api.sh setsoa foo.com admin-mail=hostmaster@foo.com default-ttl=3600
    Thu Feb 23 20:20:49 AEDT 2017: default-ttl value same as existing
    Thu Feb 23 20:20:49 AEDT 2017: SOA for zone [foo.com] modified

### helper ###

#### Description ####

Execute a helper function directly.

#### Usage ####

     $ cloudns_api.sh helper <function>

#### Example ####

    $ cloudns_api.sh helper get_available_ttls
    60 300 900 1800 3600 21600 43200 86400 172800 259200 604800 1209600 2592000
    $ cloudns_api.sh helper get_record_types
    A AAAA MX CNAME TXT SPF NS SRV WR ALIAS RP SSHFP NAPTR

Limitations
-----------

Current limitations. I may further develop the functionality offered by the script if
I receive enough interest.

- does not support sub-auth-id
- only supports forward zones
- only supports creation/modification of SUPPORTED_RECORD_TYPES  

`SUPPORTED_RECORD_TYPES=( "A" "AAAA" "CNAME" "MX" "NS" "SPF" "SRV" "TXT" )`
