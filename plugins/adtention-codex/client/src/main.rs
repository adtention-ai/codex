use adtention_codex::{
    evaluate_viewability, mark_render_seen, mark_viewable_seen, refresh_once, render_ad,
    visible_ratio_for_rect, write_viewability_decision, HttpClient, RefreshConfig,
    ViewabilityDecision, ViewabilitySample,
};
use std::env;
use std::fs;
use std::io::{self, Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, Instant, SystemTime};

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
        "viewability-check" => {
            let target = args.next().unwrap_or_else(target_app_name);
            let min_ratio = parse_env_f64("ADTENTION_MIN_VISIBLE_RATIO", 0.5);
            let decision = probe_viewability(&target, min_ratio);
            let ok = write_viewability_decision(&cache_dir(), &decision, SystemTime::now())
                .unwrap_or(false);
            if ok {
                0
            } else {
                1
            }
        }
        "viewability-daemon" => {
            let target = args.next().unwrap_or_else(target_app_name);
            let interval = parse_env_u64("ADTENTION_VIEWABILITY_INTERVAL", 5).max(2);
            viewability_daemon(&target, interval)
                .map(|_| 0)
                .unwrap_or(0)
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
        }
        thread::sleep(Duration::from_secs(interval_secs));
    }
}

fn viewability_daemon(target_app: &str, interval_secs: u64) -> io::Result<()> {
    let cache = cache_dir();
    let min_ratio = parse_env_f64("ADTENTION_MIN_VISIBLE_RATIO", 0.5);
    loop {
        let decision = probe_viewability(target_app, min_ratio);
        let _ = write_viewability_decision(&cache, &decision, SystemTime::now());
        thread::sleep(Duration::from_secs(interval_secs));
    }
}

fn probe_viewability(target_app: &str, min_visible_ratio: f64) -> ViewabilityDecision {
    #[cfg(target_os = "macos")]
    {
        return probe_macos(target_app, min_visible_ratio);
    }
    #[cfg(target_os = "windows")]
    {
        return probe_windows(target_app, min_visible_ratio);
    }
    #[cfg(all(unix, not(target_os = "macos")))]
    {
        return probe_linux(target_app, min_visible_ratio);
    }
    #[allow(unreachable_code)]
    ViewabilityDecision::Unavailable {
        source: "unknown-viewability-helper".to_string(),
        reason: "unsupported_os".to_string(),
    }
}

#[cfg(target_os = "macos")]
fn probe_macos(target_app: &str, min_visible_ratio: f64) -> ViewabilityDecision {
    let source = "macos-frontmost-helper";
    let script = format!(
        r#"tell application "System Events"
set frontApp to name of first application process whose frontmost is true
set hasWindow to false
set notMinimized to false
set winX to 0
set winY to 0
set winW to 0
set winH to 0
set screenX to 0
set screenY to 0
set screenW to 0
set screenH to 0
try
  tell application "Finder" to set desktopBounds to bounds of window of desktop
  set screenX to item 1 of desktopBounds
  set screenY to item 2 of desktopBounds
  set screenW to (item 3 of desktopBounds) - screenX
  set screenH to (item 4 of desktopBounds) - screenY
end try
if exists application process "{target}" then
  tell application process "{target}"
    if exists window 1 then
      set hasWindow to true
      set windowPosition to position of window 1
      set windowSize to size of window 1
      set winX to item 1 of windowPosition
      set winY to item 2 of windowPosition
      set winW to item 1 of windowSize
      set winH to item 2 of windowSize
      try
        set notMinimized to not (value of attribute "AXMinimized" of window 1 as boolean)
      on error
        set notMinimized to true
      end try
    end if
  end tell
end if
return frontApp & tab & hasWindow & tab & notMinimized & tab & winX & tab & winY & tab & winW & tab & winH & tab & screenX & tab & screenY & tab & screenW & tab & screenH
end tell"#,
        target = target_app.replace('"', "")
    );
    let output = command_output("osascript", &["-e", &script]);
    let Some(output) = output else {
        return ViewabilityDecision::Unavailable {
            source: source.to_string(),
            reason: "macos_accessibility_unavailable".to_string(),
        };
    };
    let parts: Vec<&str> = output.split('\t').collect();
    let visible_ratio = visible_ratio_from_parts(&parts, 3).unwrap_or(0.0);
    let sample = ViewabilitySample {
        target_app: target_app.to_string(),
        foreground_app: parts.first().map(|s| s.trim().to_string()),
        window_visible: parts.get(1).map(|s| s.trim() == "true").unwrap_or(false),
        not_minimized: parts.get(2).map(|s| s.trim() == "true").unwrap_or(false),
        visible_ratio,
    };
    evaluate_viewability(&sample, source, min_visible_ratio)
}

