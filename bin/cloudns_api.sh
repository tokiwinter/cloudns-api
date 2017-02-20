#!/bin/bash

BASENAME="/usr/bin/basename"
CURL="/usr/bin/curl"
DATE="/usr/bin/date"
ECHO="builtin echo"
EVAL="builtin eval"
GETOPTS="builtin getopts"
JQ="/usr/bin/jq"
SED="/usr/bin/sed"
TEST="/usr/bin/test"

API_URL="https://api.cloudns.net/dns"
DEBUG=0
SKIP_TESTS=0
THISPROG=$( ${BASENAME} $0 )

ROWS_PER_PAGE=100

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
    "listzones"    ) list_zones "$@"          ;;
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

function test_api_url {
  local HTTP_CODE=$( ${CURL} -4qs -o /dev/null -w '%{http_code}' ${API_URL}/login.json )
  if [ "${HTTP_CODE}" != "200" ]; then
    print_error "Unable to reach ClouDNS API" && exit 1
  else
    print_debug "API availability check successful"
  fi
}

function do_login {
  local GET_STRING="auth-id=${CLOUDNS_API_ID}&auth-password=${CLOUDNS_PASSWORD}"
  local STATUS=$( ${CURL} -4qs -X GET "${API_URL}/login.json&${GET_STRING}" | ${JQ} -r '.status' )
  case ${STATUS} in
    "Success" ) print_debug "Login successful"
                return 0 ;;
    *         ) print_debug "Login failed"
                return 1 ;;
  esac  
}

# limitation: presumes you are authoritative for <= 100 zones
function list_zones {
  (( ! SKIP_TESTS )) && {
    test_api_url
    do_login
  }
  local GET_STRING="auth-id=${CLOUDNS_API_ID}&auth-password=${CLOUDNS_PASSWORD}"
  GET_STRING="${GET_STRING}&page=0&rows-per-page=${ROWS_PER_PAGE}"
  local FLAG=""
  local COUNTER=1
  while [ "${FLAG}" != "STOP" ]; do
    print_debug "Processing listzones page=${COUNTER} with rows-per-page=${ROWS_PER_PAGE}"
    GET_STRING=$( ${ECHO} "${GET_STRING}" |\
                  ${SED} "s/^\(.*&page=\)[0-9][0-9]*\(&.*\)$/\1${COUNTER}\2/" )
    local OUTPUT=$( ${CURL} -4qs -X GET "${API_URL}/list-zones.json&${GET_STRING}" | ${JQ} -r . )
    if [ "${OUTPUT}" = "[]" ]; then
      FLAG="STOP"
    else
      ${ECHO} "${OUTPUT}" | ${JQ} -r '.[] | .name + ":" + .type'
    fi
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
process_arguments "$@"

exit 0
