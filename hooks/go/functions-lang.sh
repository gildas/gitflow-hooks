#!/usr/bin/env bash

function find_version_file() { # {{{2
  local file=$(get_config gitflow.path.versionfile "")
  local candidate

  if [[ -z $file ]]; then
    # Use the shallowest Go file that declares VERSION (e.g.: version.go, src/backend/version.go)
    while IFS= read -r candidate; do
      if grep -qE "^var[ ]+VERSION[ ]*=" "$ROOT_DIR/$candidate"; then
        file=$candidate
        break
      fi
    done < <(list_repository_files '*.go')
  fi
  [[ -n $file && $file != /* ]] && file="$ROOT_DIR/$file"

  [[ -f $file ]] || return $(error "Failed to find a file carrying the version in $ROOT_DIR")

  printf "%s" "$file"
  return 0
} # 2}}}

function get_version() { # {{{2
  local file=$1
  local version=$(grep -E "^var[ ]+VERSION[ ]*=" "$file" | sed -E "s/^var[ ]+VERSION[ ]*=[ ]*\"([0-9]+\.[0-9]+\.[0-9]+)\"/\1/")
  local status=$? ; (( status )) && { (exit $status); return $(error "Failed to get the version from $file"); }
  printf "%s" $version
  return 0
} # 2}}}

function update_and_stage_version_file() { # {{{2
  local file=$1
  local version=$2
  local status

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei.bak "/^var[ ]+VERSION[ ]*=/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to update ${file##*/}"); }
  git add "$file"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage ${file##*/}"); }
  success "Updated ${file##*/}"
  rm -f "$file.bak"
  # Update and stage the package.json file as well in case the repository contains a web client
  # This happens when this repository is a Go backend with an embedded web client
  return $(update_and_stage_package_json "$version")
} # 2}}}

# lint_staged_files runs golangci-lint and staticcheck on the packages of the staged Go files
function lint_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR -- '*.go') )
  local status
  (( ${#files[@]} )) || return 0
  local packages=( $(for file in "${files[@]}"; do printf "./%s\n" "$(dirname "$file")"; done | sort -u) )

  if command -v golangci-lint &>/dev/null; then
    local options=() patch base
    if get_config_bool gitflow.lint-new-issues-only false; then
      # The packages are still analyzed as a whole (Go type-checks packages, not files),
      # but only the issues on the staged lines are reported, the existing ones do not block the commit
      patch=$(mktemp)
      # golangci-lint reads the working tree, so the patch must carry its line numbers, not the index's:
      # in a partially staged file, the unstaged lines would shift the staged issues out of an index patch.
      # The unstaged changes of the staged files are reported as well, which can only be stricter.
      base=$(git rev-parse --verify --quiet HEAD || git hash-object -t tree /dev/null) # no HEAD on the first commit
      # Explicit prefixes, as golangci-lint expects them (diff.noprefix or diff.mnemonicPrefix would change them)
      git diff --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ "$base" -- "${files[@]}" > "$patch"
      options=(--new-from-patch="$patch")
      verbose "Reporting only the issues on the staged lines (gitflow.lint-new-issues-only)"
    fi
    verbose "Running golangci-lint on the following packages: ${packages[*]}"
    golangci-lint run "${options[@]}" "${packages[@]}"
    status=$?
    [[ -n $patch ]] && rm -f "$patch"
    (( status )) && { (exit $status); return $(error "The golangci-lint tool found issues"); }
    success "The golangci-lint tool found no issues"
  elif command -v staticcheck &>/dev/null; then
    get_config_bool gitflow.lint-new-issues-only false && warn "staticcheck cannot report only the new issues (gitflow.lint-new-issues-only), it reports all the issues of the staged packages"
    verbose "Running staticcheck on the following packages: ${packages[*]}"
    staticcheck "${packages[@]}"
    status=$? ; (( status )) && { (exit $status); return $(error "The staticcheck tool found issues"); }
    success "The staticcheck tool found no issues"
  else
    warn "neither golangci-lint nor staticcheck found, skipping"
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
    [[ ! -e $gofmt ]] && return $(error "The gofmt tool is missing")
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
  (( stop_processing )) && return $(error "gofmt could not format some files")
  success "The gofmt tool formatted the files successfully"
  return 0
} # 2}}}