#[cfg(target_os = "windows")]
fn probe_windows(target_app: &str, min_visible_ratio: f64) -> ViewabilityDecision {
    let source = "windows-foreground-helper";
    let script = r#"
Add-Type @"
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
public class W {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
}
"@
$h=[W]::GetForegroundWindow()
if ($h -eq [IntPtr]::Zero) { exit 2 }
$sb=New-Object System.Text.StringBuilder 512
[void][W]::GetWindowText($h,$sb,$sb.Capacity)
$processId=0
[void][W]::GetWindowThreadProcessId($h, [ref]$processId)
$processName=""
if ($processId -ne 0) {
  try { $processName=[Process]::GetProcessById($processId).ProcessName } catch {}
}
$rect=New-Object RECT
[void][W]::GetWindowRect($h, [ref]$rect)
$visible=[W]::IsWindowVisible($h)
$notMinimized=-not [W]::IsIconic($h)
$screenX=[W]::GetSystemMetrics(76)
$screenY=[W]::GetSystemMetrics(77)
$screenW=[W]::GetSystemMetrics(78)
$screenH=[W]::GetSystemMetrics(79)
$name=($processName + " " + $sb.ToString()).Trim()
$winW=$rect.Right - $rect.Left
$winH=$rect.Bottom - $rect.Top
Write-Output ($name + "`t" + $visible + "`t" + $notMinimized + "`t" + $rect.Left + "`t" + $rect.Top + "`t" + $winW + "`t" + $winH + "`t" + $screenX + "`t" + $screenY + "`t" + $screenW + "`t" + $screenH)
"#;
    let output = command_output("powershell.exe", &["-NoProfile", "-Command", script])
        .or_else(|| command_output("powershell", &["-NoProfile", "-Command", script]));
    let Some(output) = output else {
        return ViewabilityDecision::Unavailable {
            source: source.to_string(),
            reason: "foreground_window_unavailable".to_string(),
        };
    };
    let parts: Vec<&str> = output.split('\t').collect();
    let visible_ratio = visible_ratio_from_parts(&parts, 3).unwrap_or(0.0);
    let sample = ViewabilitySample {
        target_app: target_app.to_string(),
        foreground_app: parts.first().map(|s| s.trim().to_string()),
        window_visible: parts.get(1).map(|s| s.trim() == "True").unwrap_or(false),
        not_minimized: parts.get(2).map(|s| s.trim() == "True").unwrap_or(false),
        visible_ratio,
    };
    evaluate_viewability(&sample, source, min_visible_ratio)
}

#[cfg(all(unix, not(target_os = "macos")))]
fn probe_linux(target_app: &str, min_visible_ratio: f64) -> ViewabilityDecision {
    let source = "linux-x11-active-window-helper";
    if env::var_os("WAYLAND_DISPLAY").is_some() && env::var_os("DISPLAY").is_none() {
        return ViewabilityDecision::Unavailable {
            source: source.to_string(),
            reason: "wayland_global_window_inspection_unavailable".to_string(),
        };
    }
    if env::var_os("DISPLAY").is_none() {
        return ViewabilityDecision::Unavailable {
            source: source.to_string(),
            reason: "display_unavailable".to_string(),
        };
    }
    let active_window = command_output("xdotool", &["getactivewindow"]);
    let Some(active_window) = active_window else {
        return ViewabilityDecision::Unavailable {
            source: source.to_string(),
            reason: "xdotool_unavailable".to_string(),
        };
    };
    let active_window = active_window.trim();
    let window_name = command_output("xdotool", &["getwindowname", active_window]);
    let Some(window_name) = window_name else {
        return ViewabilityDecision::Unavailable {
            source: source.to_string(),
            reason: "active_window_name_unavailable".to_string(),
        };
    };
    let geometry = command_output("xdotool", &["getwindowgeometry", "--shell", active_window]);
    let display_geometry = command_output("xdotool", &["getdisplaygeometry"]);
    let visible_ratio = geometry
        .as_deref()
        .and_then(|geometry| visible_ratio_from_xdotool(geometry, display_geometry.as_deref()))
        .unwrap_or(0.0);
    let sample = ViewabilitySample {
        target_app: target_app.to_string(),
        foreground_app: Some(window_name),
        window_visible: true,
        not_minimized: true,
        visible_ratio,
    };
    evaluate_viewability(&sample, source, min_visible_ratio)
}

