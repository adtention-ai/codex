use adtention_codex::{
    mark_render_seen, mark_viewable_seen, refresh_once, render_ad, HttpClient, RefreshConfig,
};
use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::path::PathBuf;
use std::process::Command;
use std::thread;
use std::time::{Duration, SystemTime};

struct CurlHttp;

impl HttpClient for CurlHttp {
    fn post(&self, url: &str, body: Option<&str>) -> Result<String, String> {
        let mut cmd = Command::new("curl");
        cmd.args(["-s", "-m", "5", "-X", "POST", url]);
        if let Some(body) = body {
            cmd.args(["-H", "content-type: application/json", "-d", body]);
        }
        let output = cmd.output().map_err(|err| err.to_string())?;
        if !output.status.success() {
            return Err(format!("curl exited with {}", output.status));
        }
        Ok(String::from_utf8_lossy(&output.stdout).to_string())
    }
}

fn main() {
    let mut args = env::args().skip(1);
    let Some(command) = args.next() else {
        print_usage_and_exit();
    };

    let code = match command.as_str() {
        "setup" => setup().map(|_| 0).unwrap_or(0),
        "refresh" => {
            let cwd = args
                .next()
                .map(PathBuf::from)
                .unwrap_or_else(|| env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
            let transcript_path = args.next().filter(|s| !s.is_empty()).map(PathBuf::from);
            refresh(cwd, transcript_path).map(|_| 0).unwrap_or(0)
        }
        "render" => render().map(|_| 0).unwrap_or(0),
        "mark-display" | "mark-render" => mark_render_seen(&cache_dir(), SystemTime::now())
            .map(|_| 0)
            .unwrap_or(0),
        "mark-viewable" => {
            let source = args.next().unwrap_or_else(|| "manual-helper".to_string());
            mark_viewable_seen(&cache_dir(), &source, SystemTime::now())
                .map(|_| 0)
                .unwrap_or(0)
        }
        "title-daemon" => {
            let interval = parse_env_u64("ADTENTION_TITLE_INTERVAL", 15).max(5);
            title_daemon(interval).map(|_| 0).unwrap_or(0)
        }
        _ => {
            eprintln!("unknown command: {command}");
            2
        }
    };
    std::process::exit(code);
}

fn setup() -> io::Result<()> {
    let cache = cache_dir();
    fs::create_dir_all(&cache)?;
    write_if_missing(cache.join("balance_display"), "⊕ $0.00")?;
    write_if_missing(cache.join("title.txt"), "⊕ $0.00")?;
    write_if_missing(cache.join("prompt_line.txt"), "⊕ $0.00")?;
    write_if_missing(cache.join("terminal.txt"), "⊕ $0.00\n⊕ $0.00\n")?;
    Ok(())
}

fn refresh(cwd: PathBuf, transcript_path: Option<PathBuf>) -> io::Result<()> {
    let mut hook_input = String::new();
    let _ = io::stdin().read_to_string(&mut hook_input);
    let config = RefreshConfig {
        cache_dir: cache_dir(),
        api_base: env::var("ADTENTION_API")
            .unwrap_or_else(|_| "https://api.adtention.ai".to_string()),
        cwd,
        transcript_path,
        hook_input,
        display_ttl_secs: parse_env_u64("ADTENTION_DISPLAY_TTL", 120),
        viewability_ttl_secs: parse_env_u64("ADTENTION_VIEWABILITY_TTL", 120),
        min_dwell_secs: parse_env_u64("ADTENTION_MIN_DWELL", 15),
        now: SystemTime::now(),
    };
    let _ = refresh_once(&config, &CurlHttp);
    Ok(())
}

fn render() -> io::Result<()> {
    let cache = cache_dir();
    let balance =
        fs::read_to_string(cache.join("balance_display")).unwrap_or_else(|_| "⊕ $0.00".to_string());
    let ad = fs::read_to_string(cache.join("current_ad.txt")).ok();
    let max_width = parse_env_usize("ADTENTION_MAX_WIDTH", columns().unwrap_or(120));
    let rendered = render_ad(&balance, ad.as_deref(), 80, max_width);
    fs::write(cache.join("title.txt"), &rendered.title).ok();
    fs::write(cache.join("prompt_line.txt"), &rendered.prompt_line).ok();
    fs::write(
        cache.join("terminal.txt"),
        format!("{}\n{}\n", rendered.title, rendered.prompt_line),
    )
    .ok();
    mark_render_seen(&cache, SystemTime::now()).ok();
    println!("{}", rendered.prompt_line);
    Ok(())
}

fn title_daemon(interval_secs: u64) -> io::Result<()> {
    let cache = cache_dir();
    loop {
        let title = fs::read_to_string(cache.join("title.txt"))
            .or_else(|_| fs::read_to_string(cache.join("balance_display")))
            .unwrap_or_else(|_| "⊕ $0.00".to_string());
        let title = title.trim();
        if !title.is_empty() {
            print!("\x1b]0;{title}\x07");
            let _ = io::stdout().flush();
            let _ = mark_render_seen(&cache, SystemTime::now());
        }
        thread::sleep(Duration::from_secs(interval_secs));
    }
}

fn cache_dir() -> PathBuf {
    env::var_os("ADTENTION_CACHE")
        .or_else(|| env::var_os("PLUGIN_DATA"))
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = env::var_os("HOME")
                .map(PathBuf::from)
                .unwrap_or_else(|| PathBuf::from("."));
            home.join(".codex").join("adtention")
        })
}

fn write_if_missing(path: PathBuf, contents: &str) -> io::Result<()> {
    if !path.exists() {
        fs::write(path, contents)?;
    }
    Ok(())
}

fn parse_env_u64(name: &str, default: u64) -> u64 {
    env::var(name)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(default)
}

fn parse_env_usize(name: &str, default: usize) -> usize {
    env::var(name)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(default)
}

fn columns() -> Option<usize> {
    env::var("COLUMNS").ok().and_then(|s| s.parse().ok())
}

fn print_usage_and_exit() -> ! {
    eprintln!(
        "usage: adtention-codex <setup|refresh|render|mark-render|mark-viewable|title-daemon>"
    );
    std::process::exit(2);
}
