#!/bin/bash

AWK="/usr/bin/awk"
BASENAME="/usr/bin/basename"
CURL="/usr/bin/curl"
CUT="/usr/bin/cut"
DATE="/usr/bin/date"
ECHO="builtin echo"
EVAL="builtin eval"
GETOPTS="builtin getopts"
GREP="/usr/bin/grep"
JQ="/usr/bin/jq"
SED="/usr/bin/sed"
SLEEP="/usr/bin/sleep"
TEST="/usr/bin/test"

API_URL="https://api.cloudns.net/dns"
DEBUG=0
REMOVAL_WAIT=5
SKIP_TESTS=0
THISPROG=$( ${BASENAME} $0 )

ROWS_PER_PAGE=100

# current limitations
# - does not support sub-auth-id
# - only supports master zones
# - only supports forward zones

function print_error {
  ${ECHO} "$( ${DATE} ): Error: $@" >&2
}

function print_usage {
  {
    ${ECHO} "Usage: ${THISPROG} [-ds] command [options]"
  } >&2
}

function print_timestamp {
  ${ECHO} "$( ${DATE} ): $@"
}

function print_debug {
  (( DEBUG )) && ${ECHO} "$( ${DATE} ): DEBUG: $@"
}

function process_arguments {
  local COMMAND="$1"
  if [ -z "${COMMAND}" ]; then
    print_usage && exit 1
  fi
  case ${COMMAND} in
    "help"         ) print_usage && exit 0    ;;
    "test"         ) test_login               ;;
    "listzones"    ) list_zones               ;;
    "addzone"      ) shift
                     add_zone "$@"            ;;
    "delzone"      ) shift
                     delete_zone "$@"         ;;
    "checkzone"    ) shift
                     check_zone "$@"          ;;
    "dumpzone"     ) shift
                     dump_zone "$@"           ;;
    "zonestatus"   ) shift
                     zone_status "$@"         ;;
    "nsstatus"     ) shift
                     ns_status "$@"           ;;
    "addrecord"    ) shift
                     add_record "$@"          ;; # notimplemented 
    "delrecord"    ) shift
                     delete_record "$@"       ;; # notimplemented
    "modify"       ) shift
                     modify_record "$@"       ;; # notimplemented
    "listrecords"  ) shift
                     list_records "$@"        ;;
    "getsoa"       ) shift
                     get_soa "$@"             ;;
    "setsoa"       ) shift
                     set_soa "$@"             ;; # notimplemented
    "helper"       ) shift
                     call_helper "$@"         ;;
    *              ) print_usage && exit 1    ;;
  esac
}

function check_environment_variables {
  local ERROR_COUNT=0
  local REQUIRED_VARIABLES=( CLOUDNS_API_ID CLOUDNS_PASSWORD )
  for REQUIRED_VARIABLE in ${REQUIRED_VARIABLES[@]}; do
    if $( ${EVAL} ${TEST} -z \${${REQUIRED_VARIABLE}} ); then
      print_error "Environment variable \${${REQUIRED_VARIABLE}} unset"
      (( ERROR_COUNT = ERROR_COUNT + 1 ))
    fi
  done
  if [ "${ERROR_COUNT}" -gt "0" ]; then
    exit 1
  fi
}

function set_auth_post_data {
  AUTH_POST_DATA="-d auth-id=${CLOUDNS_API_ID} -d auth-password=${CLOUDNS_PASSWORD}"
}

function test_api_url {
  local HTTP_CODE=$( ${CURL} -4qs -o /dev/null -w '%{http_code}' ${API_URL}/login.json )
  if [ "${HTTP_CODE}" != "200" ]; then
    print_error "Unable to reach ClouDNS API" && exit 1
  else
    print_debug "API availability check successful"
  fi
}

function do_login {
  local STATUS=$( ${CURL} -4qs -X POST ${AUTH_POST_DATA} "${API_URL}/login.json" | ${JQ} -r '.status' )
  case ${STATUS} in
    "Success" ) print_debug "Login successful"
                return 0 ;;
    *         ) print_debug "Login failed"
                return 1 ;;
  esac  
}

