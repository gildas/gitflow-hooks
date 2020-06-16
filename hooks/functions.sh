#!/usr/bin/env bash

BLACK=$(printf '\e[30m')
RED=$(printf '\e[31m')
GREEN=$(printf '\e[32m')
YELLOW=$(printf '\e[33m')
BLUE=$(printf '\e[34m')
MAGENTA=$(printf '\e[35m')
CYAN=$(printf '\e[36m')
WHITE=$(printf '\e[37m')
GREY=$(printf '\e[36m')
DEFAULT=$(printf '\e[m')

BOLD=$(printf '\e[1m')
UNDERLINE=$(printf '\e[4m')
REVERSED=$(printf '\e[7m')

CHECK=$(printf ${GREEN}'✔'${DEFAULT})
CROSS=$(printf ${BOLD}${RED}'✘'${DEFAULT})

ROOT_DIR=$(git rev-parse --show-toplevel)

function color() { echo -e "\e38;5;$0m"; }
function verbose() { [[ $VERBOSE > 0 ]] && echo -e "$@"; }
function success() { echo -e "${CHECK} $@" ; }
function warn()    { echo -e "Warning: $@"; }
function error()   { echo -e "${CROSS} ${RED}Error: $@${DEFAULT}" >&2; }

function die()  { # {{{2
  local message=$1
  local errorlevel=$2

  [[ -z $message    ]] && message='Died'
  [[ -z $errorlevel ]] && errorlevel=1
  error "$message"
  exit $errorlevel
} # 2}}}

function die_on_error() { # {{{2
  local status=$?
  local message=$1

  if [[ $status != 0 ]]; then
    die "${message}, Error: $status" $status
  fi
} # 2}}}

function find_version_file() { # {{{2
  local status
  local ext=$1
  local file=$(grep -lE "^var[ ]+VERSION[ ]*=" "$ROOT_DIR"/*.${ext})

  status=$? ; [[ $status != 0 ]] && (error "Failed to grep through $ROOT_DIR" ; return $status)
  [[ -z $file ]] && (error "Failed to find a file carrying the version" ; return 1)

  printf "%s" $file
  return 0
} # 2}}}

function get_version() { # {{{2
  local status
  local file=$1
  local version=$(grep -E "^var[ ]+VERSION[ ]*=" $file | sed -E "s/^var[ ]+VERSION[ ]*=[ ]*\"([0-9]+\.[0-9]+\.[0-9]+)\"/\1/")
  status=$? ; [[ $status != 0 ]] && (error "Failed to get the version from $file" ; return $status)
  printf "%s" $version
  return 0
} # 2}}}

function bump_version() { # {{{2
  local version=$1
  local what=$2
  local components=( $(echo $version | tr "."  " ") )

  case $what in
    major)
      printf "%s.0.0" $((components[0] + 1))
      ;;
    minor)
      printf "%s.%s.0" ${components[0]} $((components[1] + 1))
      ;;
    patch)
      printf "%s.%s.%s" ${components[0]} ${components[1]} $((components[2] + 1))
      ;;
    *)
      error "Unsupported bump type: $what"
      return 1
  esac
  return 0
} # 2}}}

function update_version_file() { # {{{2
  local file=$1
  local version=$2

  sed -Ei "/^var[ ]+VERSION[ ]*=/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
  return 0
} # 2}}}

function is_binary() { # {{{2
  # Thanks to: https://github.com/jaspernbrouwer/git-flow-hooks/blob/6677eb5e45b4d5597de7ac4446e1353e61be9398/modules/functions.sh#L50
  P=$(printf '%s\t-\t' -)
  T=$(git diff --no-index --numstat /dev/null "$1")

  case "$T" in "$P"*) return 0 ;; esac
  return 1
} # 2}}}

function get_config_bool() { # {{{2
  [[ -z $1 ]] && return 1
  local value=$(git config --get --bool $1)
  [[ $value == "true" ]]
} # 2}}}

function get_config() { # {{{2
  local key=$1
  local default=$2

  [[ -z $key ]] && (printf "" ; return 0)
  local value=$(git config --get $key)
  if [[ -n $value ]]; then
    printf "%s" "$value"
  else
    printf "%s" "$default"
  fi
  return 0
} # 2}}}

