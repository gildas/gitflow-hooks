# Git Flow hooks

This repository contains git hooks for git flow to help deploy releases and hotfixes in my Go, Rust, Node.js, and Salesforce repositories.

Here are some sample repositories for [GitHub](https://github.com), [BitBucket](https://bitbucket.org), and [GitLab](https://gitlab.com):

- [gitflow-pr-sandbox on GitHub](https://github.com/gildas/gitflow-pr-sandbox),
- [gitflow-pr-sandbox on BitBucket](https://bitbucket.org/gildas_cherruel/gitflow-pr-sandbox),
- [gitflow-pr-sandbox on GitLab](https://gitlab.com/gildas_cherruel/gitflow-pr-sandbox),

## Pre-Requisites

The hooks from this repository work with [git-flow-next](https://git-flow.sh) (`brew install git-flow-next` on macOS) or [git flow AVH Edition](https://github.com/petervanderdoes/gitflow-avh), which is not maintained anymore. The original git-flow does not handle git hooks. Make sure to install one of these!

The version of the target repository is assumed to follow the [semver](https://semver.org) specifications.

## Installation

### Linux

You can grab the latest binary package on the [Downloads](https://github.com/gildas/gitflow-hooks/releases) pages.

On Debian/Ubuntu distributions, you can use my package repository. First download the signing key:

```bash
curl -fsSL https://gildas.github.io/apt/gildas-archive-keyring.gpg | \
  sudo tee /usr/share/keyrings/gildas-archive-keyring.gpg >/dev/null
```

Add this source:

```bash
echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/gildas-archive-keyring.gpg] https://gildas.github.io/apt stable main" | sudo tee /etc/apt/sources.list.d/gildas.list
sudo apt update
```

Then install `gitflow-hooks` with:

```bash
sudo apt install gitflow-hooks
```

If you use [Homebrew](https://brew.sh), you can install `gitflow-hooks` with:

```bash
brew install gildas/tap/gitflow-hooks
```

### macOS

You can get `gitflow-hooks` from [Homebrew](https://brew.sh) with:

```bash
brew install gildas/tap/gitflow-hooks
```

You can also download the archive for your platform from the [releases](https://github.com/gildas/gitflow-hooks/releases) page and install it manually.

### Windows

You can install `gitflow-hooks` with [scoop](https://scoop.sh):

```bash
scoop bucket add gildas https://github.com/gildas/scoop-bucket
scoop install gitflow-hooks
```

You can also download the archive for your platform from the [releases](https://github.com/gildas/gitflow-hooks/releases) page and install it manually.

### Source code

You can also build and install the `hook-it` application with [cargo](https://doc.rust-lang.org/cargo/) from this project's folder:

```bash
make install
```

which runs `cargo install --path .`. Run `make help` to see the other recipes (`build`, `test`, `lint`, `fmt`, ...). `make lint` checks the Rust code with clippy, and the syntax of the hooks (plus [shellcheck](https://www.shellcheck.net), if installed).

## Usage

The hooks are embedded in the binary, so `hook-it` is the only file to ship to users, and it runs from anywhere (Linux, macOS, and Windows). Point it at the target repository:

```bash
hook-it /path/to/repo
```

Use `-v` to display more information and `--noop` (or `--dry-run`) to see what would be done without modifying anything. Check all the options with `hook-it --help`.

`hook-it` checks that the repository is valid and has git-flow already; if not, it tries to initialize git-flow in the repository. With git-flow-next, it uses the branch names from `gitflow.branch.master` and `gitflow.branch.develop` if they are set anywhere in your git config (e.g., `git config --global gitflow.branch.develop dev`), instead of git-flow-next's defaults (`main` and `develop`).

You can also choose the branches on the command line, which takes precedence over the git config:

```bash
hook-it --main master --develop dev /path/to/repo
```

(`--master` and `--dev` work as well.) The main branch must already exist, locally or on `origin` (unless the repository has no branch at all), so a typo does not create a new production branch; the develop branch is created from the main branch if needed. If git-flow ends up using other branches than the requested ones, `hook-it` stops with an error.

These flags are only used when `hook-it` initializes git-flow. If the repository already uses git-flow with other branches, `hook-it` leaves them alone and displays a warning; run `git flow init -f` in the repository to change them.

It also checks that your installed git-flow is git-flow-next or the AVH edition, and stops if it is not the case.

By default, `hook-it` looks for the kind of language used in the repository (Go, Rust, Salesforce, or Node.js) and copies the appropriate hooks. It searches in the root of the repository, then in the `src/`, `backend/`, and `src/backend/` folders.

You can also tell `hook-it` where to look for the code with (it can be repeated):

```bash
hook-it --src source_folder /path/to/repo
```

To inject the hooks in all the repositories found in a folder, use `--recursive`, optionally with `--exclude` regular expressions:

```bash
hook-it --recursive --exclude archive ~/Projects
```

While editing the hooks, `--hooks-dir hooks` copies them from that folder instead of the embedded ones. Run `make install` again to embed the new versions.

## Configuration

By default, the hooks will prevent you from:

- committing anything to the master branch
- committing anything that has unresolved merge conflicts
- committing code that is not linted ([Go](https://go.dev) with [golangci-lint](https://golangci-lint.run) and [staticcheck](https://staticcheck.io), [Node.js](https://nodejs.org) and [Salesforce](https://developer.salesforce.com) LWC/Aura with the project's [ESLint](https://eslint.org), [Rust](https://www.rust-lang.org) with [Clippy](https://doc.rust-lang.org/clippy) when turned on, see [Rust](#rust)). Missing linters are skipped with a warning.
- force Pull Request usage

In case you do not want either of these features, you can turn them off with:

```bash
git config --bool gitflow.allow-master-commit true
git config --bool gitflow.allow-conflict-commit true
git config --bool gitflow.must-pass-lint false
git config --bool gitflow.use-pull-request false
```

The hooks will also:

- format the code with [gofmt](https://pkg.go.dev/cmd/gofmt) for [Go](https://go.dev) changes, with [rustfmt](https://github.com/rust-lang/rustfmt) for [Rust](https://www.rust-lang.org) changes (skipped if rustfmt is not installed), and with the project's [Prettier](https://prettier.io) for [Node.js](https://nodejs.org) and [Salesforce](https://developer.salesforce.com) changes (skipped if Prettier is not installed)

Similarly, you can turn off the formatting feature with:

```bash
git config --bool gitflow.prettify false
```

You can also change the _prefix_ used to tag the new release/hotfix (default is "v"):

```bash
git config gitflow.prefix.versiontag v
```

When using Pull Requests, if the origin is on [GitHub](https://github.com), the scripts will rely on the [Github's CLI (gh)](https://cli.github.com) and will fail if the tool is not present.

If the origin is on [BitBucket](https://bitbucket.org), the scripts will rely on the [Bitbucket's CLI (bb)](https://bitbucket.org/gildas_cherruel/bb) and will fail if the tool is not present. You can configure which Bitbucket profile is used in your git config (`git config bitbucket.cli.profile myprofile`)

If the origin is on [GitLab](https://gitlab.com), the scripts will reply on the [GitLab's CLI (glab)](https://gitlab.com/gitlab-org/cli) and will fail if the tool is not present.

The scripts will also bump the Helm Chart version if it is present. You can configure the location of the chart with:  

```bash
git config gitflow.path.chart path/to/chart
```

The default location is: `chart/`

You can turn off the chart feature with:

```bash
git config --bool gitflow.bump-chart false
```

The scripts will also update the [OCI annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md) (`version` and `created`) in the Dockerfile if present.

You can turn off the Dockerfile feature with:

```bash
git config --bool gitflow.bump-dockerfile false
```

You can also change the default name and location of the Dockerfile:

```bash
git config gitflow.path.dockerfile path/to/Dockerfile
```

The scripts will also bump the [Appveyor](https://www.appveyor.com) version if it is present.

You can turn off the Appveyor feature with:

```bash
git config --bool gitflow.bump-appveyor false
```

### Version file

By default, the scripts look for the file carrying the version of the repository:

- Go: the Go file that contains a line like `var VERSION = "1.2.3"`. It can be in a subfolder (e.g., `src/backend/version.go`); the shallowest match wins;
- Rust: the shallowest `Cargo.toml`, which is the workspace root in a workspace (see [Rust](#rust));
- Node.js: `package.json`;
- Salesforce: `sfdx-project.json`.

You can point the scripts to another file with:

```bash
git config gitflow.path.versionfile path/to/version/file
```

The path is relative to the root of the repository. If the file cannot be found, starting a release or a hotfix fails.

In Go and Rust repositories, the scripts also bump the `package.json` of an embedded web client, if any (e.g., `src/frontend/package.json`); the shallowest one wins. You can point the scripts to another one with:

```bash
git config gitflow.path.packagejson path/to/package.json
```

When searching, the scripts only consider the files known to git (tracked, or new and not ignored), and they skip hidden folders (e.g., `.local/`), `vendor/`, and `node_modules/`.

### Rust

In a single crate, the version is read from the `[package]` section of `Cargo.toml`.

In a [workspace](https://doc.rust-lang.org/cargo/reference/workspaces.html), the version is read from the `[workspace.package]` section of the root `Cargo.toml`, and the members inherit it with `version.workspace = true`:

```toml
[workspace.package]
version = "1.2.3"
```

If the members of the workspace carry their own versions instead, point the scripts to the `Cargo.toml` of the member that carries the version of the repository:

```bash
git config gitflow.path.versionfile crates/app/Cargo.toml
```

When bumping the version, the scripts also:

- bump the version requirements of the workspace's own crates, like `core = { path = "crates/core", version = "1.2.3" }`. Otherwise cargo cannot resolve the workspace anymore (e.g., `1.3.0` does not match `^1.2.3` for a `0.x` crate, or after a major bump). Only inline tables whose requirement matches the previous version (optionally with `^`, `=`, or `~`) are updated;
- update `Cargo.lock` with `cargo update --workspace` (offline first), if `Cargo.lock` is tracked by git. Only the entries of the workspace members change, the dependencies stay untouched. If cargo is not installed, the scripts warn you to run the command yourself.

When committing, the scripts format the staged `.rs` files with `rustfmt`, using the edition from `Cargo.toml` and the project's `rustfmt.toml`. Only the staged files are formatted, not the modules they declare; if a file is partially staged, the unstaged changes stay out of the commit.

[Clippy](https://doc.rust-lang.org/clippy) is **turned off by default**: it builds the whole workspace, which can make every commit slow. You can turn it on with:

```bash
git config --bool gitflow.use-clippy true
```

When turned on, the scripts run `cargo clippy --workspace --all-targets -- -D warnings` whenever `.rs` files are staged, and the commit fails if Clippy reports anything. Note that Clippy checks the working copy, including unstaged changes. `gitflow.must-pass-lint false` turns it off as well.

### Supported version bumps

All the bump types (`major`, `minor`, `patch`) are allowed by default. Some repositories do not want some of them; for example, a Salesforce package that does not use patch numbers. You can forbid a bump type with:

```bash
git config --bool gitflow.version-major-supported false
git config --bool gitflow.version-minor-supported false
git config --bool gitflow.version-patch-supported false
```

Starting a release or a hotfix with a forbidden bump type (e.g., `git flow hotfix start patch`) then fails. Giving an explicit version number (e.g., `git flow hotfix start 1.2.4`) is always allowed.

The scripts also refuse to bump a version that is not made of exactly 3 components (`major.minor.patch`).

### Tag messages

When finishing a release or a hotfix, you can customize the tag message with:

```bash
git config gitflow.release.finish.message "Release %tag%"
git config gitflow.hotfix.finish.message "Hotfix %tag%"
```

The placeholder is replaced by the version, without its prefix. You can change the placeholder with:

```bash
git config gitflow.message.versiontag "%tag%"
```

With git-flow-next, the custom message is used only when git-flow-next would use its default message (`Tagging version ...`), so a message given with `-m` on the command line is kept.

### Verbosity

By default, the hooks only display their results, warnings, and errors. To see what they are doing, either set the `VERBOSE` environment variable:

```bash
VERBOSE=1 git flow release start minor
```

or turn on verbose output in the repository:

```bash
git config --bool gitflow.verbose true
```

When `gitflow.verbose` is used, the hooks display a warning reminding you that verbose output is on.

With `VERBOSE=2`, the hooks also display tracing information, like the name of each hook as it runs.

## Usage in Target Repository

Once the hooks are initialized, everything can be done in the target repository folder.

Starting a new release can be done simply:

```bash
git flow release start xxx
```

Similarly, starting a hotfix can be done as follows:

```bash
git flow hotfix start xxx
```

Where `xxx` is the new version you are releasing/hotfixing, it is mandatory. If `xxx` is one of `major`, `minor`, `patch`, the scripts will _bump_ the corresponding component of the current version (from the repository code) according to the [semver](https://semver.org) recommandations.

For example, if the current version is `1.2.3`:

- `major` will update the version to 2.0.0
- `minor` will update the version to 1.3.0
- `patch` will update the version to 1.2.4

The scripts will stage and commit the _bumped_ files in a single commit (`Bumped to version x.y.z`).

Depending on the language, the scripts will _bump_ the following files:

- Go:
  - _version.go_ (or any file that contains the line: `var VERSION = "1.2.3"`, even in a subfolder, see [Version file](#version-file));
  - _package.json_ as well, if the repository contains one (for example, a Go backend with an embedded web client in `src/frontend/`).
- Rust:
  - _Cargo.toml_: the version in `[package]`, or in `[workspace.package]` for a workspace, and the version requirements of the workspace's own crates;
  - _Cargo.lock_, if it is tracked by git;
  - _package.json_ as well, if the repository contains one (for an embedded web client).
- Node.js:
  - _package.json_.
- Salesforce:
  - _sfdx-project.json_: the version is read from `versionNumber` (e.g., `"1.2.3.NEXT"`), then both `versionNumber` and `versionName` are updated. If patch bumps are not supported (`gitflow.version-patch-supported` is `false`), the trailing `.0` is removed from `versionName` (e.g., `1.3.0` becomes `1.3`);
  - _package.json_, if present at the root of the repository;
  - the post-install Apex class (_PostInstall.cls_), if present: the line `String PACKAGE_VERSION = '...';`, so the post-install script knows which version is being installed;
  - the loggers, if present, so the version they report matches the package:
    - the Aura logger (_logger.js_): the line `var version = '...';`,
    - the LWC logger (_genforceLogger.js_): the line `version = '...';`.

  The version written in _PostInstall.cls_ and in the loggers follows the same rule as `versionName`.

If you use Pull Requests, you should `publish` the release once to create a Pull Request:

```console
git flow release publish
```

As indicated in the command line result instruction, while merging the Pull Request, the approver should not delete the release branch.

When the release is ready, simply _finish_ it:

```console
git flow release finish
```

**Note:** The `finish` process will fail if there is no Pull Request (asuming you use the Pull Request usage feature) or the current Pull Request has not been properly merged.

Examples:

```console
git flow release start 12.3.4
```

```console
git flow release start major
```

You do not need to repeat the version when finishing the release/hotfix if you are on their branch.

As stated earlier, if the repository has a "chart" folder, the scripts will update the "appVersion" accordingly as well.
They will also bump the chart version according to the same rules used for the application version.

### Features and Bugfixes

Features and bugfixes work the same way, features with `git flow feature ...`, and bugfixes with `git flow bugfix ...`. Both start from the develop branch and are merged back into it:

```console
git flow bugfix start fix-the-thing
```

If you use Pull Requests, `publish` the bugfix to create a Pull Request against the develop branch. Its description lists the commits of the branch:

```console
git flow bugfix publish
```

Once the Pull Request is merged, _finish_ the bugfix:

```console
git flow bugfix finish
```

As with releases and hotfixes, the `finish` process fails if there is no Pull Request or if the Pull Request has not been merged yet. Before finishing, the scripts fetch the develop branch from the origin so the merged Pull Request is included.

## TODO

The hooks should log their work and maybe display some nicer progress.

Maybe having some in-repository code that would allow the hooks to update to the current version of this repository.

## Acknowledgments

Thanks to [Peter van der Does](https://github.com/petervanderdoes) and [Jasper N. Brouwer](https://github.com/jaspernbrouwer) for their git flow hooks examples (resp. [petervanderdoes/gitflow-avh](https://github.com/petervanderdoes/gitflow-avh), [jaspernbrouwer/git-flow-hooks](https://github.com/jaspernbrouwer/git-flow-hooks)) that inspired me.

Of course, we wouldn't have any git flow without [Vincent Driessen](https://nvie.com/about) and his inspiring blog post [A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model) about 10 years ago...