function do_tests {
  (( ! SKIP_TESTS )) && {
    test_api_url
    do_login
  } || {
    print_debug "-s passed - skipping tests"
  }
}

function check_zone {
  do_tests
  local ZONES="$@"
  if [ -z "${ZONES}" ]; then
    print_error "No zones passed to checkzone" && exit 1
  fi
  for ZONE in ${ZONES}; do
    print_debug "Checking zone [${ZONE}]"
    local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
    local OUTPUT=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/get-zone-info.json" )
    if [ $( ${ECHO} "${OUTPUT}" | ${JQ} -r '.status' ) != "Failed" ]; then
      ${ECHO} "${ZONE}:present"
    else
      ${ECHO} "${ZONE}:absent"
    fi
  done
}

function ns_status {
  do_tests
  if [ "$#" -ne "1" ]; then
    print_error "nsstatus expects exactly one argument" && exit 1
  fi
  local ZONE="$1"
  print_debug "Checking NS status for [${ZONE}]"
  local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
  local NS_STATUS=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/update-status.json" )
  local STATUS=$( ${ECHO} "${NS_STATUS}" | ${JQ} -r '.status' 2>/dev/null )
  if [ "${STATUS}" = "Failed" ]; then
    print_error "No such domain [${ZONE}]" && exit 1
  else
    ${ECHO} "${NS_STATUS}" | ${JQ} -r '.[] | .server + ":" + (.updated|tostring)'
  fi
}

function zone_status {
  do_tests
  local ZONES="$@"
  if [ -z "${ZONES}" ]; then
    print_error "No zones passed to zonestatus" && exit 1
  fi
  for ZONE in ${ZONES}; do
    print_debug "Checking zone status for [${ZONE}]"
    local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
    local IS_UPDATED=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/is-updated.json" )
    if [ "${IS_UPDATED}" = "true" ]; then
      ${ECHO} "${ZONE}:up-to-date"
    elif [ "${IS_UPDATED}" = "false" ]; then
      ${ECHO} "${ZONE}:out-of-date"
    else
      ${ECHO} "${ZONE}:not-valid"
    fi
  done
}

# we don't need to call do_tests in the get_* helper functions, as it
# will have already been called in the calling function
function get_page_count {
  local POST_DATA="${AUTH_POST_DATA} -d rows-per-page=${ROWS_PER_PAGE}"
  local PAGE_COUNT=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/get-pages-count.json" )
  local STATUS=$( ${ECHO} "${PAGE_COUNT}" | ${JQ} -r '.status' 2>/dev/null )
  if [ "${STATUS}" = "Failed" ]; then
    print_error "API call to get-pages-count.json failed" && exit 1
  fi
  ${ECHO} "${PAGE_COUNT}" | ${GREP} -Eqs '^[[:digit:]]+'
  if [ "$?" -ne "0" ]; then
    print_error "Invalid response received from get-pages-count.json" && exit 1
  fi
  ${ECHO} "${PAGE_COUNT}"
}

function get_record_types {
  local POST_DATA="${AUTH_POST_DATA} -d zone-type=domain"
  local RECORD_TYPES=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/get-available-record-types.json" )
  local STATUS=$( ${ECHO} "${RECORD_TYPES}" | ${JQ} -r '.status' 2>/dev/null )
  if [ "${STATUS}" = "Failed" ]; then
    print_error "API call to get-available-record-types.json failed" && exit 1
  fi
  # check for the existence of a common record type, e.g. CNAME
  local INDEX=$( ${ECHO} "${RECORD_TYPES}" | ${JQ} -r 'index("CNAME")' )
  if [ "${INDEX}" = "null" ]; then
    print_error "RECORD_TYPES array does not contain an expected record type"
    exit 1
  fi
  RECORD_TYPES=$( ${ECHO} "${RECORD_TYPES}" | ${JQ} -r '.|join(" ")' )
  ${ECHO} "${RECORD_TYPES}"
}

