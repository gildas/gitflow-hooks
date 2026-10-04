//! Injection of the git flow hooks in a repository

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use include_dir::{Dir, include_dir};

use crate::output::verbose;

/// The hooks shipped with hook-it, embedded at compile time
static HOOKS: Dir = include_dir!("$CARGO_MANIFEST_DIR/hooks");

/// The folders searched for the language when none are given
const DEFAULT_SOURCES: [&str; 4] = [".", "src", "backend", "src/backend"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Language {
    Salesforce,
    Node,
    Go,
}

impl Language {
    /// The name of the folder carrying the language specific hooks
    pub fn name(self) -> &'static str {
        match self {
            Language::Salesforce => "salesforce",
            Language::Node => "node",
            Language::Go => "go",
        }
    }

    /// Detects the language of the code in the given folder
    pub fn detect(folder: &Path) -> Option<Language> {
        if folder.join("sfdx-project.json").exists() {
            Some(Language::Salesforce)
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
        if !self.is_git_flow_initialized(repo)? {
            verbose!("Initializing git flow in repository {}", repo.display());
            self.git_run(repo, &["flow", "init", "-fd", "--tag", "v"])
                .map_err(|err| format!("Error while initializing git flow in repository {}: {err}", repo.display()))?;
            if !self.noop && !self.is_git_flow_initialized(repo)? {
                return Err("git flow was not installed properly, please install it manually".into());
            }
        }
        // Resetting the hooks folder, in case the repo was moved
        let hooks_path = repo.join(&self.hooks_dir);

        // 2/ configure git flow
        verbose!("Configuring gitflow");
        let hooks_path_str = hooks_path.to_string_lossy();
        let use_pull_requests = if self.use_pull_requests { "true" } else { "false" };
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
        for key in ["gitflow.allow-master-commit", "gitflow.allow-conflict-commit"] {
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
                fs::create_dir_all(&hooks_path)
                    .map_err(|err| format!("Error while creating hooks folder {}: {err}", hooks_path.display()))?;
            }
        }
        verbose!("Copying hooks");
        for folder in ["common", language.name()] {
            self.copy_hooks(folder, &hooks_path)
                .map_err(|err| format!("Error while copying {folder} hooks to {}: {err}", hooks_path.display()))?;
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

    /// Tells if git flow is initialized, git flow AVH sets gitflow.branch.master, git-flow-next sets gitflow.initialized
    fn is_git_flow_initialized(&self, repo: &Path) -> Result<bool, String> {
        Ok(!self.git_get(repo, &["config", "--local", "gitflow.branch.master"])?.is_empty()
            || self.git_get(repo, &["config", "--local", "--bool", "gitflow.initialized"])? == "true")
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
                        println!("Would copy {} to {}", entry.path().display(), destination.display());
                        continue;
                    }
                    fs::copy(entry.path(), &destination).map_err(|err| err.to_string())?;
                }
            }
            None => {
                let dir = HOOKS.get_dir(folder).ok_or_else(|| format!("No embedded hooks for {folder}"))?;
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
            println!("Would run: {} -C {} {}", self.git, repo.display(), args.join(" "));
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
            false => Err(format!("{} {} failed with {status}", self.git, args.join(" "))),
        }
    }

    fn git_config(&self, repo: &Path, key: &str, value: &str) -> Result<(), String> {
        self.git_run(repo, &["config", key, value])
    }
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
