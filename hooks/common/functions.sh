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

CHECK=$(printf ${BOLD}${GREEN}'✅'${DEFAULT})
CROSS=$(printf ${BOLD}${RED}'❌'${DEFAULT})

ROOT_DIR=$(git rev-parse --show-toplevel)

function color()        { echo -e "\e38;5;$0m"; }
function title()        { local title="$@" ; local len=$((114 - ${#title})) ; local s=$(printf '𝄙%.0s' $(seq 1 $len)) ;  echo -e "\033[34;1m▶\033[0m \0033[1m$title $s\033[0m" >&2; }
function subtitle()     { echo -e "\033[34;1m▶\033[0m \0033[1m$@\033[0m" >&2; }
function success()      { echo -e "${GREEN}${CHECK} $@${OFF}" >&2; }
function failure()      { echo -e "${RED}${CROSS} $@${OFF}" >&2; }
function success()      { echo -e "${CHECK} $@" >&2 ; }
function trace()        { (( VERBOSE > 1 )) && echo -e "${CYAN}$@${DEFAULT}" >&2; }
function verbose()      { (( VERBOSE > 0 )) && echo -e "$@" >&2; }
function warn()         { echo -e "${YELLOW}Warning: $@${DEFAULT}" >&2; }
function error()        { local status=$? ; echo -e "${CROSS} ${RED}Error: $@${DEFAULT}" >&2; (( status )) && return $status || return 1; }
function die()          { error "${1:-Unknown Error}, Error: ${2:-1}" ; exit ${2:-1} ; }
function die_on_error() { local status=$? ; (( status )) && die "$@" $status; }

# Remove the version prefix, if any
function normalize_version() { # {{{2
  local version=$1
  local version_tag=$(get_version_tag)

  [[ -n $version_tag ]] && printf "%s" ${version##*$version_tag} || printf "%s" $version
} # 2}}}

# bump_version bumps the given version by the given bump
#
# bump can be one of major, minor, patch
function bump_version() { # {{{2
  local version=$1
  local what=$2
  local components=( $(echo $version | tr "."  " ") )

  (( ${#components[@]} != 3 )) && return $(error "Invalid version: $version")
  case $what in
    major)
      if ! get_config_bool gitflow.version-major-supported true ; then
        error "This repository does not support major bumps"
        return 1
      fi
      printf "%s.0.0" $((components[0] + 1))
      ;;
    minor)
      if ! get_config_bool gitflow.version-minor-supported true ; then
        error "This repository does not support minor bumps"
        return 1
      fi
      printf "%s.%s.0" ${components[0]} $((components[1] + 1))
      ;;
    patch)
      if ! get_config_bool gitflow.version-patch-supported true ; then
        error "This repository does not support patch bumps"
        return 1
      fi
      printf "%s.%s.%s" ${components[0]} ${components[1]} $((components[2] + 1))
      ;;
    *)
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

# Tells if the path is absolute, including Windows paths with a drive letter (e.g.: C:/hooks with Git for Windows)
function is_absolute_path() { # {{{2
  [[ $1 == /* || $1 =~ ^[A-Za-z]:[/\\] ]]
} # 2}}}

# run_custom_hook runs the user's custom hook of the given name, if any, after ours. The first found wins:
# - gitflow.path.<hook> (relative to the repository root),
# - <hook> in gitflow.path.custom-hooks, the hooks folder (e.g.: .githooks) used before hook-it took over core.hooksPath,
# - <hook>.local in the hooks folder
#
# The custom hook replaces the current process (its exit code and output become the hook's),
# the function returns only when there is no custom hook to run
#
# Usage: run_custom_hook <hook> [arguments...]
function run_custom_hook() { # {{{2
  local hook=$1
  local custom_hook custom_dir hint
  shift
  [[ -z $hook ]] && die "run_custom_hook: missing hook name"
  custom_hook=$(git config --type=path --get "gitflow.path.$hook")
  custom_dir=$(git config --type=path --get gitflow.path.custom-hooks)
  [[ -n $custom_dir ]] && ! is_absolute_path "$custom_dir" && custom_dir="$ROOT_DIR/$custom_dir"
  if [[ -n $custom_hook ]]; then
    is_absolute_path "$custom_hook" || custom_hook="$ROOT_DIR/$custom_hook"
    [[ -e $custom_hook ]] || die "The custom $hook hook $custom_hook (gitflow.path.$hook) does not exist"
  elif [[ -n $custom_dir && -e $custom_dir/$hook ]]; then
    custom_hook="$custom_dir/$hook"
    if [[ ! -x $custom_hook ]]; then
      # Like git, ignore the hooks that are not executable
      warn "The custom $hook hook $custom_hook was ignored because it is not executable"
      return 0
    fi
  else
    custom_hook="$HOOKS_DIR/$hook.local"
    [[ -e $custom_hook ]] || return 0
    if [[ ! -x $custom_hook ]]; then
      # Like git, ignore the hooks that are not executable (e.g.: a disabled pre-commit hook saved by hook-it)
      warn "The custom $hook hook $custom_hook was ignored because it is not executable"
      return 0
    fi
  fi
  [[ -x $custom_hook ]] || die "The custom $hook hook $custom_hook is not executable, run: chmod +x $custom_hook"
  # The custom hook cannot be a git flow hook (this one, through a symlink, or a copy), running it would loop forever
  if [[ $custom_hook -ef $0 ]] || grep -Fq 'source "$HOOKS_DIR"/functions.sh' "$custom_hook" 2>/dev/null; then
    [[ $hook == pre-commit ]] && hint=", where hook-it saves the pre-commit hook it replaces"
    die "The custom $hook hook $custom_hook is a git flow hook, running it would loop. Point gitflow.path.$hook to your own hook (e.g.: $HOOKS_DIR/$hook.local$hint), or remove it"
  fi
  verbose "Running the custom $hook hook $custom_hook"
  exec "$custom_hook" "$@"
} # 2}}}

# is_git_flow_next tells if the git flow in use is git-flow-next (and not git flow AVH)
function is_git_flow_next() { # {{{2
  if [[ -z $GIT_FLOW_FLAVOR ]]; then
    [[ $(git flow version 2>/dev/null) == *git-flow-next* ]] && GIT_FLOW_FLAVOR=next || GIT_FLOW_FLAVOR=avh
  fi
  [[ $GIT_FLOW_FLAVOR == next ]]
} # 2}}}

# has_git_flow_next_config tells if the repository is configured by git-flow-next (gitflow.branch.<name>.type keys)
#
# Its configuration wins over the git flow AVH one, which can come from the global git config
function has_git_flow_next_config() { # {{{2
  git config --get-regexp '^gitflow\.branch\..*\.type$' &>/dev/null
} # 2}}}

# get_master_branch prints the production branch
#
# git flow AVH stores it in gitflow.branch.master,
# git-flow-next stores it as the base branch without a parent (gitflow.branch.<name>.type = base)
function get_master_branch() { # {{{2
  local key name

  if ! has_git_flow_next_config; then
    git config --get gitflow.branch.master
    return 0
  fi
  for key in $(git config --get-regexp '^gitflow\.branch\..*\.type$' | awk '$2 == "base" {print $1}'); do
    name=${key#gitflow.branch.}
    name=${name%.type}
    if [[ -z $(git config --get "gitflow.branch.$name.parent") ]]; then
      printf "%s" "$name"
      return 0
    fi
  done
} # 2}}}

# get_develop_branch prints the development branch
#
# git flow AVH stores it in gitflow.branch.develop,
# git-flow-next stores it as the parent of the feature branches
function get_develop_branch() { # {{{2
  if has_git_flow_next_config; then
    git config --get gitflow.branch.feature.parent
  else
    git config --get gitflow.branch.develop
  fi
} # 2}}}

# get_branch_worktree prints the worktree where the given branch is checked out (empty when it is not)
function get_branch_worktree() { # {{{2
  local branch=$1
  git worktree list --porcelain | awk -v ref="refs/heads/$branch" '
    /^worktree / { worktree = substr($0, 10) }
    $1 == "branch" && $2 == ref { print worktree; exit }
  '
} # 2}}}

# pull_branch fast-forwards the given local branch to its remote, so git flow merges into an up-to-date branch
#
# Works whether the branch is checked out (in this worktree or another one) or not.
# A local branch that is ahead of its remote is left alone, a diverged one is an error.
# Nothing happens when there is no remote, or when the remote does not have the branch.
function pull_branch() { # {{{2
  local origin=$1
  local branch=$2
  local status local_sha remote_sha worktree

  [[ -z $branch ]] && return 0
  [[ -z $origin ]] && verbose "No remote, not pulling $branch" && return 0

  git ls-remote --exit-code --heads "$origin" "$branch" &>/dev/null
  status=$?
  (( status == 2 )) && verbose "Branch $branch does not exist on $origin, not pulling it" && return 0
  (( status ))      && error "Failed to reach $origin" && return $status

  verbose "Pulling $branch from $origin"
  git fetch --quiet "$origin" "+refs/heads/$branch:refs/remotes/$origin/$branch"
  status=$? ; (( status )) && error "Failed to fetch $branch from $origin" && return $status
  remote_sha=$(git rev-parse --verify --quiet "refs/remotes/$origin/$branch")
  local_sha=$(git rev-parse --verify --quiet "refs/heads/$branch")

  if [[ -z $local_sha ]]; then
    git branch --quiet --track "$branch" "$origin/$branch"
    status=$? ; (( status )) && error "Failed to create $branch from $origin/$branch" && return $status
    verbose "Created $branch from $origin/$branch"
    return 0
  fi
  if git merge-base --is-ancestor "$remote_sha" "$local_sha"; then
    verbose "Branch $branch is up to date with $origin/$branch"
    return 0
  fi
  if ! git merge-base --is-ancestor "$local_sha" "$remote_sha"; then
    error "Branch $branch has diverged from $origin/$branch, please reconcile them first"
    return 1
  fi

  worktree=$(get_branch_worktree "$branch")
  if [[ -n $worktree ]]; then
    # The branch is checked out, its files must follow
    git -C "$worktree" merge --ff-only --quiet "refs/remotes/$origin/$branch"
  else
    git update-ref -m "pull: fast-forward from $origin/$branch" "refs/heads/$branch" "$remote_sha" "$local_sha"
  fi
  status=$? ; (( status )) && error "Failed to fast-forward $branch to $origin/$branch" && return $status
  verbose "Fast-forwarded $branch to $origin/$branch"
  return 0
} # 2}}}

# get_version_tag prints the prefix of the version tags (like v)
#
# git flow AVH stores it in gitflow.prefix.versiontag,
# git-flow-next stores it per branch type (gitflow.branch.release.tagprefix)
function get_version_tag() { # {{{2
  if has_git_flow_next_config; then
    git config --get gitflow.branch.release.tagprefix
  else
    git config --get gitflow.prefix.versiontag
  fi
} # 2}}}

function get_chart_version() { # {{{2
  local status
  local file=$1
  local version=$(grep "^version:" "$file" | sed -E "s/^version:[ ]+([0-9]+\.[0-9]+\.[0-9]+)/\1/")
  status=$? ; (( status )) && { (exit $status); return $(error "Failed to get the version from $file "); }
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

# get_origin_url prints the URL of the given remote, with SSH host aliases (from ~/.ssh/config) resolved
#
# e.g.: git@bitbucket-genesys:genesyscsp/repo.git becomes git@ssh.bitbucket.org:genesyscsp/repo.git
function get_origin_url() { # {{{2
  local origin=$1
  local url host path resolved

  url=$(git config remote.${origin}.url)
  [[ -z $url ]] && return 1
  if [[ $url =~ ^ssh://([^@/]+@)?([^/:]+)(:[0-9]+)?/(.*)$ ]]; then
    host=${BASH_REMATCH[2]}
    path=${BASH_REMATCH[4]}
  elif [[ ! $url =~ ^[a-zA-Z]+:// && $url =~ ^([^@/]+@)?([^/:]+):(.*)$ ]]; then
    host=${BASH_REMATCH[2]}
    path=${BASH_REMATCH[3]}
  else
    printf "%s" "$url"
    return 0
  fi
  command -v ssh &>/dev/null && resolved=$(ssh -G "$host" 2>/dev/null | awk '$1 == "hostname" { print $2; exit }')
  printf "git@%s:%s" "${resolved:-$host}" "$path"
  return 0
} # 2}}}

function get_repo_type() { # {{{2
  local origin=$1
  local origin_url=$(get_origin_url $origin)
  local repo_type

  if [[ $origin_url =~ ^(ssh://)?git@github\.com ]]; then
    repo_type="github"
  elif [[ $origin_url =~ ^https://github\.com ]]; then
    repo_type="github"
  elif [[ $origin_url =~ ^(ssh://)?git@ssh\.bitbucket\.org ]]; then
    repo_type="bitbucket"
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
  local origin_url=$(get_origin_url $origin)
  local status=$? ; (( status )) && return $status
  local repo

  if [[ $origin_url =~ ^(ssh://)?git@github\.com ]]; then
    repo=$(echo $origin_url | sed -E -e 's/^(ssh:\/\/)?git@github\.com://' -e 's/\.git$//')
  elif [[ $origin_url =~ ^https://github\.com ]]; then
    repo=$(echo $origin_url | sed -E -e 's/https:\/\/github\.com\///' -e 's/\.git$//')
  elif [[ $origin_url =~ ^(ssh://)?git@ssh\.bitbucket\.org ]]; then
    repo=$(echo $origin_url | sed -E -e 's/^(ssh:\/\/)?git@ssh\.bitbucket\.org://' -e 's/\.git$//')
  elif [[ $origin_url =~ ^(ssh://)?git@bitbucket\.org ]]; then
    repo=$(echo $origin_url | sed -E -e 's/^(ssh:\/\/)?git@bitbucket\.org://' -e 's/\.git$//')
  elif [[ $origin_url =~ ^https://.*bitbucket\.org ]]; then
    repo=$(echo $origin_url | sed -E -e 's/https:\/\/.*bitbucket\.org\///' -e 's/\.git$//')
  elif [[ $origin_url =~ ^(ssh://)?git@gitlab\.com ]]; then
    repo=$(echo $origin_url | sed -E -e 's/^(ssh:\/\/)?git@gitlab\.com://' -e 's/\.git$//')
  else
    return 1
  fi
  if [[ $repo =~ ^(ssh://)?git@ || $repo =~ ^https:// ]] ; then
    error "Malformed repository name: \"$repo\""
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
  local status repo_type repo
  repo_type=$(get_repo_type $origin)
  status=$? ; (( status )) && error "Unsupported remote URL for $origin: $(git config remote.${origin}.url)" && return $status
  verbose "Creating a Pull Request on a $repo_type repository"
  repo=$(get_repo $origin)
  status=$? ; (( status )) && error "Failed to retrieve the repository name" && return $status
  [[ -z $repo ]] && error "Failed to retrieve repository name (empty)" && return 1

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
        local profile=$(bb profile which --output json | jq --raw-output --exit-status '.name')
        status=$? ; (( status )) && error "Failed to find the current bitbucket profile" && return $status
        [[ -z $profile ]] && error "Failed to find the current bitbucket profile, please add it to your .git/config" && return 1
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
          --description   "$body" \
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
  local status
  local repo_type=$(get_repo_type $origin)
  status=$? ; (( status )) && return $status
  verbose "Getting Pull Request status on a $repo_type repository"
  local repo=$(get_repo $origin)
  status=$? ; (( status )) && error "Failed to retrieve the repository name" && return $status
  [[ -z $repo ]] && error "Failed to retrieve repository name (empty)" && return 1
  local state

  verbose "Getting Pull Request status on repository $repo from $origin on branch $branch"
  case $repo_type in
    github)
      if command -v gh &>/dev/null; then
        state=$(gh pr view $branch --json state --jq .state)
      fi
      ;;
    bitbucket)
      if command -v bb &>/dev/null; then
        local profile=$(bb profile which --output json | jq --raw-output --exit-status '.name')
        status=$? ; (( status )) && error "Failed to find the current bitbucket profile" && return $status
        [[ -z $profile ]] && error "Failed to find the current bitbucket profile, please add it to your .git/config" && return 1
        verbose "Using Bitbucket profile: $profile"
        state=$( \
          bb ${profile:+--profile $profile} pr list --repository "$repo" --state all --output json |\
          jq --raw-output --exit-status --arg branch $branch '
            . |= sort_by(.updated_on) |
            last(.[] | select(.source.branch.name == $branch) | .state)'
        )
        status=$? ; (( status )) && return $status
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

# list_repository_files prints the repository files matching the given pathspecs, shallowest first.
# Only files tracked by git (or new, not ignored, files) are listed,
# and files in hidden folders (.local/, .github/, ...), vendor/, or node_modules/ are skipped.
function list_repository_files() { # {{{2
  git -C "$ROOT_DIR" ls-files --cached --others --exclude-standard -- "$@" \
    | grep -vE '(^|/)(\.[^/]+|vendor|node_modules)/' \
    | awk -F/ '{ print NF "\t" $0 }' \
    | sort -s -n -k1,1 \
    | cut -f2- \
    | uniq
} # 2}}}

# update_and_stage_package_json bumps the package.json of an embedded web client, if any
# (e.g.: a Go or Rust backend with its frontend in src/frontend/)
# Languages with a different package.json logic (e.g.: Salesforce) override it
function update_and_stage_package_json() { # {{{2
  local version=$1
  local file=$(get_config gitflow.path.packagejson "")
  local status

  # Use the shallowest package.json (e.g.: package.json, src/frontend/package.json)
  [[ -z $file ]] && file=$(list_repository_files package.json '*/package.json' | head -n 1)
  [[ -n $file && $file != /* ]] && file="$ROOT_DIR/$file"

  if [[ ! -f $file ]]; then
    trace "No package.json found, skipping"
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

# git flow AVH exports MASTER_BRANCH and DEVELOP_BRANCH to the hooks, git-flow-next does not
[[ -z $MASTER_BRANCH ]]  && MASTER_BRANCH=$(get_master_branch)
[[ -z $DEVELOP_BRANCH ]] && DEVELOP_BRANCH=$(get_develop_branch)

# Set the VERBOSE variable via environment or configuration
if (( ! VERBOSE )); then
  if get_config_bool gitflow.verbose false; then
    warn "gitflow.verbose is set to true, enabling verbose output"
    export VERBOSE=1
  fi
fi
