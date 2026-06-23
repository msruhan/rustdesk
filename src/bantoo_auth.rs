use hbb_common::{
    bail,
    config::{Config, LocalConfig},
    ResultType,
};
use serde_json::json;

pub const OUTGOING_DENIED: &str =
    "OTP sesi konsultasi wajib. Mulai sesi di web Bantoo terlebih dahulu.";

const BANTOO_API_DEFAULT: &str = "https://bantoo.in";
const SESSION_GRANT_KEY: &str = "bantoo-session-grant";
const SESSION_OTP_KEY: &str = "bantoo-session-otp";
const SESSION_UNLOCKED_KEY: &str = "bantoo-session-unlocked";

pub fn api_base() -> String {
    if let Ok(url) = std::env::var("BANTOO_API_URL") {
        let url = url.trim().trim_end_matches('/').to_owned();
        if !url.is_empty() {
            return url;
        }
    }
    if !crate::is_custom_client() {
        let url = crate::common::get_api_server(
            Config::get_option("api-server"),
            Config::get_option("custom-rendezvous-server"),
        );
        if url.is_empty() || crate::is_public(&url) {
            return "".to_owned();
        }
        return url;
    }
    let url = crate::common::get_api_server(
        Config::get_option("api-server"),
        Config::get_option("custom-rendezvous-server"),
    );
    if !url.is_empty() && !crate::is_public(&url) {
        return url;
    }
    BANTOO_API_DEFAULT.to_owned()
}

fn device_token() -> String {
    LocalConfig::get_option("bantoo-device-token")
}

pub fn auth_header() -> String {
    let token = device_token();
    if token.is_empty() {
        return "".to_owned();
    }
    format!("Authorization: Bearer {}", token)
}

pub fn clear_session_unlock() {
    LocalConfig::set_option(SESSION_GRANT_KEY.to_owned(), "".to_owned());
    LocalConfig::set_option(SESSION_OTP_KEY.to_owned(), "".to_owned());
    LocalConfig::set_option(SESSION_UNLOCKED_KEY.to_owned(), "".to_owned());
}

pub fn set_session_unlock(grant: &str, otp: &str) {
    LocalConfig::set_option(SESSION_GRANT_KEY.to_owned(), grant.to_owned());
    LocalConfig::set_option(SESSION_OTP_KEY.to_owned(), otp.to_owned());
    LocalConfig::set_option(SESSION_UNLOCKED_KEY.to_owned(), "Y".to_owned());
}

pub fn is_session_unlocked() -> bool {
    if !crate::is_custom_client() {
        return true;
    }
    LocalConfig::get_option(SESSION_UNLOCKED_KEY) == "Y"
        && !LocalConfig::get_option(SESSION_OTP_KEY).is_empty()
}

fn session_grant() -> String {
    LocalConfig::get_option(SESSION_GRANT_KEY)
}

fn session_otp() -> String {
    LocalConfig::get_option(SESSION_OTP_KEY)
}

async fn post_authorize(body: serde_json::Value) -> ResultType<bool> {
    if !crate::is_custom_client() {
        return Ok(true);
    }
    if !is_session_unlocked() {
        bail!("IndoDesk belum dibuka dengan OTP sesi konsultasi.");
    }
    let base = api_base();
    if base.is_empty() {
        bail!("Server Bantoo belum dikonfigurasi pada IndoDesk.");
    }
    let token = device_token();
    if token.is_empty() {
        bail!("Akun Bantoo belum dihubungkan. Buka web Bantoo untuk pairing.");
    }
    let mut payload = body;
    payload["deviceToken"] = json!(token);
    let grant = session_grant();
    if !grant.is_empty() {
        payload["grant"] = json!(grant);
    }
    let url = format!("{}/api/indodesk/authorize", base);
    let resp = crate::post_request(url, payload.to_string(), &auth_header()).await?;
    let parsed: serde_json::Value = serde_json::from_str(&resp).unwrap_or(json!({}));
    let allowed = parsed
        .get("data")
        .and_then(|d| d.get("allowed"))
        .and_then(|v| v.as_bool())
        .unwrap_or(false);
    if allowed {
        return Ok(true);
    }
    let reason = parsed
        .get("data")
        .and_then(|d| d.get("reason"))
        .and_then(|v| v.as_str())
        .unwrap_or("Koneksi IndoDesk ditolak");
    bail!("{}", reason);
}

pub fn outgoing_plain_password(ui_password: &str, saved_peer_password: &str) -> String {
    if !ui_password.is_empty() {
        return ui_password.to_owned();
    }
    if !saved_peer_password.is_empty() {
        return saved_peer_password;
    }
    session_otp()
}

pub async fn gate_outgoing(peer_id: &str, password: &str) -> ResultType<()> {
    let otp = if password.is_empty() {
        session_otp()
    } else {
        password.to_owned()
    };
    if otp.is_empty() {
        bail!("{}", OUTGOING_DENIED);
    }
    let peer = peer_id.replace(' ', "");
    post_authorize(json!({
        "direction": "outgoing",
        "peerId": peer,
        "password": otp,
    }))
    .await?;
    Ok(())
}

pub async fn gate_incoming(connecting_peer_id: &str) -> ResultType<()> {
    let peer = connecting_peer_id.replace(' ', "");
    post_authorize(json!({
        "direction": "incoming",
        "peerId": peer,
    }))
    .await?;
    Ok(())
}

pub async fn authorize_outgoing(peer_id: &str, password: &str) -> ResultType<()> {
    gate_outgoing(peer_id, password).await
}

pub async fn authorize_incoming(connecting_peer_id: &str) -> ResultType<()> {
    gate_incoming(connecting_peer_id).await
}

pub async fn confirm_pairing(
    code: &str,
    rustdesk_id: &str,
    device_uuid: &str,
    platform: &str,
) -> ResultType<()> {
    let base = api_base();
    if base.is_empty() {
        bail!("api-server belum dikonfigurasi");
    }
    let url = format!("{}/api/indodesk/pair/confirm", base);
    let body = json!({
        "code": code,
        "rustdeskId": rustdesk_id.replace(' ', ""),
        "deviceUuid": device_uuid,
        "platform": platform,
    });
    let resp = crate::post_request(url, body.to_string(), "").await?;
    let parsed: serde_json::Value = serde_json::from_str(&resp)?;
    let token = parsed
        .get("data")
        .and_then(|d| d.get("deviceToken"))
        .and_then(|v| v.as_str())
        .unwrap_or("");
    if token.is_empty() {
        bail!("Pairing gagal");
    }
    LocalConfig::set_option("bantoo-device-token".to_owned(), token.to_owned());
    Ok(())
}
