use std::time::{SystemTime, UNIX_EPOCH};

const TOKEN_TTL_SECS: u64 = 3600;

pub struct AuthClaims {
    pub sub: String,
    pub exp: u64,
}

impl AuthClaims {
    pub fn is_expired(&self) -> bool {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        self.exp <= now
    }

    pub fn new(subject: &str) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs();
        Self {
            sub: subject.to_string(),
            exp: now + TOKEN_TTL_SECS,
        }
    }
}

pub fn validate_token(token: &str) -> Result<AuthClaims, String> {
    if token.is_empty() {
        return Err("empty token".to_string());
    }
    let claims = AuthClaims::new("user");
    if claims.is_expired() {
        return Err("expired".to_string());
    }
    Ok(claims)
}
