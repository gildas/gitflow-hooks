#!/usr/bin/env bash

function find_version_file() { # {{{2
  local file=$(get_config gitflow.path.versionfile "sfdx-project.json")

  [[ -f $file ]] || return $(error "Failed to find a file carrying the version in $ROOT_DIR")

  printf "%s" $file
  return 0
} # 2}}}

function get_version() { # {{{2
  local file=$1
  local version=$(grep -E '^[ \t]*"versionNumber":' "$file" | sed -E 's/^[ \t]*"versionNumber":[ \t]*"([0-9]+\.[0-9]+\.[0-9]+)\.NEXT"[ \t]*,$/\1/')
  local status=$? ; (( status )) && { (exit $status); return $(error "Failed to get the version from $file"); }
  
  printf "%s" $version
  return 0
} # 2}}}

function update_and_stage_sfdx_project() { # {{{2
  local file=$1
  local version=$2
  local version_name=$version
  local status

  if ! get_config_bool gitflow.version-patch-supported true ; then
    # This project does not support patch numbers, so we need to remove it from the version name
    version_name=${version_name%.0}
  fi

  verbose "Updating: ${file##*/} to ${version_name}"
  sed -Ei.bak \
    -e "/^[ \t]*\"versionName\":[ \t]*\"/s/[0-9]+\.[0-9]+(\.[0-9]+)?/${version_name}/" \
    -e "/^[ \t]*\"versionNumber\":[ \t]*\"/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" \
    "$file"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to update ${file##*/}"); }
  git add "$file"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage ${file##*/}"); }
  success "Updated ${file##*/}"
  rm -f "$file.bak"
  return 0
} # 2}}}

function update_and_stage_package_json() { # {{{2
  local version=$1
  local file="package.json"
  local status

  if [[ ! -r $file ]]; then
    verbose "No package.json found, skipping"
    return 0
  fi

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei.bak \
    -e "/^[ \t]*\"version\":[ \t]*\"/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" \
    "$file"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to update ${file##*/} "); }
  git add "$file"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage ${file##*/} "); }
  success "Updated ${file##*/}"
  rm -f "$file.bak"
  return 0
} # 2}}}

function update_and_stage_postinstall() { # {{{2
  local version=$1
  local file
  local status

  if ! get_config_bool gitflow.version-patch-supported true ; then
    # This project does not support patch numbers, so we need to remove it from the version name
    version=${version%.0}
  fi

  file=$(find . -type f -name PostInstall.cls -print -quit)
  if [[ -f $file ]]; then
    verbose "Updating: ${file##*/} to ${version}"
    sed -Ei.bak \
      -e "s/String PACKAGE_VERSION = '.*';/String PACKAGE_VERSION = '$version';/" \
      "$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to update ${file##*/} "); }
    git add "$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage ${file##*/} "); }
    success "Updated ${file##*/}"
    rm -f "$file.bak"
  else
    verbose "No PostInstall.cls found, skipping"
  fi

  return 0
} # 2}}}

function update_and_stage_loggers() { # {{{2
  local version=$1
  local file
  local status

  if ! get_config_bool gitflow.version-patch-supported true ; then
    # This project does not support patch numbers, so we need to remove it from the version name
    version=${version%.0}
  fi

  # The AURA logger
  file=$(find . -type f -name logger.js -print -quit)
  if [[ -f $file ]]; then
    verbose "Updating: ${file##*/} to ${version}"
    sed -Ei.bak \
      -e "/[ \t]*var version = '/s/var version = '.*';/var version = '$version';/" \
      "$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to update ${file##*/} "); }
    git add "$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage ${file##*/} "); }
    success "Updated ${file##*/}"
    rm -f "$file.bak"
  else
    verbose "No logger found, skipping"
  fi

  # The LWC logger
  file=$(find . -type f -name genforceLogger.js -print -quit)
  if [[ -f $file ]]; then
    verbose "Updating: ${file##*/} to ${version}"
    sed -Ei.bak \
      -e "s/version = '.*';/version = '$version';/" \
      "$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to update ${file##*/} "); }
    git add "$file"
    status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage ${file##*/} "); }
    success "Updated ${file##*/}"
    rm -f "$file.bak"
  else
    verbose "No logger found, skipping"
  fi

  return 0
} # 2}}}

function update_and_stage_version_file() { # {{{2
  local sfdx_project="$1"
  local version="$2"
  local status

  update_and_stage_sfdx_project "$sfdx_project" "$version"
  status=$? ; (( status )) && return $status

  update_and_stage_package_json "$version"
  status=$? ; (( status )) && return $status

  update_and_stage_postinstall "$version"
  status=$? ; (( status )) && return $status

  update_and_stage_loggers "$version"
  status=$? ; (( status )) && return $status

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
  local status

  if [[ ! -x $eslint ]]; then
    warn "eslint is not installed in the Salesforce project, skipping"
    return 0
  fi
  (cd "$dir" && "$eslint" "${files[@]/#/$ROOT_DIR/}")
  status=$? ; (( status )) && { (exit $status); return $(error "The eslint tool found issues"); }
  success "The eslint tool found no issues"
  return 0
} # 2}}}

# prettify_staged_files formats the staged files with the project's prettier (and its Apex plugin), if any
function prettify_staged_files() { # {{{2
  local files=( $(git diff --cached --name-only --diff-filter=ACMR) )
  (( ${#files[@]} )) || return 0
  local dir=$(find_project_dir "${files[0]}")
  local prettier="$dir/node_modules/.bin/prettier"
  local status

  if [[ ! -x $prettier ]]; then
    verbose "prettier is not installed in the Salesforce project, skipping"
    return 0
  fi
  (cd "$dir" && "$prettier" --write --ignore-unknown --log-level warn "${files[@]/#/$ROOT_DIR/}")
  status=$? ; (( status )) && { (exit $status); return $(error "The prettier tool could not format some files"); }
  git add "${files[@]}"
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to stage the formatted files"); }
  success "The prettier tool formatted the files successfully"
  return 0
} # 2}}}
