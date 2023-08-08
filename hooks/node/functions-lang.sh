#!/usr/bin/env bash

function find_version_file() { # {{{2
  local file=package.json

  [[ -z $file ]] && ERROR="Failed to find package.json" && return 1

  printf "%s" $file
  return 0
} # 2}}}

function get_version() { # {{{2
  local status
  local file=$1
  local version=$(grep -E '^[ \t]*"version":' "$file" | sed -E 's/^[ \t]*"version":[ \t]*"([0-9]+\.[0-9]+\.[0-9]+)"[ \t]*,$/\1/')
  
  status=$? ; (( status )) && ERROR="Failed to get the version from $file" && return $status
  printf "%s" $version
  return 0
} # 2}}}

function update_version_file() { # {{{2
  local file=$1
  local version=$2
  local status

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei .bak "/^[ \t]*\"version\":[ \t]*\"/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
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
