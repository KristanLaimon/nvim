#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_validate_valid_token() {
        let result = validate_token("valid_token");
        assert!(result.is_ok());
    }

    #[test]
    fn test_validate_empty_token() {
        let result = validate_token("");
        assert!(result.is_err());
    }

    #[test]
    fn test_claims_not_expired_on_creation() {
        let claims = AuthClaims::new("user");
        assert!(!claims.is_expired());
    }
}