function get_available_ttls {
  local POST_DATA="${AUTH_POST_DATA}"
  local TTLS=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/get-available-ttl.json" )
  local STATUS=$( ${ECHO} "${TTLS}" | ${JQ} -r '.status' 2>/dev/null )
  if [ "${STATUS}" = "Failed" ]; then
    print_error "API call to get-available-ttl.json failed" && exit 1
  fi
  TTLS=$( ${ECHO} "${TTLS}" | ${JQ} -r '[.[]|tostring]|join(" ")' )
  ${ECHO} "${TTLS}"
}

function has_element {
  local -n CHECK_ARRAY="$1"
  local CHECK_VALUE="$2"
  local VALUE
  for VALUE in ${CHECK_ARRAY[@]}; do
    if [ "${VALUE}" = "${CHECK_VALUE}" ]; then
      return 0
    fi
  done
  return 1
}

function list_records {
  do_tests
  if [ "$#" -eq "0" ]; then
    print_error "listrecords expects at least one argument" && exit 1
  fi
  local ZONE="$1"
  shift
  if [ "$#" -gt "2" ]; then
    print_error "usage: ${THISPROG} listrecords <zone> [type=<type>] [host=<host>]"
    exit 1
  fi
  if [ "$#" -gt "0" ]; then
    local VALID_KEYS=( "type" "host" )
    local KV_PAIRS="$@" ERROR_COUNT=0
    local KV_PAIR
    for KV_PAIR in ${KV_PAIRS}; do
      ${ECHO} "${KV_PAIR}" | ${GREP} -Eqs '^[a-z-]+=[^=]+$'
      if [ "$?" -ne "0" ]; then
        print_error "key-value pair [${KV_PAIR}] not incorrect format" && exit 1
      fi
      local KEY=$( ${ECHO} "${KV_PAIR}" | ${CUT} -d = -f 1 )
      local VALUE=$( ${ECHO} "${KV_PAIR}" | ${CUT} -d = -f 2 )
      print_debug "Checking key-value pair: ${KEY}=${VALUE}"
      if ! has_element VALID_KEYS "${KEY}"; then
        print_error "${KEY} is not a valid key"
        (( ERROR_COUNT = ERROR_COUNT + 1 ))
      fi
      case ${KEY} in
        "type" ) local -a RECORD_TYPES=( $( get_record_types ) )
                 local TMPVAR="${VALUE^^}"
                 if ! has_element RECORD_TYPES "${TMPVAR}"; then
                   print_error "${VALUE} (${TMPVAR}) is not a valid record type"
                   exit 1
                 else
                   local RECORD_TYPE="${VALUE}"
                 fi ;;
        "host" ) local HOST_RECORD="${VALUE}" ;;
      esac
      unset KEY VALUE
    done
  fi
  local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
  if [ -n "${RECORD_TYPE}" ]; then
    POST_DATA="${POST_DATA} -d type=${RECORD_TYPE}"
  fi
  if [ -n "${HOST_RECORD}" -a "${HOST_RECORD}" != "@" ]; then
    POST_DATA="${POST_DATA} -d host=${HOST_RECORD}"
  fi
  print_debug "Fetching records for zone [${ZONE}] with type [${RECORD_TYPE:-not set}] and host [${HOST_RECORD:-not set}]"
  local RECORD_DATA=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/records.json" )
  local RESULT_LENGTH=$( ${ECHO} "${RECORD_DATA}" | ${JQ} -r '.|length' )
  if [ "${RESULT_LENGTH}" -eq "0" ]; then
    print_error "No matching records found" && exit 1
  else
    # output records in BIND format
    #
    # note: the CloudDNS records.json API endpoint has no way of filtering for apex
    # records, so we handle this by changing empty hosts to '@', then select-ing based
    # upon that
    if [ "${HOST_RECORD}" = "@" ]; then
      ${ECHO} "${RECORD_DATA}" | ${JQ} -r 'map(if .host == "" then . + {"host":"@"} else . end) | .[] | select(.host == "@") | .host + "\t" + .ttl + "\tIN\t" + .type + "\t" + .record'
    else
      ${ECHO} "${RECORD_DATA}" | ${JQ} -r 'map(if .host == "" then . + {"host":"@"} else . end) | .[] | .host + "\t" + .ttl + "\tIN\t" + .type + "\t" + .record'
    fi
  fi
}

