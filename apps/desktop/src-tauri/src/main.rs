#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use std::net::TcpStream;
use std::process::{Child, Command};
use std::sync::Mutex;
use std::time::{Duration, Instant};
use tauri::{Manager, RunEvent};
use url::Url;

struct ChildProcess(Mutex<Option<Child>>);

fn port_open(host: &str, port: u16) -> bool {
    TcpStream::connect((host, port)).is_ok()
}

fn wait_for_port(host: &str, port: u16, timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if port_open(host, port) {
            return true;
        }
        std::thread::sleep(Duration::from_millis(200));
    }
    false
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            let dsh_bin = std::env::var("DSH_BIN").expect("DSH_BIN is not set");
            let host = std::env::var("DSH_HOST").unwrap_or_else(|_| "127.0.0.1".to_string());
            let port: u16 = std::env::var("DSH_PORT")
                .unwrap_or_else(|_| "3080".to_string())
                .parse()
                .unwrap_or(3080);

            // Reuse an already-running dsh web (e.g. the home-manager systemd
            // service) instead of spawning a second instance that would fail to
            // bind the port.
            let spawned = if port_open(&host, port) {
                None
            } else {
                let child = Command::new(&dsh_bin)
                    .args(["web", "--host", &host, "--port", &port.to_string()])
                    .spawn()
                    .expect("failed to start dsh web");
                wait_for_port(&host, port, Duration::from_secs(15));
                Some(child)
            };

            app.manage(ChildProcess(Mutex::new(spawned)));

            let url = format!("http://{}:{}", host, port);
            tauri::WebviewWindowBuilder::new(
                app.handle(),
                "main",
                tauri::WebviewUrl::External(Url::parse(&url).expect("invalid dsh url")),
            )
            .title("DeepSeek Harness")
            .inner_size(1200.0, 800.0)
            .build()?;

            Ok(())
        })
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        .run(|app_handle, event| {
            if matches!(event, RunEvent::ExitRequested { .. } | RunEvent::Exit) {
                if let Some(state) = app_handle.try_state::<ChildProcess>() {
                    if let Some(mut child) = state.0.lock().unwrap().take() {
                        let _ = child.kill();
                        let _ = child.wait();
                    }
                }
            }
        });
}
