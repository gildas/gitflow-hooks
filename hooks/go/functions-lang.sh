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
  local status

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei.bak "/^var[ ]+VERSION[ ]*=/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
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

# lint_staged_files runs golangci-lint and staticcheck on the packages of the staged Go files
function lint_staged_files() { # {{{2
  local status
  local files=( $(git diff --cached --name-only --diff-filter=ACMR -- '*.go') )
  (( ${#files[@]} )) || return 0
  local packages=( $(for file in "${files[@]}"; do printf "./%s\n" "$(dirname "$file")"; done | sort -u) )

  if command -v golangci-lint &>/dev/null; then
    golangci-lint run "${packages[@]}"
    status=$?
    (( status )) && ERROR="The golangci-lint tool found issues" && return 1
    (( ! status )) && verbose "The golangci-lint tool found no issues"
  else
    warn "golangci-lint is not installed, skipping"
  fi

  if command -v staticcheck &>/dev/null; then
    staticcheck "${packages[@]}"
    status=$?
    (( status )) && ERROR="The staticcheck tool found issues" && return 1
    (( ! status )) && verbose "The staticcheck tool found no issues"
  else
    warn "staticcheck is not installed, skipping"
  fi
  return 0
} # 2}}}
