use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("GitFront sequence editor: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let mut args = env::args().skip(1);
    let mode = args.next().ok_or_else(|| "missing mode".to_owned())?;
    let target = args
        .next()
        .ok_or_else(|| "missing Git editor file".to_owned())?;
    let session = env::var("GITFRONT_REBASE_SESSION")
        .map(PathBuf::from)
        .map_err(|_| "missing GITFRONT_REBASE_SESSION".to_owned())?;
    match mode.as_str() {
        "sequence" => {
            fs::copy(session.join("todo.txt"), target).map_err(|error| error.to_string())?;
        }
        "message" => {
            let messages = fs::read(session.join("messages.bin")).unwrap_or_default();
            let messages: Vec<&[u8]> = messages.split(|byte| *byte == 0).collect();
            let counter_path = session.join("message-index");
            let index = fs::read_to_string(&counter_path)
                .ok()
                .and_then(|value| value.trim().parse::<usize>().ok())
                .unwrap_or(0);
            if let Some(message) = messages.get(index).filter(|message| !message.is_empty()) {
                fs::write(target, message).map_err(|error| error.to_string())?;
            }
            fs::write(counter_path, (index + 1).to_string()).map_err(|error| error.to_string())?;
        }
        _ => return Err(format!("unknown mode: {mode}")),
    }
    Ok(())
}
