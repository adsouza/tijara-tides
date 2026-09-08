#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{
    menu::{MenuBuilder, MenuItemBuilder, SubmenuBuilder},
    Manager, Url, WebviewUrl, WebviewWindowBuilder,
};

// Remote pages receive no Tauri capabilities, commands, shell, or filesystem API.
// Keep transport policy in Rust as well as the launcher's validation.
fn allowed_navigation(url: &Url) -> bool {
    if !url.username().is_empty() || url.password().is_some() {
        return false;
    }
    match url.scheme() {
        "https" => true,
        "http" => matches!(url.host_str(), Some("localhost" | "127.0.0.1" | "[::1]")),
        "tauri" => url.host_str() == Some("localhost"),
        _ => false,
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(
            tauri_plugin_window_state::Builder::default()
                .with_state_flags(
                    tauri_plugin_window_state::StateFlags::SIZE
                        | tauri_plugin_window_state::StateFlags::POSITION
                        | tauri_plugin_window_state::StateFlags::MAXIMIZED,
                )
                .build(),
        )
        .setup(|app| {
            let window =
                WebviewWindowBuilder::new(app, "main", WebviewUrl::App("index.html".into()))
                    .title("Tijara Tides")
                    .inner_size(1200.0, 800.0)
                    .min_inner_size(640.0, 480.0)
                    .on_navigation(allowed_navigation)
                    .build()?;
            let mut launcher_url = window.url()?;
            // Settings must not trigger the launcher’s automatic reconnection.
            launcher_url.set_fragment(Some("settings"));
            let settings = MenuItemBuilder::with_id("connection", "Connection Settings…")
                .accelerator("CmdOrCtrl+Shift+C")
                .build(app)?;
            let reload = MenuItemBuilder::with_id("reload", "Reload")
                .accelerator("CmdOrCtrl+R")
                .build(app)?;
            let game = SubmenuBuilder::new(app, "Tijara Tides")
                .item(&settings)
                .item(&reload)
                .separator()
                .quit()
                .build()?;
            let edit = SubmenuBuilder::new(app, "Edit")
                .undo()
                .redo()
                .separator()
                .cut()
                .copy()
                .paste()
                .select_all()
                .build()?;
            app.set_menu(MenuBuilder::new(app).item(&game).item(&edit).build()?)?;
            app.on_menu_event(move |app, event| {
                if let Some(window) = app.get_webview_window("main") {
                    let result = match event.id().as_ref() {
                        "connection" => window.navigate(launcher_url.clone()),
                        "reload" => window.reload(),
                        _ => Ok(()),
                    };
                    if let Err(error) = result {
                        eprintln!("Window navigation failed: {error}");
                    }
                }
            });
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("failed to run Tijara Tides");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn allows_https_and_explicit_loopback_development() {
        for address in [
            "https://game.example/",
            "http://localhost:4000/",
            "http://127.0.0.1:4011/",
            "http://[::1]:4000/",
            "tauri://localhost/index.html",
        ] {
            assert!(allowed_navigation(&address.parse().unwrap()), "{address}");
        }
    }

    #[test]
    fn rejects_cleartext_remote_servers_credentials_and_non_web_schemes() {
        for address in [
            "http://game.example/",
            "http://localhost.evil.example/",
            "https://user:secret@game.example/",
            "file:///etc/passwd",
            "javascript:alert(1)",
            "tauri://evil/index.html",
        ] {
            assert!(!allowed_navigation(&address.parse().unwrap()), "{address}");
        }
    }
}
