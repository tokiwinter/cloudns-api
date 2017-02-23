cloudns-api
===========

This script has been developed to provide a simple-to-use command line interface
to the JSON API provided by ClouDNS (http://cloudns.net).

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
