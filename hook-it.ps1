<#
.SYNOPSIS
  Installs git flow (AVH Edition) hooks to a git repository
.DESCRIPTION
  Installs git flow hooks to a git repository.
  git flow AVH Edition only is suppported.
  The target repository must have "git init" and "git flow init" already executed.
.PARAMETER Path
  The Path to the target repository
.EXAMPLE
  .\hook-it.ps1 -Path /path/to/repo
#>
[CmdletBinding(SupportsShouldProcess=$true)]
Param(
  [string] $Path
)

if (! (Test-Path $Path) ) {
  Write-Error "Folder $Path does not exist"
  exit 1
}
if (! (Test-Path $Path/.git) ) {
  Write-Error "Folder $Path is not a git repository"
  exit 1
}

# 1/ make sure git flow is initialized
if ( ! (git -C $Path config gitflow.branch.master) ) {
  Write-Verbose "Initializing git flow in repository $Path"
  if ($PSCmdlet.ShouldProcess("gitflow", "Initialize")) {
    git -C $Path flow init -d --tag v
    if ( $LASTEXITCODE -ne 0 ) {
      Write-Error "git flow init failed"
      exit 1
    }
  }
}

$hooksPath=git -C $Path config gitflow.path.hooks
if ( ! $hooksPath ) {
  Write-Error "git flow AVH edition is needed for this to work"
  exit 1
}

# 2/ Configure git flow
if ($PSCmdlet.ShouldProcess("gitflow", "Configure Messages")) {
  git -C $Path config gitflow.prefix.versiontag "v"
  if ( $LASTEXITCODE -ne 0 ) {
    Write-Error "git flow Prefix Version Tag configuration failed"
    exit 1
  }
  git -C $Path config gitflow.hotfix.finish.message "Hotfix %tag%"
  if ( $LASTEXITCODE -ne 0 ) {
    Write-Error "git flow Hotfix Finish Message configuration failed"
    exit 1
  }
  git -C $Path config gitflow.release.finish.message "Release %tag%"
  if ( $LASTEXITCODE -ne 0 ) {
    Write-Error "git flow Release Finish Message configuration failed"
    exit 1
  }
  $value = (git -C $Path config --get gitflow.branch.allow-master-commit)
  if ( $value -eq "" ) {
    git -C $Path config --bool gitflow.branch.allow-master-commit false
    if ( $LASTEXITCODE -ne 0 ) {
      Write-Error "git flow Allow Master Commit configuration failed"
      exit 1
    }
  }
  $value = (git -C $Path config --get gitflow.branch.allow-config-commit)
  if ( $value -eq "" ) {
    git -C $Path config --bool gitflow.branch.allow-config-commit false
    if ( $LASTEXITCODE -ne 0 ) {
      Write-Error "git flow Allow Conflict Commit configuration failed"
      exit 1
    }
  }
}

# 3/ copy hooks
if (! (Test-Path $hooksPath)) {
  Write-Verbose "Creating folder $hooksPath"
  New-Item -Path $hooksPath -ItemType Directory -WhatIf:$WhatIfPreference
}

$language = ""
if (Test-Path $Path/package.json) {
  $language = "node"
} elseif (Test-Path $Path/go.mod) {
  $language = "go"
} elseif (Test-Path $Path/pom.xml) {
  $language = "java"
} else {
  Write-Error  "Could not determine language of repository $Path"
  exit 1
}
Write-Verbose "$hooksPath is a $language repository"

Write-Verbose "Copying hooks to folder $hooksPath"
Copy-Item -Path ./hooks/common/*    -Destination $hooksPath -Force -WhatIf:$WhatIfPreference
Copy-Item -Path ./hooks/$language/* -Destination $hooksPath -Force -WhatIf:$WhatIfPreference
