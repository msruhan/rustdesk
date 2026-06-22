use hbb_common::{
    bail,
    config::{Config, LocalConfig},
    ResultType,
};
use serde_json::json;

const BANTOO_API_DEFAULT: &str = "https://bantoo.in";

pub fn api_base() -> String {
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

async fn post_authorize(body: serde_json::Value) -> ResultType<bool> {
    if !crate::is_custom_client() {
        return Ok(true);
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

pub async fn authorize_outgoing(peer_id: &str, password: &str) -> ResultType<()> {
    if password.is_empty() {
        bail!("OTP sesi wajib diisi");
    }
    let peer = peer_id.replace(' ', "");
    post_authorize(json!({
        "direction": "outgoing",
        "peerId": peer,
        "password": password,
    }))
    .await?;
    Ok(())
}

pub async fn authorize_incoming(peer_id: &str) -> ResultType<()> {
    let peer = peer_id.replace(' ', "");
    post_authorize(json!({
        "direction": "incoming",
        "peerId": peer,
    }))
    .await?;
    Ok(())
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