function get_soa {
  do_tests
  if [ "$#" -ne "1" ]; then
    print_error "getsoa expects exactly one argument" && exit 1
  fi
  local ZONE="$1"
  print_debug "Retrieving SOA details for [${ZONE}]"
  local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
  local SOA_DATA=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/soa-details.json" )
  local STATUS=$( ${ECHO} "${SOA_DATA}" | ${JQ} -r '.status' 2>/dev/null )
  if [ "${STATUS}" = "Failed" ]; then
    local STATUS_DESC=$( ${ECHO} "${SOA_DATA}" | ${JQ} -r '.statusDescription' )
    print_error "Unable to get SOA for [${ZONE}]: ${STATUS_DESC}" && exit 1
  fi
  ${ECHO} "${SOA_DATA}" | ${JQ} -r 'to_entries[] | .key + ":" + .value'
}

function set_soa {
  do_tests
  if [ "$#" -lt "2" ]; then
    print_error "usage: ${THISPROG} setsoa <domain> key=value [key=value key=value ...]"
    exit 1
  fi
  local ZONE="$1"
  print_debug "Modifying SOA record for zone [${ZONE}]"
  shift
  local VALID_KEYS=( "primary-ns" "admin-mail" "refresh" "retry" "expire" "default-ttl" )
  local KV_PAIRS="$@" ERROR_COUNT=0
  local KV_PAIR
  for KV_PAIR in ${KV_PAIRS}; do
    ${ECHO} "${KV_PAIR}" | ${GREP} -Eqs '^[a-z-]+=[^=]+$'
    if [ "$?" -ne "0" ]; then
      print_error "key-value pair [${KV_PAIR}] not incorrect format" && exit 1
    fi
    local KEY=$( ${ECHO} "${KV_PAIR}" | ${CUT} -d = -f 1 )
    local VALUE=$( ${ECHO} "${KV_PAIR}" | ${CUT} -d = -f 2 )
    print_debug "Checking key-value pair: ${KEY}=${VALUE}"
    if ! has_element VALID_KEYS "${KEY}"; then
      print_error "${KEY} is not a valid key"
      (( ERROR_COUNT = ERROR_COUNT + 1 ))
    fi
    unset KEY VALUE
  done
  unset KV_PAIR
  [[ "${ERROR_COUNT}" -gt "0" ]] && exit 1
  # modify-soa.json expects ALL parameters to be set. We will pre-populate via
  # a call to get_soa()
  local SOA_DATA=$( get_soa "${ZONE}" )
  local PRIMARY_NS=$( ${ECHO} "${SOA_DATA}" | ${AWK} -F : '$1 == "primaryNS" { print $2 }' )
  local ADMIN_MAIL=$( ${ECHO} "${SOA_DATA}" | ${AWK} -F : '$1 == "adminMail" { print $2 }' )
  local REFRESH=$( ${ECHO} "${SOA_DATA}" | ${AWK} -F : '$1 == "refresh" { print $2 }' )
  local RETRY=$( ${ECHO} "${SOA_DATA}" | ${AWK} -F : '$1 == "retry" { print $2 }' )
  local EXPIRE=$( ${ECHO} "${SOA_DATA}" | ${AWK} -F : '$1 == "expire" { print $2 }' )
  local DEFAULT_TTL=$( ${ECHO} "${SOA_DATA}" | ${AWK} -F : '$1 == "defaultTTL" { print $2 }' )
  print_debug "Initial SOA paramters loaded via get_soa():"
  print_debug "--> PRIMARY_NS: ${PRIMARY_NS}"
  print_debug "--> ADMIN_MAIL: ${ADMIN_MAIL}"
  print_debug "--> REFRESH: ${REFRESH}"
  print_debug "--> RETRY: ${RETRY}"
  print_debug "--> EXPIRE: ${EXPIRE}"
  print_debug "--> DEFAULT_TTL: ${DEFAULT_TTL}"
  local CHANGED=0
  for KV_PAIR in ${KV_PAIRS}; do
    local KEY=$( ${ECHO} "${KV_PAIR}" | ${CUT} -d = -f 1 )
    local VALUE=$( ${ECHO} "${KV_PAIR}" | ${CUT} -d = -f 2 )
    # no default required in case as we've already checked against VALID_KEYS
    case ${KEY} in
      "primary-ns"  ) validate_soa_value ns "${VALUE}"
                      if [ "$?" -ne "0" ]; then
                        print_error "Validation of primary-ns failed" && exit 1
                      else
                        if [ "${PRIMARY_NS}" = "${VALUE}" ]; then
                          print_timestamp "primary-ns value same as existing"
                        else
                          PRIMARY_NS="${VALUE}"
                          (( CHANGED = CHANGED + 1 ))
                        fi
                      fi
                      ;;
      "admin-mail"  ) validate_soa_value email "${VALUE}"
                      if [ "$?" -ne "0" ]; then
                        print_error "Validation of admin-mail failed" && exit 1
                      else
                        if [ "${ADMIN_MAIL}" = "${VALUE}" ]; then
                          print_timestamp "admin-mail value same as existing"
                        else
                          ADMIN_MAIL="${VALUE}"
                          (( CHANGED = CHANGED + 1 ))
                        fi
                      fi
                      ;;
      "refresh"     ) validate_soa_value refresh "${VALUE}"
                      if [ "$?" -ne "0" ]; then
                        print_error "Validation of refresh failed" && exit 1
                      else
                        if [ "${REFRESH}" = "${VALUE}" ]; then
                          print_timestamp "refresh value same as existing"
                        else
                          REFRESH="${VALUE}"
                          (( CHANGED = CHANGED + 1 ))
                        fi
                      fi
                      ;;
      "retry"       ) validate_soa_value retry "${VALUE}"
                      if [ "$?" -ne "0" ]; then
                        print_error "Validation of retry failed" && exit 1
                      else
                        if [ "${RETRY}" = "${VALUE}" ]; then
                          print_timestamp "retry value same as existing"
                        else
                          RETRY="${VALUE}"
                          (( CHANGED = CHANGED + 1 ))
                        fi
                      fi
                      ;;
      "expire"      ) validate_soa_value expire "${VALUE}"
                      if [ "$?" -ne "0" ]; then
                        print_error "Validation of expire failed" && exit 1
                      else
                        if [ "${EXPIRE}" = "${VALUE}" ]; then
                          print_timestamp "expire value same as existing"
                        else
                          EXPIRE="${VALUE}"
                          (( CHANGED = CHANGED + 1 ))
                        fi
                      fi
                      ;;
      "default-ttl" ) validate_soa_value ttl "${VALUE}"
                      if [ "$?" -ne "0" ]; then
                        print_error "Validation of default-ttl failed" && exit 1
                      else
                        if [ "${DEFAULT_TTL}" = "${VALUE}" ]; then
                          print_timestamp "default-ttl value same as existing"
                        else
                          DEFAULT_TTL="${VALUE}"
                          (( CHANGED = CHANGED + 1 ))
                        fi
                      fi
                      ;;
    esac
  done 
  if [ "${CHANGED}" -eq "0" ]; then
    print_timestamp "Nothing has changed - no need to modify" && exit 0
  fi
  print_debug "SOA paramters loaded after modification:"
  print_debug "--> PRIMARY_NS: ${PRIMARY_NS}"
  print_debug "--> ADMIN_MAIL: ${ADMIN_MAIL}"
  print_debug "--> REFRESH: ${REFRESH}"
  print_debug "--> RETRY: ${RETRY}"
  print_debug "--> EXPIRE: ${EXPIRE}"
  print_debug "--> DEFAULT_TTL: ${DEFAULT_TTL}"
  local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
  POST_DATA="${POST_DATA} -d primary-ns=${PRIMARY_NS}"
  POST_DATA="${POST_DATA} -d admin-mail=${ADMIN_MAIL}"
  POST_DATA="${POST_DATA} -d refresh=${REFRESH}"
  POST_DATA="${POST_DATA} -d retry=${RETRY}"
  POST_DATA="${POST_DATA} -d expire=${EXPIRE}"
  POST_DATA="${POST_DATA} -d default-ttl=${DEFAULT_TTL}"
  local RESPONSE=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/modify-soa.json" )
  local STATUS=$( ${ECHO} "${RESPONSE}" | ${JQ} -r '.status' )
  local STATUS_DESC=$( ${ECHO} "${RESPONSE}" | ${JQ} -r '.statusDescription' )
  if [ "${STATUS}" = "Failed" ]; then
    print_error "Failed to modify SOA for zone [${ZONE}]: ${STATUS_DESC}" && exit 1
  elif [ "${STATUS}" = "Success" ]; then
    print_timestamp "SOA for zone [${ZONE}] modified"
  else
    print_error "Unexpected response while modifiying SOA for zone [${ZONE}]" && exit 1
  fi
}

