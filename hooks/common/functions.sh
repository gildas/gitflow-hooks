#!/usr/bin/env bash

BLACK=$(printf '\e[30m')
RED=$(printf '\e[31m')
GREEN=$(printf '\e[32m')
YELLOW=$(printf '\e[33m')
BLUE=$(printf '\e[34m')
MAGENTA=$(printf '\e[35m')
CYAN=$(printf '\e[36m')
WHITE=$(printf '\e[37m')
GREY=$(printf '\e[36m')
DEFAULT=$(printf '\e[m')

BOLD=$(printf '\e[1m')
UNDERLINE=$(printf '\e[4m')
REVERSED=$(printf '\e[7m')

CHECK=$(printf ${BOLD}${GREEN}'✔'${DEFAULT})
CROSS=$(printf ${BOLD}${RED}'✘'${DEFAULT})

ROOT_DIR=$(git rev-parse --show-toplevel)

ERROR=

function color()        { echo -e "\e38;5;$0m"; }
function verbose()      { [[ $VERBOSE > 0 ]] && echo -e "$@" >&2; }
function success()      { echo -e "${CHECK} $@" >&2 ; }
function warn()         { echo -e "${YELLOW}Warning: $@${DEFAULT}" >&2; }
function error()        { echo -e "${CROSS} ${RED}Error: $@${DEFAULT}" >&2; }
function die()          { error "${1:-${ERROR:-Unknown Error}}, Error: ${2:-1}" ; exit ${2:-1} ; }
function die_on_error() { local status=$? ; (( status )) && die "$@" $status; }

# Remove the version prefix, if any
function normalize_version() { # {{{2
  local version=$1
  local version_tag=$(get_config gitflow.prefix.versiontag)

  [[ -n $version_tag ]] && printf "%s" ${version##*$version_tag} || printf "%s" $version
} # 2}}}

# bump_version bumps the given version by the given bump
#
# bump can be one of major, minor, patch
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
      printf "%s.%s.%s" ${components[0]} ${components[1]} $((components[2] + 1))
      ;;
    *)
      ERROR="Unsupported bump type: $what"
      error "Unsupported bump type: $what"
      return 1
  esac
  return 0
} # 2}}}

function is_binary() { # {{{2
  # Thanks to: https://github.com/jaspernbrouwer/git-flow-hooks/blob/6677eb5e45b4d5597de7ac4446e1353e61be9398/modules/functions.sh#L50
  P=$(printf '%s\t-\t' -)
  T=$(git diff --no-index --numstat /dev/null "$1")

  case "$T" in "$P"*) return 0 ;; esac
  return 1
} # 2}}}

function get_config_bool() { # {{{2
  [[ -z $1 ]] && return 1
  local value=$(git config --get --bool $1)
  [[ -z $value ]] && value=${2:-false}
  [[ $value == "true" ]] && return 0 || return 1
} # 2}}}

function get_config() { # {{{2
  local key=$1
  local default=$2

  [[ -z $key ]] && (printf "" ; return 0)
  local value=$(git config --get $key)
  if [[ -n $value ]]; then
    printf "%s" "$value"
  else
    printf "%s" "$default"
  fi
  return 0
} # 2}}}

function get_chart_version() { # {{{2
  local status
  local file=$1
  local version=$(grep "^version:" "$file" | sed -E "s/^version:[ ]+([0-9]+\.[0-9]+\.[0-9]+)/\1/")
  status=$? ; (( status )) && ERROR="Failed to get the version from $file" && return $status
  printf "%s" $version
  return 0
} # 2}}}

