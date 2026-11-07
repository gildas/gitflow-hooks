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
        if self.is_git_flow_initialized(repo)? || self.import_shared_config(repo, flavor)? {
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
        // The hooks folder before the reset (e.g.: in the previous location of the repo), as core.hooksPath may still point to it
        let previous_hooks_path = self.git_get(
            repo,
            &["config", "--type=path", "--get", "gitflow.path.hooks"],
        )?;

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
        self.preserve_custom_pre_commit(repo, &hooks_path)?;
        verbose!("Copying hooks");
        for folder in ["common", language.name()] {
            self.copy_hooks(folder, &hooks_path).map_err(|err| {
                format!(
                    "Error while copying {folder} hooks to {}: {err}",
                    hooks_path.display()
                )
            })?;
        }

        // 5/ make sure git runs our hooks, even when the repository has its own hooks folder (e.g.: a committed .githooks)
        self.take_over_hooks_path(repo, &hooks_path, &previous_hooks_path)?;
        Ok(())
    }

    /// git only runs the hooks of core.hooksPath, which would skip our pre-commit hook
    /// When core.hooksPath points to another folder, it is saved in gitflow.path.custom-hooks and core.hooksPath points to our hooks,
    /// which forward every git hook to the custom folder (our pre-commit runs the custom pre-commit after its own checks)
    /// The forwarders are installed after our hooks, so core.hooksPath only moves once everything is in place
    /// core.hooksPath is not a custom folder when it points to our hooks, now or before the repo was moved or copied
    /// (previous_hooks_path), or to any folder carrying our pre-commit, as forwarding to it would loop
    fn take_over_hooks_path(
        &self,
        repo: &Path,
        hooks_path: &Path,
        previous_hooks_path: &str,
    ) -> Result<(), String> {
        let is_managed = |folder: &Path| {
            same_folder(folder, hooks_path)
                || (!previous_hooks_path.is_empty()
                    && same_folder(folder, &repo.join(previous_hooks_path)))
                || fs::read(folder.join("pre-commit"))
                    .is_ok_and(|contents| is_our_pre_commit(&contents))
        };
        let hooks_path_config =
            self.git_get(repo, &["config", "--type=path", "--get", "core.hooksPath"])?;
        let mut custom_hooks = self.git_get(
            repo,
            &[
                "config",
                "--type=path",
                "--get",
                "gitflow.path.custom-hooks",
            ],
        )?;
        if !hooks_path_config.is_empty() && !is_managed(&repo.join(&hooks_path_config)) {
            custom_hooks = hooks_path_config.clone();
        }
        if custom_hooks.is_empty() {
            // core.hooksPath points to other git flow hooks: in the previous location of the repository (moved or copied),
            // or another folder of git flow hooks (e.g.: in the global config), git would run them instead of the ones just installed
            let configured = repo.join(&hooks_path_config);
            if !hooks_path_config.is_empty() && !same_folder(&configured, hooks_path) {
                let previous = !previous_hooks_path.is_empty()
                    && same_folder(&configured, &repo.join(previous_hooks_path));
                if !previous {
                    // Its other hooks will not run anymore (forwarding to it would run its git flow pre-commit, which loops)
                    let others: Vec<&str> = GIT_HOOKS
                        .iter()
                        .copied()
                        .filter(|name| {
                            fs::read(configured.join(name))
                                .is_ok_and(|contents| !is_forwarder(&contents))
                        })
                        .collect();
                    warning!(
                        "core.hooksPath pointed to the git flow hooks in {}, it now points to {}{}",
                        configured.display(),
                        hooks_path.display(),
                        if others.is_empty() {
                            String::new()
                        } else {
                            format!(
                                ". These hooks from that folder will not run anymore: {}",
                                others.join(", ")
                            )
                        }
                    );
                }
                self.git_config(repo, "core.hooksPath", &hooks_path.to_string_lossy())?;
            }
            return Ok(());
        }
        verbose!("Forwarding the git hooks to {custom_hooks}");
        let custom_path = repo.join(&custom_hooks);
        if is_managed(&custom_path) {
            // e.g.: set by hand to a folder of git flow hooks
            return Err(format!(
                "gitflow.path.custom-hooks ({custom_hooks}) is a git flow hooks folder, forwarding to it would loop. Set it to your own hooks folder (e.g.: git config gitflow.path.custom-hooks .githooks) or remove it (git config --unset gitflow.path.custom-hooks)"
            ));
        }
        let forwarder = self.hook_contents("forward", "forward-hook")?;
        for name in GIT_HOOKS {
            let destination = hooks_path.join(name);
            if let Ok(contents) = fs::read(&destination)
                && !is_forwarder(&contents)
            {
                // Not ours (e.g.: a hook installed by another tool in .git/hooks), leave it alone
                if custom_path.join(name).exists() {
                    warning!(
                        "{} is not a git flow hook, {} will not run. Move it away and run hook-it again",
                        destination.display(),
                        custom_path.join(name).display()
                    );
                }
                continue;
            }
            if self.noop {
                println!("Would write {}", destination.display());
                continue;
            }
            install_file(&destination, &forwarder)
                .map_err(|err| format!("Error while writing {}: {err}", destination.display()))?;
        }
        self.git_config(repo, "gitflow.path.custom-hooks", &custom_hooks)?;
        let hooks_path_str = hooks_path.to_string_lossy();
        if hooks_path_config.is_empty() || !same_folder(&repo.join(&hooks_path_config), hooks_path)
        {
            self.git_config(repo, "core.hooksPath", &hooks_path_str)?;
            warning!(
                "core.hooksPath now points to {hooks_path_str}, the hooks from {custom_hooks} still run (pre-commit after the git flow checks). If core.hooksPath changes again (e.g.: husky), run hook-it again"
            );
        }
        Ok(())
    }

    /// Gives the contents of a hook, from the hooks folder given on the command line or the embedded ones
    fn hook_contents(&self, folder: &str, name: &str) -> Result<Vec<u8>, String> {
        match &self.hooks_source {
            Some(source) => {
                let path = source.join(folder).join(name);
                fs::read(&path).map_err(|err| format!("{}: {err}", path.display()))
            }
            None => HOOKS
                .get_file(format!("{folder}/{name}"))
                .map(|file| file.contents().to_vec())
                .ok_or_else(|| format!("No embedded hook {folder}/{name}")),
        }
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

    /// Copies the git-flow-next configuration shared in the repository (.gitflow, from git flow init --shared) into the local config
    /// git-flow-next reads .gitflow by itself, but git flow init ignores it and the hooks only read the git config,
    /// so a fresh clone would get git flow's default branches instead of the shared ones
    /// Tells if the configuration was imported
    fn import_shared_config(&self, repo: &Path, flavor: Flavor) -> Result<bool, String> {
        let shared = repo.join(".gitflow");
        if flavor != Flavor::Next || !shared.is_file() {
            return Ok(false);
        }
        let shared_str = shared.to_string_lossy();
        if self.git_get(
            repo,
            &[
                "config",
                "--file",
                &shared_str,
                "--bool",
                "gitflow.initialized",
            ],
        )? != "true"
        {
            return Ok(false);
        }
        verbose!("Importing the shared git flow configuration from {shared_str}");
        let entries = self.git_get(repo, &["config", "--file", &shared_str, "--list", "-z"])?;
        let mut skipped = Vec::new();
        for entry in entries.split('\0').filter(|entry| !entry.is_empty()) {
            let (key, value) = entry.split_once('\n').unwrap_or((entry, ""));
            if is_shareable_key(key) {
                self.git_config(repo, key, value)?;
            } else {
                skipped.push(key);
            }
        }
        if !skipped.is_empty() {
            warning!(
                "Ignored these settings from {shared_str}, only the branch configuration is imported, set them yourself if you trust them: {}",
                skipped.join(", ")
            );
        }
        Ok(true)
    }

    /// Copies the user's own pre-commit hook to pre-commit.local, before ours overwrites it
    /// Our pre-commit runs pre-commit.local after its own checks
    /// It is copied, not moved, so the user's hook stays in place if installing ours fails
    /// gitflow.path.pre-commit is updated when it points to the replaced hook, as it would point to ours afterwards
    fn preserve_custom_pre_commit(&self, repo: &Path, hooks_path: &Path) -> Result<(), String> {
        let pre_commit = hooks_path.join("pre-commit");
        // Look at the entry itself, without following it: a dangling symlink still is the user's hook
        match fs::symlink_metadata(&pre_commit) {
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(()),
            Err(err) => return Err(format!("Cannot check {}: {err}", pre_commit.display())),
            Ok(_) => {}
        }
        let link = fs::read_link(&pre_commit).ok();
        let contents = match fs::read(&pre_commit) {
            Ok(contents) if is_our_pre_commit(&contents) => return Ok(()),
            Ok(contents) => Some(contents),
            // A dangling symlink is saved as is
            Err(_) if link.is_some() => None,
            // It would be replaced without a backup
            Err(err) => {
                return Err(format!(
                    "Cannot read {} to save it before installing the git flow pre-commit hook: {err}",
                    pre_commit.display()
                ));
            }
        };
        let local = hooks_path.join("pre-commit.local");
        // Never write onto an existing pre-commit.local, not even a dangling symlink (it would be written through)
        let local_exists = fs::symlink_metadata(&local).is_ok();
        // Saved by a previous run that could not install our hooks: the same symlink, or a copy of the same contents
        let already_saved = local_exists
            && match &link {
                Some(target) => {
                    fs::read_link(&local).is_ok_and(|local_target| &local_target == target)
                }
                None => {
                    !local.is_symlink()
                        && fs::read(&local)
                            .is_ok_and(|local_contents| Some(local_contents) == contents)
                }
            };
        match (local_exists, already_saved) {
            (_, true) => {}
            (true, false) => {
                return Err(format!(
                    "{} is not a git flow hook and {} already exists, move one of them away first",
                    pre_commit.display(),
                    local.display()
                ));
            }
            (false, _) if self.noop => {
                println!("Would copy {} to {}", pre_commit.display(), local.display());
            }
            (false, _) => {
                preserve_file(&pre_commit, &local).map_err(|err| {
                    format!(
                        "Error while copying {} to {}: {err}",
                        pre_commit.display(),
                        local.display()
                    )
                })?;
                if is_executable(&pre_commit) {
                    warning!(
                        "Saved your pre-commit hook as {}, it will run after the git flow pre-commit hook",
                        local.display()
                    );
                } else {
                    warning!(
                        "Saved your pre-commit hook as {}, it is not executable, so like before it will not run (chmod +x to turn it on)",
                        local.display()
                    );
                }
            }
        }
        let configured = self.git_get(
            repo,
            &["config", "--type=path", "--get", "gitflow.path.pre-commit"],
        )?;
        if !configured.is_empty() && same_entry(&repo.join(&configured), &pre_commit) {
            self.git_config(repo, "gitflow.path.pre-commit", &local.to_string_lossy())?;
        }
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
                    fs::read(entry.path())
                        .and_then(|contents| install_file(&destination, &contents))
                        .map_err(|err| err.to_string())?;
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
                    install_file(&destination, file.contents()).map_err(|err| err.to_string())?;
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

/// The git hooks forwarded to gitflow.path.custom-hooks (see githooks(5)), pre-commit is ours and runs the custom one itself
const GIT_HOOKS: [&str; 27] = [
    "applypatch-msg",
    "pre-applypatch",
    "post-applypatch",
    "pre-merge-commit",
    "prepare-commit-msg",
    "commit-msg",
    "post-commit",
    "pre-rebase",
    "post-checkout",
    "post-merge",
    "pre-push",
    "pre-receive",
    "update",
    "proc-receive",
    "post-receive",
    "post-update",
    "reference-transaction",
    "push-to-checkout",
    "pre-auto-gc",
    "post-rewrite",
    "sendemail-validate",
    "fsmonitor-watchman",
    "p4-changelist",
    "p4-prepare-changelist",
    "p4-post-changelist",
    "p4-pre-submit",
    "post-index-change",
];

/// Tells if the setting can be imported from a committed .gitflow file: only the branch configuration of git-flow-next
/// The other settings (e.g.: gitflow.path.pre-commit, gitflow.allow-master-commit) would let any repository run its own scripts
/// on commit or turn the checks off, without the developer opting in
fn is_shareable_key(key: &str) -> bool {
    const BRANCH_KEYS: [&str; 10] = [
        "type",
        "parent",
        "startpoint",
        "upstreamstrategy",
        "downstreamstrategy",
        "prefix",
        "autoupdate",
        "tag",
        "tagprefix",
        "worktree",
    ];
    if key == "gitflow.version" || key == "gitflow.initialized" {
        return true;
    }
    // Branch names can contain dots (e.g.: gitflow.branch.v1.x.type), the setting is the last part
    key.strip_prefix("gitflow.branch.")
        .and_then(|rest| rest.rsplit_once('.'))
        .is_some_and(|(name, setting)| !name.is_empty() && BRANCH_KEYS.contains(&setting))
}

/// Tells if the hook is one of our forwarders
fn is_forwarder(contents: &[u8]) -> bool {
    String::from_utf8_lossy(contents).contains("# gitflow-hooks: forwarder")
}

/// Tells if both paths are the same folder, when they exist, or the same path otherwise
fn same_folder(left: &Path, right: &Path) -> bool {
    match (left.canonicalize(), right.canonicalize()) {
        (Ok(left), Ok(right)) => left == right,
        _ => left == right,
    }
}

/// Tells if the pre-commit hook is one of ours (any version), they all load our functions.sh
fn is_our_pre_commit(contents: &[u8]) -> bool {
    String::from_utf8_lossy(contents).contains("\"$HOOKS_DIR\"/functions.sh")
}

/// Saves a hook under another name, a symlink stays a symlink to the same target (e.g.: a committed .githooks/pre-commit),
/// so the changes of its target still apply. Elsewhere than on Unix, the contents and permissions are copied
fn preserve_file(source: &Path, destination: &Path) -> std::io::Result<()> {
    #[cfg(unix)]
    if let Ok(target) = fs::read_link(source) {
        // Both are in the same folder, so a relative target stays valid
        return std::os::unix::fs::symlink(target, destination);
    }
    fs::copy(source, destination).map(|_| ())
}

/// Tells if both paths name the same entry of the same folder, without following the entry itself if it is a symlink
fn same_entry(left: &Path, right: &Path) -> bool {
    left.file_name() == right.file_name()
        && match (left.parent(), right.parent()) {
            (Some(left), Some(right)) => same_folder(left, right),
            _ => false,
        }
}

/// Writes an executable hook through a temporary file renamed over the destination:
/// a symlink is replaced, not written through (it could point to a committed hook, e.g.: .githooks/pre-commit),
/// and the previous file stays in place if writing fails
fn install_file(destination: &Path, contents: &[u8]) -> std::io::Result<()> {
    let name = destination
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_default();
    let temporary = destination.with_file_name(format!(".{name}.hook-it.tmp"));
    let _ = fs::remove_file(&temporary);
    let result = fs::write(&temporary, contents)
        .and_then(|_| make_executable(&temporary))
        .and_then(|_| fs::rename(&temporary, destination));
    if result.is_err() {
        let _ = fs::remove_file(&temporary);
    }
    result
}

/// Tells if git would run the hook, git ignores the hooks that are not executable (on Windows, they all are)
#[cfg(unix)]
fn is_executable(path: &Path) -> bool {
    use std::os::unix::fs::PermissionsExt;
    fs::metadata(path).is_ok_and(|metadata| metadata.permissions().mode() & 0o111 != 0)
}

#[cfg(not(unix))]
fn is_executable(_path: &Path) -> bool {
    true
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
    fn recognizes_our_forwarder() {
        let forwarder = injector().hook_contents("forward", "forward-hook").unwrap();
        assert!(is_forwarder(&forwarder));
        assert!(!is_our_pre_commit(&forwarder));
        assert!(!is_forwarder(b"#!/bin/sh\nctags -R\n"));
        assert!(!GIT_HOOKS.contains(&"pre-commit"));
    }

    #[test]
    fn our_hooks_folder_is_not_a_custom_one() {
        let dir = temp_hooks("managed");
        let ours = HOOKS.get_file("common/pre-commit").unwrap().contents();
        fs::write(dir.join("pre-commit"), ours).unwrap();
        // A hooks folder from the previous location of the repository, which carries our pre-commit
        assert!(
            fs::read(dir.join("pre-commit")).is_ok_and(|contents| is_our_pre_commit(&contents))
        );
        assert!(same_folder(&dir, &dir.join(".")));
        assert!(!same_folder(&dir, &dir.join("missing")));
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn imports_only_the_branch_configuration() {
        assert!(is_shareable_key("gitflow.initialized"));
        assert!(is_shareable_key("gitflow.branch.feature.parent"));
        assert!(is_shareable_key("gitflow.branch.v1.x.type"));
        assert!(!is_shareable_key("gitflow.path.pre-commit"));
        assert!(!is_shareable_key("gitflow.path.hooks"));
        assert!(!is_shareable_key("gitflow.allow-master-commit"));
        assert!(!is_shareable_key("gitflow.branch.feature.hook"));
        assert!(!is_shareable_key("gitflow.branch.type"));
    }

    #[cfg(unix)]
    #[test]
    fn replaces_symlinks_instead_of_writing_through() {
        let dir = temp_hooks("symlink");
        fs::create_dir_all(dir.join("shared")).unwrap();
        fs::write(dir.join("shared/pre-commit"), "#!/bin/sh\nteam\n").unwrap();
        std::os::unix::fs::symlink("shared/pre-commit", dir.join("pre-commit")).unwrap();
        preserve_file(&dir.join("pre-commit"), &dir.join("pre-commit.local")).unwrap();
        install_file(&dir.join("pre-commit"), b"#!/bin/sh\nours\n").unwrap();
        assert_eq!(
            fs::read_to_string(dir.join("shared/pre-commit")).unwrap(),
            "#!/bin/sh\nteam\n"
        );
        assert_eq!(
            fs::read_to_string(dir.join("pre-commit")).unwrap(),
            "#!/bin/sh\nours\n"
        );
        assert!(!dir.join("pre-commit").is_symlink());
        assert_eq!(
            fs::read_link(dir.join("pre-commit.local")).unwrap(),
            PathBuf::from("shared/pre-commit")
        );
        assert!(!dir.join(".pre-commit.hook-it.tmp").exists());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn saves_a_dangling_pre_commit_symlink() {
        let dir = temp_hooks("dangling");
        std::os::unix::fs::symlink("missing/pre-commit", dir.join("pre-commit")).unwrap();
        injector().preserve_custom_pre_commit(&dir, &dir).unwrap();
        assert_eq!(
            fs::read_link(dir.join("pre-commit.local")).unwrap(),
            PathBuf::from("missing/pre-commit")
        );
        // A second run (e.g.: after a failed installation) accepts it
        injector().preserve_custom_pre_commit(&dir, &dir).unwrap();
        fs::remove_dir_all(&dir).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn never_writes_through_a_dangling_local() {
        let dir = temp_hooks("dangling-local");
        fs::write(dir.join("pre-commit"), "#!/bin/sh\nmake lint\n").unwrap();
        std::os::unix::fs::symlink("target", dir.join("pre-commit.local")).unwrap();
        assert!(injector().preserve_custom_pre_commit(&dir, &dir).is_err());
        assert!(!dir.join("target").exists());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn refuses_to_replace_an_unreadable_pre_commit() {
        use std::os::unix::fs::PermissionsExt;
        let dir = temp_hooks("unreadable");
        fs::write(dir.join("pre-commit"), "#!/bin/sh\nmake lint\n").unwrap();
        fs::set_permissions(dir.join("pre-commit"), fs::Permissions::from_mode(0o000)).unwrap();
        // root reads anything, nothing to check then
        if fs::read(dir.join("pre-commit")).is_err() {
            assert!(injector().preserve_custom_pre_commit(&dir, &dir).is_err());
            assert!(!dir.join("pre-commit.local").exists());
        }
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn copies_custom_pre_commit() {
        let dir = temp_hooks("custom");
        fs::write(dir.join("pre-commit"), "#!/bin/sh\nmake lint\n").unwrap();
        injector().preserve_custom_pre_commit(&dir, &dir).unwrap();
        // Still in place, in case installing our hooks fails
        assert!(dir.join("pre-commit").exists());
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
        injector().preserve_custom_pre_commit(&dir, &dir).unwrap();
        assert!(dir.join("pre-commit").exists());
        assert!(!dir.join("pre-commit.local").exists());
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn accepts_a_previous_copy() {
        let dir = temp_hooks("retry");
        fs::write(dir.join("pre-commit"), "#!/bin/sh\nmake lint\n").unwrap();
        fs::write(dir.join("pre-commit.local"), "#!/bin/sh\nmake lint\n").unwrap();
        injector().preserve_custom_pre_commit(&dir, &dir).unwrap();
        fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn refuses_to_overwrite_existing_local() {
        let dir = temp_hooks("both");
        fs::write(dir.join("pre-commit"), "#!/bin/sh\nmake lint\n").unwrap();
        fs::write(dir.join("pre-commit.local"), "#!/bin/sh\nmake test\n").unwrap();
        assert!(injector().preserve_custom_pre_commit(&dir, &dir).is_err());
        assert!(dir.join("pre-commit").exists());
        fs::remove_dir_all(&dir).unwrap();
    }
}