fn visible_ratio_from_parts(parts: &[&str], offset: usize) -> Option<f64> {
    Some(visible_ratio_for_rect(
        parse_part_f64(parts, offset)?,
        parse_part_f64(parts, offset + 1)?,
        parse_part_f64(parts, offset + 2)?,
        parse_part_f64(parts, offset + 3)?,
        parse_part_f64(parts, offset + 4)?,
        parse_part_f64(parts, offset + 5)?,
        parse_part_f64(parts, offset + 6)?,
        parse_part_f64(parts, offset + 7)?,
    ))
}

fn parse_part_f64(parts: &[&str], index: usize) -> Option<f64> {
    parts.get(index)?.trim().parse::<f64>().ok()
}

#[cfg(all(unix, not(target_os = "macos")))]
fn visible_ratio_from_xdotool(geometry: &str, display_geometry: Option<&str>) -> Option<f64> {
    let x = shell_value_f64(geometry, "X")?;
    let y = shell_value_f64(geometry, "Y")?;
    let width = shell_value_f64(geometry, "WIDTH")?;
    let height = shell_value_f64(geometry, "HEIGHT")?;
    let display = display_geometry?;
    let mut dims = display.split_whitespace();
    let screen_width = dims.next()?.parse::<f64>().ok()?;
    let screen_height = dims.next()?.parse::<f64>().ok()?;
    Some(visible_ratio_for_rect(
        x,
        y,
        width,
        height,
        0.0,
        0.0,
        screen_width,
        screen_height,
    ))
}

#[cfg(all(unix, not(target_os = "macos")))]
fn shell_value_f64(body: &str, key: &str) -> Option<f64> {
    let prefix = format!("{key}=");
    body.lines()
        .find_map(|line| line.strip_prefix(&prefix))
        .and_then(|value| value.trim().parse::<f64>().ok())
}

fn command_output(program: &str, args: &[&str]) -> Option<String> {
    let timeout = Duration::from_secs(parse_env_u64("ADTENTION_PROBE_TIMEOUT", 3).max(1));
    command_output_with_timeout(program, args, timeout)
}

fn command_output_with_timeout(program: &str, args: &[&str], timeout: Duration) -> Option<String> {
    let mut child = Command::new(program)
        .args(args)
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .ok()?;
    let started = Instant::now();
    loop {
        match child.try_wait() {
            Ok(Some(status)) => {
                let mut text = String::new();
                if let Some(mut stdout) = child.stdout.take() {
                    let _ = stdout.read_to_string(&mut text);
                }
                if !status.success() {
                    return None;
                }
                let text = text.trim().to_string();
                return if text.is_empty() { None } else { Some(text) };
            }
            Ok(None) if started.elapsed() >= timeout => {
                let _ = child.kill();
                let _ = child.wait();
                return None;
            }
            Ok(None) => thread::sleep(Duration::from_millis(50)),
            Err(_) => return None,
        }
    }
}

fn cache_dir() -> PathBuf {
    env::var_os("ADTENTION_CACHE")
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            let home = env::var_os("HOME")
                .or_else(|| env::var_os("USERPROFILE"))
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

fn parse_env_f64(name: &str, default: f64) -> f64 {
    env::var(name)
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(default)
}

fn target_app_name() -> String {
    env::var("ADTENTION_TARGET_APP").unwrap_or_else(|_| "Codex".to_string())
}

fn columns() -> Option<usize> {
    env::var("COLUMNS").ok().and_then(|s| s.parse().ok())
}

fn print_usage_and_exit() -> ! {
    eprintln!(
        "usage: adtention-codex <setup|refresh|render|mark-render|mark-viewable|title-daemon|viewability-check|viewability-daemon>"
    );
    std::process::exit(2);
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn command_output_returns_trimmed_text() {
        assert_eq!(
            command_output_with_timeout(
                "/bin/sh",
                &["-c", "printf 'hello\\n'"],
                Duration::from_secs(1),
            )
            .as_deref(),
            Some("hello")
        );
    }

    #[cfg(unix)]
    #[test]
    fn command_output_returns_none_after_timeout() {
        let started = Instant::now();

        let output = command_output_with_timeout(
            "/bin/sh",
            &["-c", "sleep 2; printf too-late"],
            Duration::from_millis(100),
        );

        assert_eq!(output, None);
        assert!(started.elapsed() < Duration::from_secs(2));
    }
}
