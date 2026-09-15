use rust_lib_gitfront_preview::api::git::{
    open_repository_paged, query_commits, refresh_repository_paged,
};
use rust_lib_gitfront_preview::api::models::{HistoryQuery, HistoryScope};
use std::env;
use std::time::Instant;

fn main() {
    let paths = env::args().skip(1).collect::<Vec<_>>();
    if paths.is_empty() {
        eprintln!("usage: gitfront_startup_probe <repository>...");
        std::process::exit(2);
    }

    for path in paths {
        if let Err(error) = probe(&path) {
            eprintln!("repository={path}\terror={error}");
        }
    }
}

fn probe(path: &str) -> Result<(), String> {
    let started = Instant::now();
    let opened = open_repository_paged(path.to_owned(), 250)?;
    let overview_ms = started.elapsed().as_millis();

    let started = Instant::now();
    let history = query_commits(
        opened.snapshot.workdir.clone(),
        HistoryQuery {
            scope: HistoryScope::CurrentBranch,
            selected_ref: None,
            text: String::new(),
            path: None,
        },
        None,
        200,
    )?;
    let history_ms = started.elapsed().as_millis();

    let started = Instant::now();
    let refreshed = refresh_repository_paged(opened.snapshot.workdir.clone(), 250)?;
    let warm_refresh_ms = started.elapsed().as_millis();

    println!(
        "repository={}\toverview_ms={}\thistory_ms={}\twarm_refresh_ms={}\tchanges={}\tbranches={}\tknown_commits={}\tfirst_history_page={}",
        opened.snapshot.workdir,
        overview_ms,
        history_ms,
        warm_refresh_ms,
        opened.changes.total_files,
        refreshed.branches.total_branches,
        history.matched_count,
        history.commits.len(),
    );
    Ok(())
}
