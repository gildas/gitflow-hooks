//! Injection of the git flow hooks in a repository

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use include_dir::{Dir, include_dir};

use crate::output::{verbose, warning};

/// The hooks shipped with hook-it, embedded at compile time
static HOOKS: Dir = include_dir!("$CARGO_MANIFEST_DIR/hooks");

/// The folders searched for the language when none are given
const DEFAULT_SOURCES: [&str; 4] = [".", "src", "backend", "src/backend"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Language {
    Salesforce,
    Node,
    Go,
    Rust,
}

impl Language {
    /// The name of the folder carrying the language specific hooks
    pub fn name(self) -> &'static str {
        match self {
            Language::Salesforce => "salesforce",
            Language::Node => "node",
            Language::Go => "go",
            Language::Rust => "rust",
        }
    }

    /// Detects the language of the code in the given folder
    pub fn detect(folder: &Path) -> Option<Language> {
        if folder.join("sfdx-project.json").exists() {
            Some(Language::Salesforce)
        } else if folder.join("Cargo.toml").exists() {
            // Before package.json, as a Rust backend may carry its web client at the root
            Some(Language::Rust)
        } else if folder.join("package.json").exists() {
            Some(Language::Node)
        } else if folder.join("go.mod").exists() {
            Some(Language::Go)
        } else {
            None
        }
    }
}

/// The git flow implementations supporting hooks
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Flavor {
    Avh,
    Next,
}

pub struct Injector {
    /// The git executable
    pub git: String,
    /// The hooks folder, relative to the repository
    pub hooks_dir: PathBuf,
    /// The folders, relative to the repository, used to detect the language
    pub sources: Vec<String>,
    /// Copy the hooks from this folder instead of the embedded ones
    pub hooks_source: Option<PathBuf>,
    pub use_pull_requests: bool,
    /// The main (production) branch name to use when initializing git flow
    pub main_branch: Option<String>,
    /// The develop branch name to use when initializing git flow
    pub develop_branch: Option<String>,
    pub noop: bool,
}

