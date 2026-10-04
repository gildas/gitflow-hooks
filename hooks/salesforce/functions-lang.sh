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


# find_project_dir prints the closest folder containing a sfdx-project.json for the given file
function find_project_dir() { # {{{2
  local dir=$(dirname "$ROOT_DIR/$1")

  while [[ $dir != / && ! -f $dir/sfdx-project.json ]]; do dir=$(dirname "$dir"); done
  printf "%s\n" "$dir"
} # 2}}}

# lint_staged_files runs the project's eslint on the staged LWC/Aura JavaScript files
function lint_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR -- '*.js') )
  (( ${#files[@]} )) || return 0
  local dir=$(find_project_dir "${files[0]}")
  local eslint="$dir/node_modules/.bin/eslint"
  if [[ ! -x $eslint ]]; then
    warn "eslint is not installed in the Salesforce project, skipping"
    return 0
  fi
  (cd "$dir" && "$eslint" "${files[@]/#/$ROOT_DIR/}")
  (( $? )) && ERROR="The eslint tool found issues" && return 1
  return 0
} # 2}}}

# prettify_staged_files formats the staged files with the project's prettier (and its Apex plugin), if any
function prettify_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR) )
  (( ${#files[@]} )) || return 0
  local dir=$(find_project_dir "${files[0]}")
  local prettier="$dir/node_modules/.bin/prettier"

  if [[ ! -x $prettier ]]; then
    verbose "prettier is not installed in the Salesforce project, skipping"
    return 0
  fi
  (cd "$dir" && "$prettier" --write --ignore-unknown --log-level warn "${files[@]/#/$ROOT_DIR/}")
  (( $? )) && ERROR="The prettier tool could not format some files" && return 1
  git add "${files[@]}"
  return 0
} # 2}}}
