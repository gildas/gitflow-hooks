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
  sed -Ei.bak "/^[ \t]*\"version\":[ \t]*\"/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
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

# find_package_dir prints the closest folder containing a package.json for the given file
function find_package_dir() { # {{{2
  local dir=$(dirname "$ROOT_DIR/$1")

  while [[ $dir != / && ! -f $dir/package.json ]]; do dir=$(dirname "$dir"); done
  [[ -f $dir/package.json ]] && printf "%s\n" "$dir"
} # 2}}}

# lint_staged_files runs the project's eslint on the staged JavaScript/TypeScript files
function lint_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR -- '*.js' '*.jsx' '*.mjs' '*.cjs' '*.ts' '*.tsx' '*.mts' '*.cts') )
  (( ${#files[@]} )) || return 0
  local projects=( $(for file in "${files[@]}"; do find_package_dir "$file"; done | sort -u) )
  local project file eslint project_files

  for project in "${projects[@]}"; do
    eslint="$project/node_modules/.bin/eslint"
    if [[ ! -x $eslint ]]; then
      warn "eslint is not installed in ${project#$ROOT_DIR/}, skipping"
      continue
    fi
    project_files=()
    for file in "${files[@]}"; do
      [[ $(find_package_dir "$file") == $project ]] && project_files+=( "$ROOT_DIR/$file" )
    done
    (cd "$project" && "$eslint" "${project_files[@]}")
    (( $? )) && ERROR="The eslint tool found issues" && return 1
  done
  return 0
} # 2}}}

# prettify_staged_files formats the staged files with the project's prettier, if any
function prettify_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR) )
  (( ${#files[@]} )) || return 0
  local projects=( $(for file in "${files[@]}"; do find_package_dir "$file"; done | sort -u) )
  local project file prettier project_files

  for project in "${projects[@]}"; do
    prettier="$project/node_modules/.bin/prettier"
    if [[ ! -x $prettier ]]; then
      verbose "prettier is not installed in ${project#$ROOT_DIR/}, skipping"
      continue
    fi
    project_files=()
    for file in "${files[@]}"; do
      [[ $(find_package_dir "$file") == $project ]] && project_files+=( "$ROOT_DIR/$file" )
    done
    (cd "$project" && "$prettier" --write --ignore-unknown --log-level warn "${project_files[@]}")
    (( $? )) && ERROR="The prettier tool could not format some files" && return 1
    git add "${project_files[@]}"
  done
  return 0
} # 2}}}