impl Injector {
    pub fn inject(&self, repo: &Path) -> Result<(), String> {
        // 0/ validation
        if !repo.is_dir() {
            return Err(format!("Folder {} does not exist", repo.display()));
        }
        if !repo.join(".git").is_dir() {
            return Err(format!("Folder {} is not a git repository", repo.display()));
        }
        // Use an absolute path, so the hooks path stored in the git config does not depend on the current folder
        let repo = &repo
            .canonicalize()
            .map_err(|err| format!("Failed to resolve {}: {err}", repo.display()))?;
        verbose!("Injecting git hooks into {}", repo.display());

        // 1/ make sure git flow is installed and initialized
        let flavor = self.git_flow_flavor(repo)?;
        verbose!("git flow: {flavor:?}");
        if self.is_git_flow_initialized(repo)? {
            self.check_branches(repo, flavor)?;
        } else {
            verbose!("Initializing git flow in repository {}", repo.display());
            // Branch names: from the command line, else from the git config (any level), else git flow's defaults
            // git-flow-next ignores the git flow AVH branch names when they are not in the repository config
            // (e.g.: gitflow.branch.develop=dev in ~/.gitconfig), and would create main and develop instead
            let master = match &self.main_branch {
                Some(branch) => branch.clone(),
                None => self.git_get(repo, &["config", "--get", "gitflow.branch.master"])?,
            };
            let develop = match &self.develop_branch {
                Some(branch) => branch.clone(),
                None => self.git_get(repo, &["config", "--get", "gitflow.branch.develop"])?,
            };
            // git flow silently falls back to, or creates, other branches than the requested ones
            self.prepare_branches(repo)?;
            let mut args: Vec<String> = Vec::new();
            match flavor {
                Flavor::Next => {
                    args.extend(["flow", "init", "-fd", "--tag", "v"].map(String::from));
                    if !master.is_empty() {
                        args.extend(["--main".into(), master.clone()]);
                    }
                    if !develop.is_empty() {
                        args.extend(["--develop".into(), develop.clone()]);
                    }
                }
                Flavor::Avh => {
                    // git flow AVH has no flags for the branch names, it reads them from the git config.
                    // They are given as temporary overrides (git -c), so a failed initialization does not leave
                    // a gitflow.branch.master behind that would make the repository look initialized
                    if let Some(branch) = &self.main_branch {
                        args.extend(["-c".into(), format!("gitflow.branch.master={branch}")]);
                    }
                    if let Some(branch) = &self.develop_branch {
                        args.extend(["-c".into(), format!("gitflow.branch.develop={branch}")]);
                    }
                    args.extend(["flow", "init", "-fd", "--tag", "v"].map(String::from));
                }
            }
            let args: Vec<&str> = args.iter().map(String::as_str).collect();
            self.git_run(repo, &args).map_err(|err| {
                format!(
                    "Error while initializing git flow in repository {}: {err}",
                    repo.display()
                )
            })?;
            if !self.noop {
                if !self.is_git_flow_initialized(repo)? {
                    return Err(
                        "git flow was not installed properly, please install it manually".into(),
                    );
                }
                // git flow may pick other branches than the requested ones (e.g.: AVH falls back to an existing main)
                let (current_master, current_develop) = self.current_branches(repo, flavor)?;
                let differs = |wanted: &Option<String>, current: &str| {
                    wanted.as_deref().is_some_and(|wanted| wanted != current)
                };
                if differs(&self.main_branch, &current_master)
                    || differs(&self.develop_branch, &current_develop)
                {
                    return Err(format!(
                        "git flow was initialized in {} with main branch \"{current_master}\" and develop branch \"{current_develop}\" instead of the requested ones. To change them, run: git flow init -f",
                        repo.display()
                    ));
                }
            }
        }
        // Resetting the hooks folder, in case the repo was moved
        let hooks_path = repo.join(&self.hooks_dir);

        // 2/ configure git flow
        verbose!("Configuring gitflow");
        let hooks_path_str = hooks_path.to_string_lossy();
        let use_pull_requests = if self.use_pull_requests {
            "true"
        } else {
            "false"
        };
        self.git_config(repo, "gitflow.path.hooks", &hooks_path_str)?;
        self.git_config(repo, "gitflow.prefix.versiontag", "v")?;
        if flavor == Flavor::Next {
            // git-flow-next stores the tag prefix per branch type
            self.git_config(repo, "gitflow.branch.release.tagprefix", "v")?;
            self.git_config(repo, "gitflow.branch.hotfix.tagprefix", "v")?;
            // Like git flow AVH, always create a merge commit when finishing releases and hotfixes
            self.git_config(repo, "gitflow.release.finish.no-ff", "true")?;
            self.git_config(repo, "gitflow.hotfix.finish.no-ff", "true")?;
        }
        self.git_config(repo, "gitflow.hotfix.finish.message", "Hotfix %tag%")?;
        self.git_config(repo, "gitflow.release.finish.message", "Release %tag%")?;
        self.git_config(repo, "gitflow.use-pull-request", use_pull_requests)?;
        for key in [
            "gitflow.allow-master-commit",
            "gitflow.allow-conflict-commit",
        ] {
            if self.git_get(repo, &["config", "--get", key])?.is_empty() {
                self.git_config(repo, key, "false")?;
            }
        }

        // 3/ find language
        // TODO: Also handle repos with multiple languages, like go and node (web kind of app, that have a backend and a frontend)
        let sources: Vec<&str> = if self.sources.is_empty() {
            DEFAULT_SOURCES.to_vec()
        } else {
            self.sources.iter().map(String::as_str).collect()
        };
        let language = sources
            .iter()
            .find_map(|source| Language::detect(&repo.join(source)))
            .ok_or_else(|| format!("Unable to find language for {}", repo.display()))?;
        verbose!("Language: {}", language.name());

        // 4/ copy hooks
        if !hooks_path.is_dir() {
            if self.noop {
                println!("Would create folder {}", hooks_path.display());
            } else {
                fs::create_dir_all(&hooks_path).map_err(|err| {
                    format!(
                        "Error while creating hooks folder {}: {err}",
                        hooks_path.display()
                    )
                })?;
            }
        }
        self.preserve_custom_pre_commit(&hooks_path)?;
        verbose!("Copying hooks");
        for folder in ["common", language.name()] {
            self.copy_hooks(folder, &hooks_path).map_err(|err| {
                format!(
                    "Error while copying {folder} hooks to {}: {err}",
                    hooks_path.display()
                )
            })?;
        }
        Ok(())
    }

