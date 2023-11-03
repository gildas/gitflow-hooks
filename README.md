# Git Flow hooks

This repository contains git hooks for git flow to help deploy releases and hotfixes in my go, nodejs repositories.

Here are some sample repositories for [GitHub](https://github.com), [BitBucket](https://bitbucket.org), and [GitLab](https://gitlab.com):

- [gitflow-pr-sandbox on GitHub](https://github.com/gildas/gitflow-pr-sandbox),
- [gitflow-pr-sandbox on BitBucket](https://bitbucket.org/gildas_cherruel/gitflow-pr-sandbox),
- [gitflow-pr-sandbox on GitLab](https://gitlab.com/gildas_cherruel/gitflow-pr-sandbox),

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

The Bash script supports the `-v` switch to display more information and the `-n` switch to see what would be executed. Check the script's help with `./hook-it -h`.

The PowerShell script support the `-Verbose` switch to display more information and the `-WhatIf` switch to see what would be executed. Check the script's help with `Get-Help .\hook-it.ps1`.

The script will check if the repository is valid and has git-flow already, if not it will try to initialize it in the repository.

The script also checks if your installed git-flow is the AVH edition, and stops if it is not the case.

## Configuration

By default, the hooks will prevent you from:
- committing anything to the master branch
- committing anything that has unresolved merge conflicts
- force Pull Request usage

In case you do not want either of these features, you can turn them off with:
```bash
git config --bool gitflow.allow-master-commit true
git config --bool gitflow.allow-conflict-commit true
git config --bool gitflow.use-pull-request false
```

You can also change the _prefix_ used to tag the new release/hotfix (default is "v"):
```bash
git config gitflow.prefix.versiontag v
```

When using Pull Requests, if the origin is on [GitHub](https://github.com), the scripts will rely on the [Github's CLI (gh)](https://cli.github.com) and will fail if the tool is not present. If the origin is on [BitBucket](https://bitbucket.org), you must create a [repository access token](https://support.atlassian.com/bitbucket-cloud/docs/create-a-repository-access-token/) and store this access token in the git config:

```sh
git config bitbucket.api.access-token xxxxyyyy
```

If the origin is on [GitLab](https://gitlab.com/about), the [GitLab CLI](https://gitlab.com/gitlab-org/cli) must be installed.

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

## Hooks Update

Whenever there is an update to this repository, simply re-run the `hook-it` script to update the target repositories.

## TODO

The hooks should log their work and maybe display some nicer progress.

Maybe having some in-repository code that would allow the hooks to update to the current version of this repository.

## Acknowledgments

Thanks to [Peter van der Does](https://github.com/petervanderdoes) and [Jasper N. Brouwer](https://github.com/jaspernbrouwer) for their git flow hooks examples (resp. [petervanderdoes/gitflow-avh](https://github.com/petervanderdoes/gitflow-avh), [jaspernbrouwer/git-flow-hooks](https://github.com/jaspernbrouwer/git-flow-hooks)) that inspired me.

Of course, we wouldn't have any git flow without [Vincent Driessen](https://nvie.com/about) and his inspiring blog post [A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model) about 10 years ago...
