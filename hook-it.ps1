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
  Write-Error "git flow is not initialized in repository $REPO"
  exit 1
}
$hooksPath=git -C $Path config gitflow.path.hooks
if ( ! $hooksPath ) {
  Write-Error "git flow AVH edition is needed for this to work"
  exit 1
}

# 2/ Configure git flow
if ($PSCmdlet.ShouldProcess("gitflow", "Configure Messages")) {
  git -C $Path config gitflow.hotfix.finish.message "Hotfix %tag%"
  git -C $Path config gitflow.release.finish.message "Release %tag%"
}

# 3/ copy hooks
if (! (Test-Path $hooksPath)) {
  Write-Verbose "Creating folder $hooksPath"
  New-Item -Path $hooksPath -ItemType Directory -WhatIf:$WhatIfPreference
}
Write-Verbose "Copying hooks to folder $hooksPath"
Copy-Item -Path ./hooks/* -Destination $hooksPath -Force -WhatIf:$WhatIfPreference