    /// Finds which git flow is installed, only git flow AVH and git-flow-next support hooks
    fn git_flow_flavor(&self, repo: &Path) -> Result<Flavor, String> {
        let version = self.git_get(repo, &["flow", "version"])?;
        if version.contains("AVH") {
            Ok(Flavor::Avh)
        } else if version.contains("git-flow-next") {
            Ok(Flavor::Next)
        } else {
            Err("git flow AVH edition or git-flow-next is needed for this to work".into())
        }
    }

    /// Warns when the branches given on the command line differ from the ones of an initialized repository
    /// The branches are not changed, as existing feature/release/hotfix branches depend on them
    fn check_branches(&self, repo: &Path, flavor: Flavor) -> Result<(), String> {
        if self.main_branch.is_none() && self.develop_branch.is_none() {
            return Ok(());
        }
        let (master, develop) = self.current_branches(repo, flavor)?;
        let differs = |wanted: &Option<String>, current: &str| {
            wanted.as_deref().is_some_and(|wanted| wanted != current)
        };
        if differs(&self.main_branch, &master) || differs(&self.develop_branch, &develop) {
            warning!(
                "git flow is already initialized in {} with main branch \"{master}\" and develop branch \"{develop}\", ignoring --main/--develop. To change them, run: git flow init -f",
                repo.display()
            );
        }
        Ok(())
    }

    /// Finds the main and develop branches of an initialized repository, like the hooks do (see functions.sh)
    /// git-flow-next: the main branch is the base branch without parent, the develop branch is the parent of features
    /// git flow AVH: gitflow.branch.master and gitflow.branch.develop
    fn current_branches(&self, repo: &Path, flavor: Flavor) -> Result<(String, String), String> {
        let is_next = flavor == Flavor::Next
            && self.git_get(
                repo,
                &["config", "--local", "--bool", "gitflow.initialized"],
            )? == "true";
        if !is_next {
            return Ok((
                self.git_get(repo, &["config", "--get", "gitflow.branch.master"])?,
                self.git_get(repo, &["config", "--get", "gitflow.branch.develop"])?,
            ));
        }
        let types = self.git_get(
            repo,
            &[
                "config",
                "--local",
                "--get-regexp",
                r"^gitflow\.branch\..*\.type$",
            ],
        )?;
        let mut master = String::new();
        for line in types.lines() {
            let Some((key, "base")) = line.split_once(' ') else {
                continue;
            };
            let Some(name) = key
                .strip_prefix("gitflow.branch.")
                .and_then(|key| key.strip_suffix(".type"))
            else {
                continue;
            };
            let parent_key = format!("gitflow.branch.{name}.parent");
            if self
                .git_get(repo, &["config", "--get", &parent_key])?
                .is_empty()
            {
                master = name.to_string();
                break;
            }
        }
        let develop = self.git_get(repo, &["config", "--get", "gitflow.branch.feature.parent"])?;
        Ok((master, develop))
    }

    /// Makes sure git flow uses the requested branches, as it silently falls back to other ones:
    /// git flow AVH picks an existing branch (e.g.: --main production picks main when production does not exist),
    /// git-flow-next creates the missing main branch from HEAD (a typo would create a new production branch)
    /// The main branch must exist (locally or on origin), the develop branch is created from it when missing
    fn prepare_branches(&self, repo: &Path) -> Result<(), String> {
        if self.main_branch.is_none() && self.develop_branch.is_none() {
            return Ok(());
        }
        // In a repository without any branch, git flow creates the requested branches itself
        if self.git_get(repo, &["branch", "--list"])?.is_empty() {
            return Ok(());
        }
        let master = match &self.main_branch {
            Some(branch) => branch.clone(),
            None => {
                let configured =
                    self.git_get(repo, &["config", "--get", "gitflow.branch.master"])?;
                if configured.is_empty() {
                    "master".into()
                } else {
                    configured
                }
            }
        };
        if !self.branch_exists(repo, &master)? {
            return Err(format!(
                "The main branch \"{master}\" does not exist in {}, create it first",
                repo.display()
            ));
        }
        if let Some(develop) = &self.develop_branch
            && !self.branch_exists(repo, develop)?
        {
            verbose!("Creating the develop branch {develop} from {master}");
            let start = if self.git_ok(
                repo,
                &[
                    "rev-parse",
                    "--verify",
                    "--quiet",
                    &format!("refs/heads/{master}"),
                ],
            )? {
                master.clone()
            } else {
                format!("origin/{master}")
            };
            self.git_run(repo, &["branch", "--no-track", develop, &start])?;
        }
        Ok(())
    }

