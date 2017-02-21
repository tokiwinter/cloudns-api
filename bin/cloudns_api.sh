#!/bin/bash

BASENAME="/usr/bin/basename"
CURL="/usr/bin/curl"
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
                     list_records "$@"        ;; # notimplemented
    "getsoa"  )      shift
                     get_soa "$@"             ;; # notimplemented
    "setsoa"  )      shift
                     set_soa "$@"             ;; # notimplemented
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
    print_error "usage: ${THISPROG} listrecords <zone> [<type> <host>]"
    exit 1
  fi
  if [ "$#" -gt "0" ]; then
    local -a RECORD_TYPES=( $( get_record_types ) )
    local RECORD_TYPE HOST_RECORD
    while [ "$#" -ne "0" ]; do
      if [ -n "$1" ]; then
        local TMPVAR="${1^^}"
        # pass RECORD_TYPES array by reference
        if has_element RECORD_TYPES "${TMPVAR}"; then
          if [ -z "${RECORD_TYPE}" ]; then
            RECORD_TYPE="$1"
          else
            print_error "Multiple record types passed to listrecords"
            exit 1
          fi
        else
          if [ -z "${HOST_RECORD}" ]; then
            HOST_RECORD="$1" 
          else
            print_error "Multiple hostnames passed to listrecords or invalid record type specified"
            exit 1
          fi
        fi
      fi
      shift
    done
  fi
  local POST_DATA="${AUTH_POST_DATA} -d domain-name=${ZONE}"
  if [ -n "${RECORD_TYPE}" ]; then
    POST_DATA="${POST_DATA} -d type=${RECORD_TYPE}"
  fi
  if [ -n "${HOST_RECORD}" -a "${HOST_RECORD}" != "@" ]; then
    POST_DATA="${POST_DATA} -d host=${HOST_RECORD}"
  fi
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
