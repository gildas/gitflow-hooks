#!/usr/bin/env bash

function find_version_file() { # {{{2
  local status
  local file=$(grep -lE "^var[ ]+VERSION[ ]*=" "$ROOT_DIR"/*.go)

  status=$? ; [[ $status != 0 ]] && ERROR="Failed to grep through $ROOT_DIR" && return $status
  [[ -z $file ]] && ERROR="Failed to find a file carrying the version" && return 1

  printf "%s" $file
  return 0
} # 2}}}

function get_version() { # {{{2
  local status
  local file=$1
  local version=$(grep -E "^var[ ]+VERSION[ ]*=" $file | sed -E "s/^var[ ]+VERSION[ ]*=[ ]*\"([0-9]+\.[0-9]+\.[0-9]+)\"/\1/")
  status=$? ; (( status )) && ERROR="Failed to get the version from $file" && return $status
  printf "%s" $version
  return 0
} # 2}}}

function update_version_file() { # {{{2
  local file=$1
  local version=$2

  sed -Ei "/^var[ ]+VERSION[ ]*=/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
  return 0
} # 2}}}