    /// Tells if the branch exists locally or on origin
    fn branch_exists(&self, repo: &Path, branch: &str) -> Result<bool, String> {
        Ok(self.git_ok(
            repo,
            &[
                "rev-parse",
                "--verify",
                "--quiet",
                &format!("refs/heads/{branch}"),
            ],
        )? || self.git_ok(
            repo,
            &[
                "rev-parse",
                "--verify",
                "--quiet",
                &format!("refs/remotes/origin/{branch}"),
            ],
        )?)
    }

    /// Runs git and tells if it succeeded, even in noop mode, so only use it for read-only commands
    fn git_ok(&self, repo: &Path, args: &[&str]) -> Result<bool, String> {
        Command::new(&self.git)
            .arg("-C")
            .arg(repo)
            .args(args)
            .output()
            .map(|output| output.status.success())
            .map_err(|err| format!("Failed to run {}: {err}", self.git))
    }

    /// Tells if git flow is initialized, git flow AVH sets gitflow.branch.master, git-flow-next sets gitflow.initialized
    /// Only gitflow.branch.master is checked for git flow AVH, as many repositories keep gitflow.branch.develop in the global config
    fn is_git_flow_initialized(&self, repo: &Path) -> Result<bool, String> {
        Ok(!self
            .git_get(repo, &["config", "--local", "gitflow.branch.master"])?
            .is_empty()
            || self.git_get(
                repo,
                &["config", "--local", "--bool", "gitflow.initialized"],
            )? == "true")
    }

    /// Moves the user's own pre-commit hook to pre-commit.local, so ours does not overwrite it
    /// Our pre-commit runs pre-commit.local after its own checks
    fn preserve_custom_pre_commit(&self, hooks_path: &Path) -> Result<(), String> {
        let pre_commit = hooks_path.join("pre-commit");
        let Ok(contents) = fs::read(&pre_commit) else {
            return Ok(());
        };
        if is_our_pre_commit(&contents) {
            return Ok(());
        }
        let local = hooks_path.join("pre-commit.local");
        if local.exists() {
            return Err(format!(
                "{} is not a git flow hook and {} already exists, move one of them away first",
                pre_commit.display(),
                local.display()
            ));
        }
        if self.noop {
            println!("Would move {} to {}", pre_commit.display(), local.display());
            return Ok(());
        }
        fs::rename(&pre_commit, &local).map_err(|err| {
            format!(
                "Error while moving {} to {}: {err}",
                pre_commit.display(),
                local.display()
            )
        })?;
        warning!(
            "Moved your pre-commit hook to {}, it will run after the git flow pre-commit hook",
            local.display()
        );
        Ok(())
    }

    /// Copies the hooks of the given folder (common or a language) into the hooks path
    fn copy_hooks(&self, folder: &str, hooks_path: &Path) -> Result<(), String> {
        match &self.hooks_source {
            Some(source) => {
                let source = source.join(folder);
                let mut entries = fs::read_dir(&source)
                    .map_err(|err| format!("{}: {err}", source.display()))?
                    .collect::<Result<Vec<_>, _>>()
                    .map_err(|err| err.to_string())?;
                entries.sort_by_key(|entry| entry.file_name());
                for entry in entries.iter().filter(|entry| entry.path().is_file()) {
                    let destination = hooks_path.join(entry.file_name());
                    if self.noop {
                        println!(
                            "Would copy {} to {}",
                            entry.path().display(),
                            destination.display()
                        );
                        continue;
                    }
                    fs::copy(entry.path(), &destination).map_err(|err| err.to_string())?;
                }
            }
            None => {
                let dir = HOOKS
                    .get_dir(folder)
                    .ok_or_else(|| format!("No embedded hooks for {folder}"))?;
                let mut files: Vec<_> = dir.files().collect();
                files.sort_by_key(|file| file.path());
                for file in files {
                    let name = file.path().file_name().expect("embedded files have a name");
                    let destination = hooks_path.join(name);
                    if self.noop {
                        println!("Would write {}", destination.display());
                        continue;
                    }
                    fs::write(&destination, file.contents()).map_err(|err| err.to_string())?;
                    make_executable(&destination).map_err(|err| err.to_string())?;
                }
            }
        }
        Ok(())
    }

