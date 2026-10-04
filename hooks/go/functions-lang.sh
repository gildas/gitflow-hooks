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

# prettify_staged_files formats the staged Go files with gofmt
function prettify_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR -- '*.go') )
  (( ${#files[@]} )) || return 0
  local gofmt=$(command -v gofmt)
  local file output mode blob formatted stop_processing=0

  if [[ -z $gofmt ]]; then
    gofmt=$GOROOT/bin/gofmt
    [[ ! -e $gofmt ]] && ERROR="The gofmt tool is missing" && return 1
  fi

  for file in "${files[@]}"; do
    if git diff --quiet -- "$file"; then
      output=$($gofmt -s -w "$file" 2>&1)
      if (( $? )); then
        error "$file is not formatted properly: $output"
        stop_processing=1
      else
        git add "$file"
      fi
    else
      # The file is partially staged: format the staged content only, so the unstaged changes stay out of the commit
      formatted=$(mktemp)
      output=$(git show ":$file" | $gofmt -s 2>&1 > "$formatted")
      if (( $? )); then
        error "$file is not formatted properly: $output"
        stop_processing=1
      else
        mode=$(git ls-files --stage -- "$file" | cut -d' ' -f1)
        blob=$(git hash-object -w "$formatted")
        git update-index --cacheinfo "$mode,$blob,$file"
        # Also format the working copy, so it does not show the formatting as unstaged changes; ignore errors from unfinished code
        $gofmt -s -w "$file" &>/dev/null
      fi
      rm -f "$formatted"
    fi
  done
  (( stop_processing )) && ERROR="gofmt could not format some files" && return 1
  return 0
} # 2}}}
