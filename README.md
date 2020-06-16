# Git Flow hooks for GENESYS Widget Extensions

This repository contains git hooks for git flow to help deploy releases and hotfixes in my go repositories.

## Pre-Requisites

The hooks from this repository will work only with [git flow AVH Edition](https://github.com/petervanderdoes/gitflow-avh). The basic git-flow does not handle git hooks. Make sure to [install](https://github.com/petervanderdoes/gitflow-avh/wiki/Installation) the proper version!

The version of the target repository is assumed to follow the [semver](https://semver.org) specifications.

## Installation

First, you should `git clone` this project.

Then, from its folder, you just run the deployment script, pointing it at the target repository:  
```console
./hook-it /path/to/repo
```  
On Windows:
```posh
.\hook-it.ps1 -Path /path/to/repo
```

The script will check if the repository is valid and has git-flow already, if not it complains.

## Configuration

By default, the hooks will prevent you from:
- committing anything to the master branch
- committing anything that has unresolved merge conflicts

In case you do not want either of these features, you can turn them off with:
```console
git config --bool gitflow.branch.allow-master-commit true
git config --bool gitflow.branch.allow-conflict-commit true
```

You can also change the _prefix_ used to tag the new release/hotfix (default is none):
```console
git config gitflow.prefix.versiontag v
```

## Usage

Now, everything can be done in the target repository folder.

Starting a new release can be done simply:
```console
git flow release start
```

The hooks will bump automatically the version in the code and the README.md, provided that:
- in the code the version is a line like this:  
  ```js
  var version = '1.2.3'
  ```  
  It does not matter which file contains the version, as long as there is only one.
- in the README, the _download badge_ and code references to `id="my-extension"` look like this:
   ```markdown
   [![Download](https://path/to/badge?version=1.2.3)](https://path/to/software/1.2.3/whatever)
   ```
   ```html
   <html>
     <script id="my-extension" src="https://path/to/software/1.2.3/stuff.js"></script>
     <script id="my-extension" src="https://path/to/software/stuff-1.2.3.js"></script>
   </html>
   ```

When the release is ready, simply _finish_ it:
```console
git flow release finish
```

`Releases` will bump the _minor_ component of the [semver](https://semver.org) version, by default.

`Hotfixes` work the very same way, although they modify the last number of the [semver](https://semver.org) version (i.e. the patch):
```console
git flow hotfix start
# ... work, work
git flow hotfix finish
```

Both releases and hotfixes allow overwriting the default version bump by providing a _version_ to the start command:
- `major`, `minor`, `patch` will bump the corresponding component of the [semver](https://semver.org) version,
- a [semver](https://semver.org) version.

Examples:
```console
git flow release start 12.3.4
```
```console
git flow release start major
```

You do not need to repeat the version when finishing the release/hotfix.

## Hooks Update

Whenever there is an update to this repository, simply re-run the `hook-it` script to update the target repositories.

## TODO

I would love to be able to find a way to run "git flow init" from the script (with my own preferences) when it finds out there is only git in the target repository.

The hooks should log their work and maybe display some nicer progress.

Maybe having some in-repository code that would allow the hooks to update to the current version of this repository.

## Acknowledgments

Thanks to [Peter van der Does](https://github.com/petervanderdoes) and [Jasper N. Brouwer](https://github.com/jaspernbrouwer) for their git flow hooks examples (resp. [petervanderdoes/gitflow-avh](https://github.com/petervanderdoes/gitflow-avh), [jaspernbrouwer/git-flow-hooks](https://github.com/jaspernbrouwer/git-flow-hooks)) that inspired me.

Of course, we wouldn't have any git flow without [Vincent Driessen](https://nvie.com/about) and his inspiring blog post [A successful Git branching model](https://nvie.com/posts/a-successful-git-branching-model) about 10 years ago...