function check_integer {
  local VALUE="$1"
  local LOWER="$2"
  local UPPER="$3"
  ${ECHO} "${VALUE}" | ${GREP} -Eqs '^[[:digit:]]+' || return 1
  if [ "${VALUE}" -ge "${LOWER}" -a "${VALUE}" -le "${UPPER}" ]; then
    return 0
  else
    return 1
  fi
}

function validate_soa_value {
  # see https://www.cloudns.net/wiki/article/63/ for permissible integer values
  local TYPE="$1"
  local VALUE="$2"
  case ${TYPE} in
    "ns"      ) # check for at least something.something
                ${ECHO} "${VALUE}" | ${GREP} -Eqs '^[a-z0-9-]+\.[a-z0-9-]+'
                return $? ;;
    "email"   ) # check for at least something@something
                ${ECHO} "${VALUE}" | ${GREP} -Eqs '^[^@]+@[^@]+$'
                return $? ;;
    "refresh" ) check_integer ${VALUE} 1200 43200
                return $? ;;
    "retry"   ) check_integer ${VALUE} 180 2419200
                return $? ;;
    "expire"  ) check_integer ${VALUE} 1209600 2419200
                return $? ;;
    "ttl"     ) check_integer ${VALUE} 60 2419200
                return $? ;;
  esac
}

