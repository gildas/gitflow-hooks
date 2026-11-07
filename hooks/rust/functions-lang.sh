#!/usr/bin/env bash

# The version of a Rust project lives in Cargo.toml:
# - in [workspace.package] for a workspace whose members use `version.workspace = true`,
# - in [package] for a single crate (or when gitflow.path.versionfile points to a member's Cargo.toml).

# get_cargo_version_section prints the Cargo.toml section carrying the version (workspace.package or package)
function get_cargo_version_section() { # {{{2
  local file=$1
  local section

  for section in workspace.package package; do
    if [[ -n $(get_cargo_value "$file" "$section" version) ]]; then
      printf "%s" "$section"
      return 0
    fi
  done
  error "Failed to find a version in [workspace.package] or [package] of $file. If each workspace member has its own version, set gitflow.path.versionfile to the Cargo.toml of the member carrying the version"
} # 2}}}

# get_cargo_value prints the string value of the given key in the given section of a Cargo.toml file
# Only literal strings are printed, `version.workspace = true` is ignored
function get_cargo_value() { # {{{2
  local file=$1
  local section=$2
  local key=$3

  awk -v section="$section" -v key="$key" '
    /^[[:space:]]*\[/ {
      line = $0
      sub(/#.*/, "", line)
      gsub(/[[:space:]]/, "", line)
      in_section = (line == "[" section "]")
      next
    }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=[[:space:]]*\"" {
      value = $0
      sub(/^[^"]*"/, "", value)
      sub(/".*$/, "", value)
      print value
      exit
    }
  ' "$file"
} # 2}}}

# find_cargo_lock prints the Cargo.lock of the workspace the given Cargo.toml belongs to, if any
function find_cargo_lock() { # {{{2
  local dir=$(cd "$(dirname "$1")" && pwd)
  local root=$(cd "$ROOT_DIR" && pwd)

  while :; do
    [[ -f $dir/Cargo.lock ]] && { printf "%s" "$dir/Cargo.lock"; return 0; }
    [[ $dir == "$root" || $dir == / ]] && return 1
    dir=$(dirname "$dir")
  done
} # 2}}}

function find_version_file() { # {{{2
  local file=$(get_config gitflow.path.versionfile "")
  local candidate

  if [[ -z $file ]]; then
    # Use the shallowest Cargo.toml (e.g.: Cargo.toml, src/backend/Cargo.toml), which is the workspace root, if any
    file=$(list_repository_files Cargo.toml '*/Cargo.toml' | head -n 1)
  fi
  [[ -n $file && $file != /* ]] && file="$ROOT_DIR/$file"

  [[ -f $file ]] || return $(error "Failed to find a Cargo.toml in $ROOT_DIR")

  printf "%s" "$file"
  return 0
} # 2}}}

function get_version() { # {{{2
  local file=$1
  local section version

  section=$(get_cargo_version_section "$file") || return 1
  version=$(get_cargo_value "$file" "$section" version)
  [[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || return $(error "Unsupported version \"$version\" in [$section] of $file, expected major.minor.patch")

  printf "%s" "$version"
  return 0
} # 2}}}

# update_and_stage_path_dependencies bumps the version requirements of the path dependencies (the workspace's own crates)
# e.g.: core = { path = "crates/core", version = "0.4.1" } becomes core = { path = "crates/core", version = "0.5.0" }
# Otherwise, cargo cannot resolve the workspace anymore (0.5.0 does not match ^0.4.1)
# Only inline tables are handled, and only requirements matching the previous version (optionally with ^, =, or ~)
function update_and_stage_path_dependencies() { # {{{2
  local old_version=$1
  local version=$2
  local old_pattern=${old_version//./\\.}
  local file status

  while IFS= read -r file; do
    grep -qE "path[[:space:]]*=.*version[[:space:]]*=[[:space:]]*\"[\^=~]?${old_pattern}\"|version[[:space:]]*=[[:space:]]*\"[\^=~]?${old_pattern}\".*path[[:space:]]*=" "$ROOT_DIR/$file" || continue
    verbose "Updating: path dependencies in $file to ${version}"
    sed -Ei.bak \
      -e "/path[[:space:]]*=/s/(version[[:space:]]*=[[:space:]]*\"[\^=~]?)${old_pattern}\"/\1${version}\"/" \
      "$ROOT_DIR/$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to update $file"); }
    rm -f "$ROOT_DIR/$file.bak"
    git add "$ROOT_DIR/$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage $file"); }
    success "Updated path dependencies in $file"
  done < <(list_repository_files Cargo.toml '*/Cargo.toml')
  return 0
} # 2}}}

# update_and_stage_cargo_lock refreshes the workspace entries of Cargo.lock, when it is tracked by git
function update_and_stage_cargo_lock() { # {{{2
  local cargo_toml=$1
  local lock status

  lock=$(find_cargo_lock "$cargo_toml")
  if [[ -z $lock ]]; then
    trace "No Cargo.lock found, skipping"
    return 0
  fi
  if ! git ls-files --error-unmatch -- "$lock" &>/dev/null; then
    trace "Cargo.lock is not tracked by git, skipping"
    return 0
  fi
  if ! command -v cargo &>/dev/null; then
    warn "cargo is not installed, Cargo.lock was not updated, run: cargo update --workspace"
    return 0
  fi

  verbose "Updating: Cargo.lock"
  # --workspace only updates the entries of the workspace members, the dependencies stay untouched
  # Try offline first, as the registry index is usually cached already
  (cd "$(dirname "$lock")" && { cargo update --workspace --offline --quiet 2>/dev/null || cargo update --workspace --quiet; })
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to update Cargo.lock"); }
  git add "$lock"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage Cargo.lock"); }
  success "Updated Cargo.lock"
  return 0
} # 2}}}

function update_and_stage_version_file() { # {{{2
  local file=$1
  local version=$2
  local section old_version updated status

  section=$(get_cargo_version_section "$file") || return 1
  old_version=$(get_cargo_value "$file" "$section" version)

  verbose "Updating: ${file##*/} [$section] to ${version}"
  updated=$(mktemp)
  awk -v section="$section" -v version="$version" '
    /^[[:space:]]*\[/ {
      line = $0
      sub(/#.*/, "", line)
      gsub(/[[:space:]]/, "", line)
      in_section = (line == "[" section "]")
    }
    in_section && !done && /^[[:space:]]*version[[:space:]]*=[[:space:]]*"/ {
      sub(/"[^"]*"/, "\"" version "\"")
      done = 1
    }
    { print }
  ' "$file" > "$updated"
  status=$? ; (( status )) && { rm -f "$updated"; (exit $status); return $(error "Failed to update ${file##*/}"); }
  # Overwrite the content only, so the file keeps its permissions
  cat "$updated" > "$file" && rm -f "$updated"
  git add "$file"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage ${file##*/}"); }
  success "Updated ${file##*/}"

  update_and_stage_path_dependencies "$old_version" "$version" || return 1
  update_and_stage_cargo_lock "$file" || return 1

  # Update and stage the package.json file as well in case the repository contains a web client
  update_and_stage_package_json "$version"
} # 2}}}

# get_rust_edition prints the edition of the crate the given file belongs to (default: 2021)
function get_rust_edition() { # {{{2
  local dir=$(dirname "$ROOT_DIR/$1")
  local edition

  while [[ $dir != / ]]; do
    if [[ -f $dir/Cargo.toml ]]; then
      edition=$(get_cargo_value "$dir/Cargo.toml" package edition)
      [[ -z $edition ]] && edition=$(get_cargo_value "$dir/Cargo.toml" workspace.package edition)
      [[ -n $edition ]] && { printf "%s" "$edition"; return 0; }
    fi
    [[ $dir == "$ROOT_DIR" ]] && break
    dir=$(dirname "$dir")
  done
  printf "2021"
} # 2}}}

# rustfmt_stdin formats Rust code from stdin
# Code is given through stdin so rustfmt does not also format the child modules (mod xxx;) of the file,
# rustfmt is run from the file folder so it finds the rustfmt.toml of the project
function rustfmt_stdin() { # {{{2
  local file=$1
  (cd "$(dirname "$ROOT_DIR/$file")" && rustfmt --edition "$(get_rust_edition "$file")" --emit stdout)
} # 2}}}

function prettify_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR -- '*.rs') )
  (( ${#files[@]} )) || return 0
  local file output mode blob formatted stop_processing=0

  if ! command -v rustfmt &>/dev/null; then
    warn "rustfmt is not installed, skipping"
    return 0
  fi

  for file in "${files[@]}"; do
    formatted=$(mktemp)
    output=$(git show ":$file" | rustfmt_stdin "$file" 2>&1 > "$formatted")
    if (( $? )); then
      error "$file is not formatted properly: $output"
      stop_processing=1
    elif git diff --quiet -- "$file"; then
      # The file is fully staged: format the working copy and stage it
      cat "$formatted" > "$ROOT_DIR/$file"
      git add "$file"
    else
      # The file is partially staged: format the staged content only, so the unstaged changes stay out of the commit
      mode=$(git ls-files --stage -- "$file" | cut -d' ' -f1)
      blob=$(git hash-object -w "$formatted")
      git update-index --cacheinfo "$mode,$blob,$file"
      # Also format the working copy, so it does not show the formatting as unstaged changes; ignore errors from unfinished code
      if rustfmt_stdin "$file" < "$ROOT_DIR/$file" > "$formatted" 2>/dev/null; then
        cat "$formatted" > "$ROOT_DIR/$file"
      fi
    fi
    rm -f "$formatted"
  done
  (( stop_processing )) && return $(error "rustfmt could not format some files")
  success "The rustfmt tool formatted the files successfully"
  return 0
} # 2}}}

# lint_staged_files runs clippy on the workspace when Rust files are staged
# clippy builds the whole workspace, which is slow, so it is turned off by default (gitflow.use-clippy)
function lint_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR -- '*.rs') )
  local cargo_toml status
  (( ${#files[@]} )) || return 0

  if ! get_config_bool gitflow.use-clippy false; then
    verbose "clippy is turned off (gitflow.use-clippy), skipping"
    return 0
  fi
  if ! cargo clippy --version &>/dev/null; then
    warn "clippy is not installed, skipping"
    return 0
  fi

  cargo_toml=$(list_repository_files Cargo.toml '*/Cargo.toml' | head -n 1)
  [[ -n $cargo_toml ]] || return $(error "Failed to find a Cargo.toml in $ROOT_DIR")

  verbose "Running clippy on the workspace of $cargo_toml"
  # Note: clippy checks the working copy, not only the staged content
  (cd "$(dirname "$ROOT_DIR/$cargo_toml")" && cargo clippy --workspace --all-targets --quiet -- -D warnings)
  status=$? ; (( status )) && { (exit $status); return $(error "The clippy tool found issues"); }
  success "The clippy tool found no issues"
  return 0
} # 2}}}
