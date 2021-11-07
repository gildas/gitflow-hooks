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

ERROR=

function color()        { echo -e "\e38;5;$0m"; }
function verbose()      { [[ $VERBOSE > 0 ]] && echo -e "$@"; }
function success()      { echo -e "${CHECK} $@" ; }
function warn()         { echo -e "${YELLOW}Warning: $@${DEFAULT}"; }
function error()        { echo -e "${CROSS} ${RED}Error: $@${DEFAULT}" >&2; }
function die()          { error "${1:-${ERROR:-Unknown Error}}, Error: ${2:-1}" ; exit ${2:-1} ; }
function die_on_error() { local status=$? ; (( status )) && die "$@" $status; }

# Remove the version prefix, if any
function normalize_version() { # {{{2
  local version=$1
  local version_tag=$(get_config gitflow.prefix.versiontag)

  [[ -n $version_tag ]] && printf "%s" ${version##*$version_tag} || printf "%s" $version
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
      ERROR="Unsupported bump type: $what"
      return 1
  esac
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
  (( value == "true" ))
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