function dump_zone {
  do_tests
  if [ "$#" -ne "1" ]; then
    print_error "dumpzone expects exactly one argument" && exit 1
  fi
  local ZONE="$1"
  print_debug "Dumping BIND-format zone file for [${ZONE}]"
  local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
  local ZONE_DATA=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/records-export.json" )
  local STATUS=$( ${ECHO} "${ZONE_DATA}" | ${JQ} -r '.status' )
  if [ "${STATUS}" = "Success" ]; then
    ${ECHO} "${ZONE_DATA}" | ${JQ} -r '.zone'
  else
    print_error "Unable to get zone file for [${ZONE}]" && exit 1
  fi
}

function add_zone {
  do_tests
  if [ "$#" -ne "1" ]; then
    print_error "addzone expects exactly one argument" && exit 1
  fi
  local ZONE="$1"
  local ZONE_TYPE="master" # we only support master zones
  print_debug "Adding new ${ZONE_TYPE} zone for [${ZONE}]"
  local POST_DATA="${AUTH_POST_DATA} -d zone-type=${ZONE_TYPE} -d domain-name=${ZONE}"
  local RESPONSE=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/register.json" )
  local STATUS=$( ${ECHO} "${RESPONSE}" | ${JQ} -r '.status' )
  local STATUS_DESC=$( ${ECHO} "${RESPONSE}" | ${JQ} -r '.statusDescription' )
  if [ "${STATUS}" = "Failed" ]; then
    print_error "Failed to add zone [${ZONE}]: ${STATUS_DESC}" && exit 1
  elif [ "${STATUS}" = "Success" ]; then
    print_timestamp "New zone [${ZONE}] added"
  else
    print_error "Unexpected response while adding zone [${ZONE}]" && exit 1
  fi
}

