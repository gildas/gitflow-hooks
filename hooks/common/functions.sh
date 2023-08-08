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

CHECK=$(printf ${BOLD}${GREEN}'✔'${DEFAULT})
CROSS=$(printf ${BOLD}${RED}'✘'${DEFAULT})

ROOT_DIR=$(git rev-parse --show-toplevel)

ERROR=

function color()        { echo -e "\e38;5;$0m"; }
function verbose()      { [[ $VERBOSE > 0 ]] && echo -e "$@" >&2; }
function success()      { echo -e "${CHECK} $@" >&2 ; }
function warn()         { echo -e "${YELLOW}Warning: $@${DEFAULT}" >&2; }
function error()        { echo -e "${CROSS} ${RED}Error: $@${DEFAULT}" >&2; }
function die()          { error "${1:-${ERROR:-Unknown Error}}, Error: ${2:-1}" ; exit ${2:-1} ; }
function die_on_error() { local status=$? ; (( status )) && die "$@" $status; }

# Remove the version prefix, if any
function normalize_version() { # {{{2
  local version=$1
  local version_tag=$(get_config gitflow.prefix.versiontag)

  [[ -n $version_tag ]] && printf "%s" ${version##*$version_tag} || printf "%s" $version
} # 2}}}

# bump_version bumps the given version by the given bump
#
# bump can be one of major, minor, patch
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
      error "Unsupported bump type: $what"
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
  [[ -z $value ]] && value=${2:-false}
  [[ $value == "true" ]] && return 0 || return 1
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

function get_chart_version() { # {{{2
  local status
  local file=$1
  local version=$(grep "^version:" "$file" | sed -E "s/^version:\s+([0-9]+\.[0-9]+\.[0-9]+)/\1/")
  status=$? ; (( status )) && ERROR="Failed to get the version from $file" && return $status
  printf "%s" $version
  return 0
} # 2}}}

function update_chart_version() { # {{{2
  local file=$1
  local version=$2

  verbose "Updating Chart: ${file##*/} to ${version}"
  sed -Ei "/^version:/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
  return 0
} # 2}}}

function update_chart_appversion() { # {{{2
  local file=$1
  local version=$2
  local status

  verbose "Updating App Version: ${file##*/} to ${version}"
  sed -Ei "/^appVersion:/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
  status=$? ; (( status )) && error "Failed to update ${file##*/}, exit code: $status" || success "Updated ${file##*/}"
  return 0
} # 2}}}

function update_dockerfile_version() { # {{{2
  local file=$1
  local version=$2
  local now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local status

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei \
    -e "/^LABEL\s+org\.opencontainers\.image\.version/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" \
    -e "/^LABEL\s+org\.opencontainers\.image\.created/s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" \
    "$file"
  status=$? ; (( status )) && error "Failed to update ${file##*/}, exit code: $status" || success "Updated ${file##*/}"
} # 2}}}

function update_appveyor_version() { # {{{2
  local file=$1
  local version=$2
  local status

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei \
    -e "/^version:/s/.*/version: ${version}+{build}/" \
    "$file"
  status=$? ; (( status )) && error "Failed to update ${file##*/}, exit code: $status" || success "Updated ${file##*/}"
} # 2}}}

