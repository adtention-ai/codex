use serde_json::{json, Value};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RenderedAd {
    pub title: String,
    pub prompt_line: String,
}

pub const LEARN_MORE_HINT: &str = "-> learn-more";

pub trait HttpClient {
    fn post(&self, url: &str, body: Option<&str>) -> Result<String, String>;
}

#[derive(Debug, Clone)]
pub struct RefreshConfig {
    pub cache_dir: PathBuf,
    pub api_base: String,
    pub cwd: PathBuf,
    pub transcript_path: Option<PathBuf>,
    pub hook_input: String,
    pub display_ttl_secs: u64,
    pub min_dwell_secs: u64,
    pub now: SystemTime,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RefreshOutcome {
    SkippedNoRender,
    SkippedDwell,
    NoPublisher,
    NoAd,
    Served { category: String, ad_text: String },
}

pub fn strip_terminal_controls(input: &str) -> String {
    input.chars().filter(|ch| !ch.is_control()).collect()
}

pub fn truncate_chars(input: &str, max_chars: usize) -> String {
    if max_chars == 0 {
        return String::new();
    }
    let len = input.chars().count();
    if len <= max_chars {
        return input.to_string();
    }
    if max_chars <= 3 {
        return ".".repeat(max_chars);
    }
    let keep = max_chars - 3;
    let mut out: String = input.chars().take(keep).collect();
    out.push_str("...");
    out
}

pub fn render_ad(
    balance_display: &str,
    ad_text: Option<&str>,
    max_title: usize,
    max_line: usize,
) -> RenderedAd {
    let balance = normalize_space(&strip_terminal_controls(balance_display));
    let balance = if balance.is_empty() {
        "⊕ $0.00".to_string()
    } else {
        balance
    };
    let ad = ad_text
        .map(strip_terminal_controls)
        .map(|s| normalize_space(&s))
        .map(|s| strip_existing_learn_more_hint(&s))
        .filter(|s| !s.is_empty());

    let title = match ad.as_deref() {
        Some(ad) => render_line_with_learn_more_hint(&balance, " · ", ad, max_title),
        None => balance.clone(),
    };
    let prompt_line = match ad.as_deref() {
        Some(ad) => render_line_with_learn_more_hint(&balance, "  ", ad, max_line),
        None => balance,
    };

    RenderedAd {
        title: truncate_chars(&title, max_title),
        prompt_line: truncate_chars(&prompt_line, max_line),
    }
}

fn strip_existing_learn_more_hint(ad: &str) -> String {
    ad.trim()
        .strip_suffix(LEARN_MORE_HINT)
        .map(str::trim_end)
        .unwrap_or_else(|| ad.trim())
        .to_string()
}

fn render_line_with_learn_more_hint(
    balance: &str,
    separator: &str,
    ad: &str,
    max_chars: usize,
) -> String {
    if max_chars == 0 {
        return String::new();
    }

    let prefix = format!("{balance}{separator}");
    let suffix = format!(" {LEARN_MORE_HINT}");
    let prefix_len = prefix.chars().count();
    let suffix_len = suffix.chars().count();

    if prefix_len + suffix_len >= max_chars {
        return truncate_chars(&format!("{prefix}{LEARN_MORE_HINT}"), max_chars);
    }

    let ad_max = max_chars - prefix_len - suffix_len;
    format!("{prefix}{}{suffix}", truncate_chars(ad, ad_max))
}

pub fn mark_render_seen(cache_dir: &Path, now: SystemTime) -> std::io::Result<()> {
    fs::create_dir_all(cache_dir)?;
    fs::write(
        cache_dir.join("last_render_seen"),
        unix_secs(now).to_string(),
    )
}

pub fn click_url_from_response(value: &Value) -> Option<String> {
    value
        .get("click_url")
        .and_then(Value::as_str)
        .filter(|url| !url.trim().is_empty())
        .map(|url| url.trim().to_string())
        .or_else(|| {
            value
                .get("impression_id")
                .and_then(Value::as_str)
                .filter(|id| !id.trim().is_empty())
                .map(|id| format!("/v1/click/{}", strip_terminal_controls(id.trim())))
        })
}

pub fn resolve_open_url(input: &str, api_base: &str) -> Option<String> {
    let input = input.trim();
    if input.starts_with("https://") || input.starts_with("http://") {
        return Some(strip_terminal_controls(input));
    }
    if input.starts_with('/') && !input.starts_with("//") {
        return Some(format!(
            "{}{}",
            api_base.trim_end_matches('/'),
            strip_terminal_controls(input)
        ));
    }
    None
}

pub fn sanitize_ref_code(input: &str) -> String {
    let mut out = String::new();
    for ch in input.chars().flat_map(char::to_lowercase) {
        if ch.is_ascii_lowercase() || ch.is_ascii_digit() {
            out.push(ch);
            if out.len() >= 32 {
                break;
            }
        }
    }
    out
}

pub fn ref_code_from_values(env_ref: Option<&str>, file_ref: Option<&str>) -> Option<String> {
    env_ref
        .filter(|s| !s.trim().is_empty())
        .or(file_ref)
        .map(sanitize_ref_code)
        .filter(|s| !s.is_empty())
}

pub fn read_ref_code(cache_dir: &Path) -> Option<String> {
    let env_ref = env::var("ADTENTION_REF").ok();
    let file_ref = fs::read_to_string(cache_dir.join("ref")).ok();
    ref_code_from_values(env_ref.as_deref(), file_ref.as_deref())
}

pub fn mark_display_seen(cache_dir: &Path, now: SystemTime) -> std::io::Result<()> {
    mark_render_seen(cache_dir, now)
}

pub fn render_is_fresh(cache_dir: &Path, now: SystemTime, ttl_secs: u64) -> bool {
    heartbeat_is_fresh(cache_dir, "last_render_seen", now, ttl_secs)
}

pub fn display_is_fresh(cache_dir: &Path, now: SystemTime, ttl_secs: u64) -> bool {
    render_is_fresh(cache_dir, now, ttl_secs)
}

fn heartbeat_is_fresh(cache_dir: &Path, file_name: &str, now: SystemTime, ttl_secs: u64) -> bool {
    let path = cache_dir.join(file_name);
    let modified = match fs::metadata(&path).and_then(|m| m.modified()) {
        Ok(modified) => modified,
        Err(_) => return false,
    };
    match now.duration_since(modified) {
        Ok(age) => age.as_secs() <= ttl_secs,
        Err(_) => true,
    }
}

pub fn should_attempt_serve(
    cache_dir: &Path,
    now: SystemTime,
    render_ttl_secs: u64,
    min_dwell_secs: u64,
) -> bool {
    if !render_is_fresh(cache_dir, now, render_ttl_secs) {
        return false;
    }

    let last_serve = fs::read_to_string(cache_dir.join("last_serve"))
        .ok()
        .and_then(|s| s.trim().parse::<u64>().ok())
        .unwrap_or(0);
    let now_secs = unix_secs(now);
    now_secs.saturating_sub(last_serve) >= min_dwell_secs
}

pub fn refresh_once<C: HttpClient>(config: &RefreshConfig, client: &C) -> RefreshOutcome {
    if fs::create_dir_all(&config.cache_dir).is_err() {
        return RefreshOutcome::NoAd;
    }

    if !render_is_fresh(&config.cache_dir, config.now, config.display_ttl_secs) {
        let _ = fs::write(config.cache_dir.join("last_skipped"), "no_render");
        return RefreshOutcome::SkippedNoRender;
    }

    if !should_attempt_serve(
        &config.cache_dir,
        config.now,
        config.display_ttl_secs,
        config.min_dwell_secs,
    ) {
        let _ = fs::write(config.cache_dir.join("last_skipped"), "dwell");
        return RefreshOutcome::SkippedDwell;
    }

    let (category, source) = classify(config);
    let mut publisher_id = read_publisher_id(&config.cache_dir);
    if publisher_id.is_none() {
        let ref_code = read_ref_code(&config.cache_dir);
        match register(config, client, ref_code.as_deref()) {
            Ok(body) => {
                let _ = fs::write(config.cache_dir.join("identity.json"), &body);
                publisher_id = publisher_id_from_json(&body);
                if publisher_id.is_some() {
                    let _ = fs::remove_file(config.cache_dir.join("ref"));
                }
            }
            Err(_) => return RefreshOutcome::NoPublisher,
        }
    }
    let Some(mut publisher_id) = publisher_id else {
        return RefreshOutcome::NoPublisher;
    };

    let now_secs = unix_secs(config.now);
    let _ = fs::write(config.cache_dir.join("last_serve"), now_secs.to_string());
    let mut response = serve(config, client, &publisher_id, &category, now_secs, "");

    if response
        .as_deref()
        .unwrap_or_default()
        .contains("unknown_publisher")
    {
        match register(config, client, None) {
            Ok(body) => {
                let _ = fs::write(config.cache_dir.join("identity.json"), &body);
                if let Some(id) = publisher_id_from_json(&body) {
                    publisher_id = id;
                    response = serve(config, client, &publisher_id, &category, now_secs, "-r");
                }
            }
            Err(_) => return RefreshOutcome::NoPublisher,
        }
    }

    let Some(body) = response else {
        return RefreshOutcome::NoAd;
    };
    let value: Value = serde_json::from_str(&body).unwrap_or(Value::Null);
    let ad_text = value
        .get("text")
        .and_then(Value::as_str)
        .map(strip_terminal_controls)
        .map(|s| normalize_space(&s))
        .unwrap_or_default();

    write_balance_files(&config.cache_dir, value.get("balance_usd"));

    if ad_text.is_empty() {
        let _ = fs::write(config.cache_dir.join("current_ad.txt"), "");
        let _ = fs::write(config.cache_dir.join("current_click.txt"), "");
        return RefreshOutcome::NoAd;
    }

    let balance_display = fs::read_to_string(config.cache_dir.join("balance_display"))
        .unwrap_or_else(|_| "⊕ $0.00".to_string());
    let rendered = render_ad(&balance_display, Some(&ad_text), 80, 160);

    let _ = fs::write(config.cache_dir.join("current_ad.txt"), &ad_text);
    let click_url = click_url_from_response(&value).unwrap_or_default();
    let _ = fs::write(config.cache_dir.join("current_click.txt"), click_url);
    let _ = fs::write(config.cache_dir.join("category.txt"), &category);
    let _ = fs::write(config.cache_dir.join("source.txt"), &source);
    let _ = fs::write(config.cache_dir.join("title.txt"), rendered.title);
    let _ = fs::write(
        config.cache_dir.join("prompt_line.txt"),
        rendered.prompt_line,
    );
    let _ = fs::write(
        config.cache_dir.join("terminal.txt"),
        format!(
            "{}\n{}\n",
            fs::read_to_string(config.cache_dir.join("title.txt")).unwrap_or_default(),
            fs::read_to_string(config.cache_dir.join("prompt_line.txt")).unwrap_or_default()
        ),
    );
    let _ = append_impression(&config.cache_dir, now_secs, &source, &category, &ad_text);

    RefreshOutcome::Served { category, ad_text }
}

fn register<C: HttpClient>(
    config: &RefreshConfig,
    client: &C,
    ref_code: Option<&str>,
) -> Result<String, String> {
    let body = ref_code.map(|ref_code| json!({ "ref": ref_code }).to_string());
    client.post(
        &format!("{}/v1/register", config.api_base.trim_end_matches('/')),
        body.as_deref(),
    )
}

fn serve<C: HttpClient>(
    config: &RefreshConfig,
    client: &C,
    publisher_id: &str,
    category: &str,
    now_secs: u64,
    nonce_suffix: &str,
) -> Option<String> {
    let nonce = format!("{now_secs}-codex{nonce_suffix}");
    let body = json!({
        "publisher_id": publisher_id,
        "category": category,
        "nonce": nonce
    })
    .to_string();
    client
        .post(
            &format!("{}/v1/serve", config.api_base.trim_end_matches('/')),
            Some(&body),
        )
        .ok()
}

fn read_publisher_id(cache_dir: &Path) -> Option<String> {
    let body = fs::read_to_string(cache_dir.join("identity.json")).ok()?;
    publisher_id_from_json(&body)
}

fn publisher_id_from_json(body: &str) -> Option<String> {
    serde_json::from_str::<Value>(body)
        .ok()
        .and_then(|v| {
            v.get("publisher_id")
                .and_then(Value::as_str)
                .map(str::to_string)
        })
        .filter(|s| !s.is_empty())
}

fn write_balance_files(cache_dir: &Path, balance: Option<&Value>) {
    let Some(balance) = balance else {
        return;
    };
    let amount = match balance {
        Value::Number(n) => n.as_f64(),
        Value::String(s) => s.parse::<f64>().ok(),
        _ => None,
    };
    if let Some(amount) = amount {
        let _ = fs::write(cache_dir.join("balance"), amount.to_string());
        let _ = fs::write(cache_dir.join("balance_display"), format!("⊕ ${amount:.2}"));
    }
}

fn append_impression(
    cache_dir: &Path,
    now_secs: u64,
    source: &str,
    category: &str,
    ad_text: &str,
) -> std::io::Result<()> {
    use std::io::Write;
    let mut file = fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(cache_dir.join("impressions.log"))?;
    writeln!(file, "{now_secs}\t{source}\t{category}\t{ad_text}")
}

fn classify(config: &RefreshConfig) -> (String, String) {
    if let Some(category) = classify_topic(config) {
        return (category, "topic".to_string());
    }
    (classify_folder(&config.cwd), "folder".to_string())
}

fn classify_topic(config: &RefreshConfig) -> Option<String> {
    let mut text = String::new();
    if let Some(prompt) = prompt_from_hook(&config.hook_input) {
        text.push_str(&prompt);
    }
    if let Some(path) = &config.transcript_path {
        if let Ok(body) = fs::read_to_string(path) {
            text.push('\n');
            text.push_str(&tail_chars(&body, 20_000));
        }
    }
    let text = text.to_lowercase();
    if text.trim().is_empty() {
        return None;
    }
    let scores = [
        (
            "web3",
            count_any(
                &text,
                &[
                    "solidity",
                    "ethereum",
                    "web3",
                    "smart contract",
                    "defi",
                    "onchain",
                    "blockchain",
                    "wallet",
                    "stablecoin",
                    "crypto",
                    "erc-20",
                    "erc20",
                ],
            ),
        ),
        (
            "web",
            count_any(
                &text,
                &[
                    "react",
                    "tailwind",
                    "next.js",
                    "frontend",
                    "vite",
                    "jsx",
                    "tsx",
                    "css",
                    "component",
                ],
            ),
        ),
        (
            "devops",
            count_any(
                &text,
                &[
                    "docker",
                    "kubernetes",
                    "terraform",
                    "kubectl",
                    "nginx",
                    "ci/cd",
                    "pipeline",
                    "deployment",
                ],
            ),
        ),
        (
            "data",
            count_any(
                &text,
                &[
                    "dataset",
                    "training data",
                    "pandas",
                    "embedding",
                    "inference",
                    "fine-tune",
                    "gpu",
                    "machine learning",
                ],
            ),
        ),
        (
            "systems",
            count_any(
                &text,
                &[
                    "goroutine",
                    "borrow checker",
                    "mutex",
                    "concurrency",
                    "memory safety",
                    "rustc",
                ],
            ),
        ),
    ];
    scores
        .into_iter()
        .max_by_key(|(_, score)| *score)
        .and_then(|(category, score)| {
            if score > 0 {
                Some(category.to_string())
            } else {
                None
            }
        })
}

fn prompt_from_hook(input: &str) -> Option<String> {
    let value: Value = serde_json::from_str(input).ok()?;
    for key in [
        "prompt",
        "user_prompt",
        "userPrompt",
        "message",
        "input",
        "text",
    ] {
        if let Some(text) = value.get(key).and_then(Value::as_str) {
            if !text.is_empty() {
                return Some(text.to_string());
            }
        }
    }
    None
}

fn classify_folder(cwd: &Path) -> String {
    let has = |name: &str| cwd.join(name).exists();
    if has("foundry.toml") || glob_ext(cwd, "sol") || glob_prefix(cwd, "hardhat.config.") {
        return "web3".to_string();
    }
    if has("Dockerfile") || glob_ext(cwd, "tf") {
        return "devops".to_string();
    }
    if has("package.json") {
        return "web".to_string();
    }
    if has("requirements.txt") || glob_ext(cwd, "py") {
        return "data".to_string();
    }
    if has("Cargo.toml") || has("go.mod") {
        return "systems".to_string();
    }
    "general".to_string()
}

fn glob_ext(cwd: &Path, ext: &str) -> bool {
    fs::read_dir(cwd)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .any(|entry| entry.path().extension().and_then(|s| s.to_str()) == Some(ext))
}

fn glob_prefix(cwd: &Path, prefix: &str) -> bool {
    fs::read_dir(cwd)
        .ok()
        .into_iter()
        .flatten()
        .flatten()
        .any(|entry| {
            entry
                .file_name()
                .to_str()
                .map(|s| s.starts_with(prefix))
                .unwrap_or(false)
        })
}

fn count_any(text: &str, needles: &[&str]) -> usize {
    needles
        .iter()
        .map(|needle| text.matches(needle).count())
        .sum()
}

fn tail_chars(input: &str, max_chars: usize) -> String {
    let len = input.chars().count();
    if len <= max_chars {
        return input.to_string();
    }
    input.chars().skip(len - max_chars).collect()
}

fn normalize_space(input: &str) -> String {
    let mut out = String::new();
    let mut last_was_space = false;
    for ch in input.chars() {
        if ch.is_whitespace() {
            if !last_was_space {
                out.push(' ');
                last_was_space = true;
            }
        } else {
            out.push(ch);
            last_was_space = false;
        }
    }
    out.trim().to_string()
}

fn unix_secs(t: SystemTime) -> u64 {
    t.duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::sync::Mutex;
    use std::time::{Duration, UNIX_EPOCH};

    static TEMP_COUNTER: AtomicU64 = AtomicU64::new(0);

    fn temp_dir() -> PathBuf {
        let mut dir = std::env::temp_dir();
        dir.push(format!(
            "adtention-codex-test-{}-{}",
            std::process::id(),
            TEMP_COUNTER.fetch_add(1, Ordering::SeqCst)
        ));
        fs::create_dir_all(&dir).unwrap();
        dir
    }

    #[test]
    fn render_ad_strips_terminal_control_sequences() {
        let rendered = render_ad(
            "⊕ $1.23",
            Some("Neon\u{1b}]0;pwned\u{7}\nPostgres"),
            80,
            120,
        );

        assert_eq!(
            rendered.title,
            "⊕ $1.23 · Neon]0;pwnedPostgres -> learn-more"
        );
        assert_eq!(
            rendered.prompt_line,
            "⊕ $1.23  Neon]0;pwnedPostgres -> learn-more"
        );
        assert!(!rendered.title.contains('\u{1b}'));
        assert!(!rendered.title.contains('\u{7}'));
        assert!(!rendered.title.contains('\n'));
    }

    #[test]
    fn render_ad_keeps_learn_more_hint_when_truncating() {
        let rendered = render_ad("⊕ $1.23", Some("Déployez 🚀 maintenant"), 35, 36);

        assert_eq!(rendered.title, "⊕ $1.23 · Déployez... -> learn-more");
        assert_eq!(
            rendered.prompt_line,
            "⊕ $1.23  Déployez 🚀... -> learn-more"
        );
    }

    #[test]
    fn render_ad_does_not_duplicate_learn_more_hint() {
        let rendered = render_ad("⊕ $1.23", Some("Neon -> learn-more"), 80, 120);

        assert_eq!(rendered.title, "⊕ $1.23 · Neon -> learn-more");
        assert_eq!(rendered.prompt_line, "⊕ $1.23  Neon -> learn-more");
    }

    #[test]
    fn missing_ad_renders_balance_only() {
        let rendered = render_ad("⊕ $0.00", None, 80, 120);

        assert_eq!(rendered.title, "⊕ $0.00");
        assert_eq!(rendered.prompt_line, "⊕ $0.00");
    }

    #[test]
    fn render_heartbeat_records_supplied_time() {
        let tmp = temp_dir();
        let now = UNIX_EPOCH + Duration::from_secs(1_234);

        mark_render_seen(&tmp, now).unwrap();

        assert_eq!(
            fs::read_to_string(tmp.join("last_render_seen")).unwrap(),
            "1234"
        );
    }

    #[test]
    fn click_url_prefers_server_url_and_falls_back_to_click_route() {
        let with_click = serde_json::json!({
            "text": "Sponsor",
            "click_url": "https://example.com/click"
        });
        assert_eq!(
            click_url_from_response(&with_click).as_deref(),
            Some("https://example.com/click")
        );

        let with_impression = serde_json::json!({
            "text": "Sponsor",
            "impression_id": "imp_123"
        });
        assert_eq!(
            click_url_from_response(&with_impression).as_deref(),
            Some("/v1/click/imp_123")
        );
    }

    #[test]
    fn resolve_open_url_accepts_http_and_relative_click_paths_only() {
        assert_eq!(
            resolve_open_url("https://example.com", "https://api.adtention.ai").as_deref(),
            Some("https://example.com")
        );
        assert_eq!(
            resolve_open_url("/v1/click/imp_123", "https://api.adtention.ai/").as_deref(),
            Some("https://api.adtention.ai/v1/click/imp_123")
        );
        assert_eq!(
            resolve_open_url("javascript:alert(1)", "https://api.adtention.ai"),
            None
        );
        assert_eq!(
            resolve_open_url("//example.com", "https://api.adtention.ai"),
            None
        );
    }

    #[test]
    fn referral_codes_are_sanitized_and_env_takes_precedence() {
        assert_eq!(sanitize_ref_code("ABC-123_!!"), "abc123");
        assert_eq!(
            sanitize_ref_code("abcdefghijklmnopqrstuvwxyz1234567890"),
            "abcdefghijklmnopqrstuvwxyz123456"
        );
        assert_eq!(
            ref_code_from_values(Some("ENV-1"), Some("file-2")).as_deref(),
            Some("env1")
        );
        assert_eq!(
            ref_code_from_values(None, Some("file-2")).as_deref(),
            Some("file2")
        );
        assert_eq!(ref_code_from_values(Some("!!!"), Some("file-2")), None);
    }

    #[test]
    fn serve_is_blocked_without_fresh_render() {
        let tmp = temp_dir();
        let now = UNIX_EPOCH + Duration::from_secs(1_000);

        assert!(!should_attempt_serve(&tmp, now, 120, 15));
    }

    #[test]
    fn serve_is_allowed_with_fresh_render_and_dwell_elapsed() {
        let tmp = temp_dir();
        let now = SystemTime::now();

        mark_render_seen(&tmp, now).unwrap();
        fs::write(tmp.join("last_serve"), "0").unwrap();

        assert!(should_attempt_serve(&tmp, SystemTime::now(), 120, 15));
    }

    #[test]
    fn serve_is_blocked_inside_minimum_dwell_window() {
        let tmp = temp_dir();
        let now = SystemTime::now();
        mark_render_seen(&tmp, now).unwrap();
        let now_secs = now.duration_since(UNIX_EPOCH).unwrap().as_secs();
        fs::write(tmp.join("last_serve"), now_secs.to_string()).unwrap();

        assert!(!should_attempt_serve(&tmp, SystemTime::now(), 120, 15));
    }

    struct MockHttp {
        calls: Mutex<Vec<(String, Option<String>)>>,
        responses: Mutex<Vec<Result<String, String>>>,
    }

    impl MockHttp {
        fn new(responses: Vec<Result<String, String>>) -> Self {
            Self {
                calls: Mutex::new(Vec::new()),
                responses: Mutex::new(responses),
            }
        }

        fn calls(&self) -> Vec<(String, Option<String>)> {
            self.calls.lock().unwrap().clone()
        }
    }

    impl HttpClient for MockHttp {
        fn post(&self, url: &str, body: Option<&str>) -> Result<String, String> {
            self.calls
                .lock()
                .unwrap()
                .push((url.to_string(), body.map(str::to_string)));
            self.responses.lock().unwrap().remove(0)
        }
    }

    fn refresh_config(cache_dir: PathBuf) -> RefreshConfig {
        RefreshConfig {
            cache_dir,
            api_base: "http://127.0.0.1:9".to_string(),
            cwd: std::env::current_dir().unwrap(),
            transcript_path: None,
            hook_input: r#"{"prompt":"Please improve this React component"}"#.to_string(),
            display_ttl_secs: 120,
            min_dwell_secs: 15,
            now: SystemTime::now(),
        }
    }

    #[test]
    fn refresh_skips_all_backend_calls_without_render_heartbeat() {
        let tmp = temp_dir();
        let http = MockHttp::new(vec![]);
        let outcome = refresh_once(&refresh_config(tmp), &http);

        assert_eq!(outcome, RefreshOutcome::SkippedNoRender);
        assert!(http.calls().is_empty());
    }

    #[test]
    fn refresh_registers_and_serves_after_fresh_render() {
        let tmp = temp_dir();
        mark_render_seen(&tmp, SystemTime::now()).unwrap();
        let http = MockHttp::new(vec![
            Ok(r#"{"publisher_id":"pub_123"}"#.to_string()),
            Ok(r#"{"text":"Neon Postgres for AI apps","balance_usd":1.23,"click_url":"https://neon.tech/adtention"}"#.to_string()),
        ]);

        let outcome = refresh_once(&refresh_config(tmp.clone()), &http);

        assert_eq!(
            outcome,
            RefreshOutcome::Served {
                category: "web".to_string(),
                ad_text: "Neon Postgres for AI apps".to_string()
            }
        );
        let calls = http.calls();
        assert_eq!(calls.len(), 2);
        assert!(calls[0].0.ends_with("/v1/register"));
        assert!(calls[1].0.ends_with("/v1/serve"));
        assert!(calls[1].1.as_ref().unwrap().contains(r#""category":"web""#));
        assert!(!calls[1].1.as_ref().unwrap().contains("viewability"));
        assert_eq!(
            fs::read_to_string(tmp.join("title.txt")).unwrap(),
            "⊕ $1.23 · Neon Postgres for AI apps -> learn-more"
        );
        assert_eq!(
            fs::read_to_string(tmp.join("prompt_line.txt")).unwrap(),
            "⊕ $1.23  Neon Postgres for AI apps -> learn-more"
        );
        assert_eq!(
            fs::read_to_string(tmp.join("terminal.txt")).unwrap(),
            "⊕ $1.23 · Neon Postgres for AI apps -> learn-more\n⊕ $1.23  Neon Postgres for AI apps -> learn-more\n"
        );
        assert_eq!(
            fs::read_to_string(tmp.join("current_click.txt")).unwrap(),
            "https://neon.tech/adtention"
        );
    }

    #[test]
    fn refresh_sends_ref_on_first_registration_and_consumes_file() {
        let tmp = temp_dir();
        std::env::remove_var("ADTENTION_REF");
        mark_render_seen(&tmp, SystemTime::now()).unwrap();
        fs::write(tmp.join("ref"), "ABC-123_!!").unwrap();
        let http = MockHttp::new(vec![
            Ok(r#"{"publisher_id":"pub_ref"}"#.to_string()),
            Ok(r#"{"text":"Referral sponsor","balance_usd":1.0}"#.to_string()),
        ]);

        let outcome = refresh_once(&refresh_config(tmp.clone()), &http);

        assert!(matches!(outcome, RefreshOutcome::Served { .. }));
        let calls = http.calls();
        assert_eq!(calls[0].0, "http://127.0.0.1:9/v1/register");
        assert_eq!(calls[0].1.as_deref(), Some(r#"{"ref":"abc123"}"#));
        assert!(!tmp.join("ref").exists());
    }

    #[test]
    fn refresh_reuses_existing_publisher_id() {
        let tmp = temp_dir();
        mark_render_seen(&tmp, SystemTime::now()).unwrap();
        fs::write(
            tmp.join("identity.json"),
            r#"{"publisher_id":"pub_cached"}"#,
        )
        .unwrap();
        let http = MockHttp::new(vec![Ok(
            r#"{"text":"Cached publisher ad","balance_usd":2.0}"#.to_string(),
        )]);

        let outcome = refresh_once(&refresh_config(tmp), &http);

        assert!(matches!(outcome, RefreshOutcome::Served { .. }));
        let calls = http.calls();
        assert_eq!(calls.len(), 1);
        assert!(calls[0].0.ends_with("/v1/serve"));
        assert!(calls[0]
            .1
            .as_ref()
            .unwrap()
            .contains(r#""publisher_id":"pub_cached""#));
    }

    #[test]
    fn refresh_derives_click_url_from_impression_id() {
        let tmp = temp_dir();
        mark_render_seen(&tmp, SystemTime::now()).unwrap();
        fs::write(
            tmp.join("identity.json"),
            r#"{"publisher_id":"pub_cached"}"#,
        )
        .unwrap();
        let http = MockHttp::new(vec![Ok(
            r#"{"text":"Derived click ad","balance_usd":2.0,"impression_id":"imp_456"}"#
                .to_string(),
        )]);

        let outcome = refresh_once(&refresh_config(tmp.clone()), &http);

        assert!(matches!(outcome, RefreshOutcome::Served { .. }));
        assert_eq!(
            fs::read_to_string(tmp.join("current_click.txt")).unwrap(),
            "/v1/click/imp_456"
        );
    }
}