    /// Runs git and returns its trimmed output, an unset configuration key gives an empty string
    fn git_get(&self, repo: &Path, args: &[&str]) -> Result<String, String> {
        let output = Command::new(&self.git)
            .arg("-C")
            .arg(repo)
            .args(args)
            .output()
            .map_err(|err| format!("Failed to run {}: {err}", self.git))?;
        Ok(String::from_utf8_lossy(&output.stdout).trim().to_string())
    }

    /// Runs git, or only displays the command in noop mode
    fn git_run(&self, repo: &Path, args: &[&str]) -> Result<(), String> {
        if self.noop {
            println!(
                "Would run: {} -C {} {}",
                self.git,
                repo.display(),
                args.join(" ")
            );
            return Ok(());
        }
        let status = Command::new(&self.git)
            .arg("-C")
            .arg(repo)
            .args(args)
            .status()
            .map_err(|err| format!("Failed to run {}: {err}", self.git))?;
        match status.success() {
            true => Ok(()),
            false => Err(format!(
                "{} {} failed with {status}",
                self.git,
                args.join(" ")
            )),
        }
    }

    fn git_config(&self, repo: &Path, key: &str, value: &str) -> Result<(), String> {
        self.git_run(repo, &["config", key, value])
    }
}

/// Tells if the pre-commit hook is one of ours (any version), they all load our functions.sh
fn is_our_pre_commit(contents: &[u8]) -> bool {
    String::from_utf8_lossy(contents).contains("\"$HOOKS_DIR\"/functions.sh")
}

#[cfg(unix)]
fn make_executable(path: &Path) -> std::io::Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o755))
}

#[cfg(not(unix))]
fn make_executable(_path: &Path) -> std::io::Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn injector() -> Injector {
        Injector {
            git: "git".into(),
            hooks_dir: ".git/hooks".into(),
            sources: Vec::new(),
            hooks_source: None,
            use_pull_requests: false,
            main_branch: None,
            develop_branch: None,
            noop: false,
        }
    }

    fn temp_hooks(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("hook-it-{name}-{}", std::process::id()));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn recognizes_our_pre_commit() {
        let ours = HOOKS.get_file("common/pre-commit").unwrap().contents();
        assert!(is_our_pre_commit(ours));
        assert!(!is_our_pre_commit(b"#!/bin/sh\nmake lint\n"));
    }

    #[test]
    fn moves_custom_pre_commit() {
        let dir = temp_hooks("custom");
        fs::write(dir.join("pre-commit"), "#!/bin/sh\nmake lint\n").unwrap();
        injector().preserve_custom_pre_commit(&dir).unwrap();
        assert!(!dir.join("pre-commit").exists());
        assert_eq!(
            fs::read_to_string(dir.join("pre-commit.local")).unwrap(),
            "#!/bin/sh\nmake lint\n"
        );
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn keeps_our_pre_commit() {
        let dir = temp_hooks("ours");
        let ours = HOOKS.get_file("common/pre-commit").unwrap().contents();
        fs::write(dir.join("pre-commit"), ours).unwrap();
        injector().preserve_custom_pre_commit(&dir).unwrap();
        assert!(dir.join("pre-commit").exists());
        assert!(!dir.join("pre-commit.local").exists());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn refuses_to_overwrite_existing_local() {
        let dir = temp_hooks("both");
        fs::write(dir.join("pre-commit"), "#!/bin/sh\nmake lint\n").unwrap();
        fs::write(dir.join("pre-commit.local"), "#!/bin/sh\nmake test\n").unwrap();
        assert!(injector().preserve_custom_pre_commit(&dir).is_err());
        assert!(dir.join("pre-commit").exists());
        fs::remove_dir_all(&dir).unwrap();
    }
}