function delete_zone {
  do_tests
  if [ "$#" -ne "1" ]; then
    print_error "delzone expects exactly one argument" && exit 1
  fi
  local ZONE="$1"
  print_debug "Deleting zone [${ZONE}]"
  ${ECHO} "Are you sure you want to delete zone [${ZONE}]?"
  ${ECHO} -n "You must type I-AM-SURE, exactly: "
  local RESPONSE=""
  builtin read RESPONSE
  if [ "${RESPONSE}" != "I-AM-SURE" ]; then
    print_error "Aborting removal of zone [${ZONE}]" && exit 1
  fi
  ${ECHO} "Okay. Waiting ${REMOVAL_WAIT}s prior to removal. CTRL-C now if unsure!"
  ${SLEEP} ${REMOVAL_WAIT}
  local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
  local RESPONSE=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/delete.json" )
  local STATUS=$( ${ECHO} "${RESPONSE}" | ${JQ} -r '.status' )
  local STATUS_DESC=$( ${ECHO} "${RESPONSE}" | ${JQ} -r '.statusDescription' )
  if [ "${STATUS}" = "Failed" ]; then
    print_error "Unable to delete zone [${ZONE}]: ${STATUS_DESC}" && exit 1
  elif [ "${STATUS}" = "Success" ]; then
    print_timestamp "Zone [${ZONE}] deleted"
  else
    print_error "Unexpected response while deleting zone [${ZONE}]" && exit 1
  fi
}

function list_zones {
  do_tests
  local PAGE_COUNT=$( get_page_count )
  local COUNTER=0
  local POST_DATA="${AUTH_POST_DATA} -d page=0 -d rows-per-page=${ROWS_PER_PAGE}"
  while [ "${COUNTER}" -lt "${PAGE_COUNT}" ]; do
    print_debug "Processing listzones page=$(( ${COUNTER} + 1 )) with rows-per-page=${ROWS_PER_PAGE}"
    POST_DATA=$( ${ECHO} "${POST_DATA}" |\
                 ${SED} "s/^\(.*-d page=\)[0-9][0-9]*\( .*\)$/\1$(( ${COUNTER} + 1 ))\2/" )
    local OUTPUT=$( ${CURL} -4qs -X POST ${POST_DATA} "${API_URL}/list-zones.json" | ${JQ} -r . )
    ${ECHO} "${OUTPUT}" | ${JQ} -r '.[] | .name + ":" + .type'
    (( COUNTER = COUNTER + 1 ))
  done
}

function call_helper {
  do_tests
  if [ "$#" -ne "1" ]; then
    print_error "helper expects exactly one argument" && exit 1
  fi
  local HELPER_FUNCTION="$1"
  print_debug "Calling helper function ${HELPER_FUNCTION}()"
  case ${HELPER_FUNCTION} in
    "get_available_ttls" ) get_available_ttls ;;
    "get_record_types"   ) get_record_types   ;;
    "get_page_count"     ) get_page_count     ;;
    *                    ) print_error "No such helper function ${HELPER_FUNCTION}"
                           exit 1             ;;
  esac
}

function test_login {
  # don't check SKIP_TESTS here as this is the "test" command
  test_api_url
  do_login
  if [ "$?" -eq "0" ]; then
    print_timestamp "Login test successful"
  else
    print_error "Login test failed"
    exit 1
  fi
}

while ${GETOPTS} ":dhs" OPTION; do
  case ${OPTION} in
    "d") DEBUG=1               ;;
    "h") print_usage && exit 0 ;;
    "s") SKIP_TESTS=1          ;;
    *  ) print_usage && exit 1 ;;
  esac
done

shift $(( ${OPTIND} - 1 ))

if [ "$#" -eq "0" ]; then
  print_usage && exit 1
fi

check_environment_variables
set_auth_post_data
process_arguments "$@"

exit 0
