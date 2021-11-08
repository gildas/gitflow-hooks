# Git Flow hooks

This repository contains git hooks for git flow to help deploy releases and hotfixes in my go, nodejs repositories.

## Pre-Requisites

The hooks from this repository will work only with [git flow AVH Edition](https://github.com/petervanderdoes/gitflow-avh). The basic git-flow does not handle git hooks. Make sure to [install](https://github.com/petervanderdoes/gitflow-avh/wiki/Installation) the proper version!

The version of the target repository is assumed to follow the [semver](https://semver.org) specifications.

## Installation

First, you should `git clone` this project.

Then, from its folder, you just run the deployment script, pointing it at the target repository:  
```bash
./hook-it /path/to/repo
```  
On Windows:
```posh
.\hook-it.ps1 -Path /path/to/repo
```

The script will check if the repository is valid and has git-flow already, if not it will try to initialize it in the repository.

The script also checks if your installed git-flow is the AVH edition, and stops if it is not the case.

## Configuration

By default, the hooks will prevent you from:
- committing anything to the master branch
- committing anything that has unresolved merge conflicts

In case you do not want either of these features, you can turn them off with:
```bash
git config --bool gitflow.branch.allow-master-commit true
git config --bool gitflow.branch.allow-conflict-commit true
```

You can also change the _prefix_ used to tag the new release/hotfix (default is "v"):
```bash
git config gitflow.prefix.versiontag v
```

The scripts will also bump the Helm Chart version if it is present. You can configure the location of the chart with:  
```bash
git config gitflow.path.chart path/to/chart
```
The default location is: `chart/`

You can turn off the chart feature with:
```bash
git config --bool gitflow.branch.bump-chart false
```

## Usage

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

The scripts will also commit the _bumped_ files.

Depending on the language, the scripts will _bump_ the following files:
- _version.go_ in Go (or any file that contains the line: `var VERSION = "1.2.3"`);
- _package.json_ in Node.js;

When the release is ready, simply _finish_ it:
```console
git flow release finish
```

Examples:
```console
git flow release start 12.3.4
```
```console
git flow release start major
```

You do not need to repeat the version when finishing the release/hotfix.

As stated earlier, if the repository has a "chart" folder, the scripts will update the "appVersion" accordingly as well.
They will also bump the chart version according to the same rules used for the application version.

## Hooks Update

Whenever there is an update to this repository, simply re-run the `hook-it` script to update the target repositories.

## TODO

The hooks should log their work and maybe display some nicer progress.

Maybe having some in-repository code that would allow the hooks to update to the current version of this repository.

## Acknowledgments

Thanks to [Peter van der Does](https://github.com/petervanderdoes) and [Jasper N. Brouwer](https://github.com/jaspernbrouwer) for their git flow hooks examples (resp. [petervanderdoes/gitflow-avh](https://github.com/petervanderdoes/gitflow-avh), [jaspernbrouwer/git-flow-hooks](https://github.com/jaspernbrouwer/git-flow-hooks)) that inspired me.

Of course, we wouldn't have any git flow without [Vincent Driessen](https://nvie.com/about) and his inspiring blog post [A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model) about 10 years ago...
