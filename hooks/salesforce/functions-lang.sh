#!/usr/bin/env bash

function find_version_file() { # {{{2
  local file="sfdx-project.json"

  [[ -z $file ]] && ERROR="Failed to find $file" && return 1

  printf "%s" $file
  return 0
} # 2}}}

function get_version() { # {{{2
  local status
  local file=$1
  local version=$(grep -E '^[ \t]*"versionName":' "$file" | sed -E 's/^[ \t]*"versionName":[ \t]*"([0-9]+\.[0-9]+"[ \t]*,$/\1/')
  
  version="${version}.0" # Salesforce does not support patch numbers
  status=$? ; (( status )) && ERROR="Failed to get the version from $file" && return $status
  printf "%s" $version
  return 0
} # 2}}}

function update_version_file() { # {{{2
  local file=$1
  local version=$2
  local status

  # Salesforce does not support patch numbers, so we need to remove it
  version=${version%.0}
  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei.bak "/^[ \t]*\"versionName\":[ \t]*\"/s/[0-9]+\.[0-9]+/${version}/" "$file"
  status=$?
  if (( status )); then
    error "Failed to update ${file##*/}, exit code: $status"
    return $status
  else
    success "Updated ${file##*/}"
    rm -f "$file.bak"
  fi
  return 0
} # 2}}}

# bump_version bumps the given version by the given bump
#
# We have to overwrite the default function for Salesforce as they do not support patch bump.s
#
# bump can be one of major, minor
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
      ERROR="Salesforce does not support patch bumps"
      error "Salesforce does not support patch bumps"
      return 1
      ;;
    *)
      ERROR="Unsupported bump type: $what"
      error "Unsupported bump type: $what"
      return 1
  esac
  return 0
} # 2}}}

