use crate::api::models::{UpdateState, UpdateStatus};
use once_cell::sync::Lazy;
use parking_lot::Mutex;
use velopack::sources::GithubSource;
use velopack::{UpdateCheck, UpdateInfo, UpdateManager, VelopackApp};

static PENDING_UPDATE: Lazy<Mutex<Option<UpdateInfo>>> = Lazy::new(|| Mutex::new(None));

fn update_repository() -> Option<&'static str> {
    option_env!("GITFRONT_UPDATE_REPOSITORY").filter(|value| !value.trim().is_empty())
}

fn manager() -> Result<UpdateManager, String> {
    let repository = update_repository()
        .ok_or_else(|| "Updates are disabled in this development build.".to_owned())?;
    UpdateManager::new(GithubSource::new(repository, None, false), None, None)
        .map_err(|error| error.to_string())
}

pub fn check_for_update() -> Result<UpdateStatus, String> {
    let Some(_) = update_repository() else {
        return Ok(disabled_status());
    };
    let manager = match manager() {
        Ok(manager) => manager,
        Err(error) => {
            return Ok(UpdateStatus {
                state: UpdateState::NotInstalled,
                current_version: env!("CARGO_PKG_VERSION").to_owned(),
                available_version: None,
                release_notes_markdown: None,
                download_size: None,
                message: error,
            });
        }
    };
    let current = manager.get_current_version_as_string();
    match manager
        .check_for_updates()
        .map_err(|error| error.to_string())?
    {
        UpdateCheck::RemoteIsEmpty | UpdateCheck::NoUpdateAvailable => Ok(UpdateStatus {
            state: UpdateState::UpToDate,
            current_version: current,
            available_version: None,
            release_notes_markdown: None,
            download_size: None,
            message: "GitFront is up to date.".to_owned(),
        }),
        UpdateCheck::UpdateAvailable(update) => {
            let status = status_from_update(&current, &update, UpdateState::Available);
            *PENDING_UPDATE.lock() = Some(*update);
            Ok(status)
        }
    }
}

pub fn download_update() -> Result<UpdateStatus, String> {
    let manager = manager()?;
    let update = PENDING_UPDATE
        .lock()
        .clone()
        .ok_or_else(|| "Check for updates before downloading.".to_owned())?;
    manager
        .download_updates(&update, None)
        .map_err(|error| error.to_string())?;
    Ok(status_from_update(
        &manager.get_current_version_as_string(),
        &update,
        UpdateState::Downloaded,
    ))
}

pub fn apply_update_and_restart() -> Result<(), String> {
    let manager = manager()?;
    let update = PENDING_UPDATE
        .lock()
        .clone()
        .ok_or_else(|| "No downloaded update is ready.".to_owned())?;
    manager
        .apply_updates_and_restart(update)
        .map_err(|error| error.to_string())
}

fn status_from_update(current: &str, update: &UpdateInfo, state: UpdateState) -> UpdateStatus {
    let release = &update.TargetFullRelease;
    UpdateStatus {
        state,
        current_version: current.to_owned(),
        available_version: Some(release.Version.clone()),
        release_notes_markdown: (!release.NotesMarkdown.is_empty())
            .then(|| release.NotesMarkdown.clone()),
        download_size: Some(release.Size),
        message: format!("GitFront {} is available.", release.Version),
    }
}

fn disabled_status() -> UpdateStatus {
    UpdateStatus {
        state: UpdateState::Disabled,
        current_version: env!("CARGO_PKG_VERSION").to_owned(),
        available_version: None,
        release_notes_markdown: None,
        download_size: None,
        message: "Updates are disabled in this development build.".to_owned(),
    }
}

#[flutter_rust_bridge::frb(ignore)]
#[unsafe(no_mangle)]
pub extern "C" fn gitfront_velopack_bootstrap() {
    VelopackApp::build().run();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn development_build_reports_disabled_updates() {
        if update_repository().is_none() {
            assert_eq!(check_for_update().unwrap().state, UpdateState::Disabled);
        }
    }
}