function update_chart_version() { # {{{2
  local file=$1
  local version=$2

  verbose "Updating Chart: ${file##*/} to ${version}"
  sed -Ei.bak "/^version:/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
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

function update_chart_appversion() { # {{{2
  local file=$1
  local version=$2
  local status

  verbose "Updating App Version: ${file##*/} to ${version}"
  sed -Ei.bak "/^appVersion:/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" "$file"
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

function update_dockerfile_version() { # {{{2
  local file=$1
  local version=$2
  local now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local status

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei.bak \
    -e "/^LABEL\s+org\.opencontainers\.image\.version/s/[0-9]+\.[0-9]+\.[0-9]+/${version}/" \
    -e "/^LABEL\s+org\.opencontainers\.image\.created/s/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z/$(date -u +%Y-%m-%dT%H:%M:%SZ)/" \
    "$file"
  status=$?
  if (( status )); then
    error "Failed to update ${file##*/}, exit code: $status"
    return $status
  else
    success "Updated ${file##*/}"
    rm -f "$file.bak"
  fi
} # 2}}}

function update_appveyor_version() { # {{{2
  local file=$1
  local version=$2
  local status

  verbose "Updating: ${file##*/} to ${version}"
  sed -Ei.bak \
    -e "/^version:/s/.*/version: ${version}+{build}/" \
    "$file"
  status=$?
  if (( status )); then
    error "Failed to update ${file##*/}, exit code: $status"
    return $status
  else
    success "Updated ${file##*/}"
    rm -f "$file.bak"
  fi
} # 2}}}

function get_repo_type() { # {{{2
  local origin=$1
  local origin_url=$(git config remote.${origin}.url)
  local repo_type

  if [[ $origin_url =~ ^(ssh://)?git@github\.com ]]; then
    repo_type="github"
  elif [[ $origin_url =~ ^https://github\.com ]]; then
    repo_type="github"
  elif [[ $origin_url =~ ^(ssh://)?git@bitbucket\.org ]]; then
    repo_type="bitbucket"
  elif [[ $origin_url =~ ^https://.*bitbucket\.org ]]; then
    repo_type="bitbucket"
  elif [[ $origin_url =~ ^(ssh://)?git@gitlab\.com ]]; then
    repo_type="gitlab"
  else
    return 1
  fi
  printf "%s" $repo_type
  return 0
} # 2}}}

function get_repo() { # {{{2
  local origin=$1
  local origin_url=$(git config remote.${origin}.url)
  local repo

  if [[ $origin_url =~ ^(ssh://)?git@github\.com ]]; then
    repo=$(echo $origin_url | sed -e 's/^(ssh:\/\/)?git@github\.com://' -e 's/\.git$//')
  elif [[ $origin_url =~ ^https://github\.com ]]; then
    repo=$(echo $origin_url | sed -e 's/https:\/\/github\.com\///' -e 's/\.git$//')
  elif [[ $origin_url =~ ^(ssh://)?git@bitbucket\.org ]]; then
    repo=$(echo $origin_url | sed -e 's/^(ssh:\/\/)?git@bitbucket\.org://' -e 's/\.git$//')
  elif [[ $origin_url =~ ^https://.*bitbucket\.org ]]; then
    repo=$(echo $origin_url | sed -e 's/https:\/\/.*bitbucket\.org\///' -e 's/\.git$//')
  elif [[ $origin_url =~ ^(ssh://)?git@gitlab\.com ]]; then
    repo=$(echo $origin_url | sed -e 's/^(ssh:\/\/)?git@gitlab\.com://' -e 's/\.git$//')
  else
    return 1
  fi
  printf "%s" $repo
  return 0
} # 2}}}

function create_pull_request() { #{{{2
  local origin=$1
  local source=$2
  local destination=$3
  local title=$4
  local body=$5
  local repo_type=$(get_repo_type $origin)
  local repo=$(get_repo $origin)

  verbose "Creating a Pull Request on repository $repo from $source to $destination"
  case $repo_type in
    github)
      if command -v gh &>/dev/null; then
        gh pr create \
          --title "$title" \
          --body  "$body" \
          --repo  $repo \
          --base  $destination
        # TODO: use --web optionally so the user can edit the PR?!?
      else
        echo ""
        echo "Create Pull Request at: https://github.com/$repo/compare/$source?expand=1"
        echo "$body. It will be deleted automatically."
        echo ""
      fi
      ;;
    bitbucket)
      if command -v bb &>/dev/null; then
        local profile=$(git config bitbucket.cli.profile)
        bb ${profile:+--profile $profile} pr create \
          --title       "$title" \
          --description "$body" \
          --repository  $repo \
          --source      $source \
          --destination $destination
      else
        echo ""
        echo "Create Pull Request at: https://bitbucket.org/$repo/branches"
        echo "$body. It will be deleted automatically."
        echo ""
      fi
      ;;
    gitlab)
      if command -v glab &> /dev/null; then
        glab mr create \
          --title         "$title" \
          --description   "$description" \
          --source-branch $source \
          --target-branch $destination \
          --yes
      else
        echo ""
        echo "Create Pull Request at: https://gitlab.com/$repo/-/merge_requests/new"
        echo "$body. It will be deleted automatically."
        echo ""
      fi
      ;;
    *)
      echo "Unknown origin type: $repo_type"
      echo "Create a Pull Request manually at $ORIGIN_URL"
      echo "$body. It will be deleted automatically."
      ;;
  esac
} # 2}}}

function get_pull_request_state() { # {{{2
  local origin=$1
  local branch=$2
  local repo_type=$(get_repo_type $origin)
  local repo=$(get_repo $origin)
  local state

  case $repo_type in
    github)
      if command -v gh &>/dev/null; then
        state=$(gh pr view $branch --json state --jq .state)
      fi
      ;;
    bitbucket)
      if command -v bb &>/dev/null; then
        local profile=$(git config bitbucket.cli.profile)
        state=$( \
          bb ${profile:+--profile $profile} pr list --repository $repo --state all --output json |\
          jq -r --arg branch $branch '
            . |= sort_by(.updated_on) |
            last(.[] | select(.source.branch.name == $branch) | .state)'
        )
      fi
      ;;
    gitlab)
      if command -v glab &> /dev/null; then
        state=$(glab mr view $branch | awk '/^state:/{print $2}')
      fi
      ;;
  esac
  printf "%s" $state
  return 0
} # 2}}}

# Set the VERBOSE variable via environment or configuration
if [[ $VERBOSE == 0 ]]; then
  if get_config_bool gitflow.verbose false; then
    VERBOSE=1
  fi
fi
