/// {@template jwks_format}
/// The JWKS response format used by an auth provider's public key endpoint.
///
/// Each value maps to a specific [PublicKeyStore] subclass that knows how to
/// parse that format.
/// {@endtemplate}
enum JwksFormat {
  /// Google's format: a flat JSON object mapping key IDs to PEM certificate
  /// strings.
  keyValue,

  /// Microsoft Entra ID's format: a JWK Set containing X.509 certificate
  /// chains (`x5c`/`x5t` fields).
  jwkCertificate,

  /// Shorebird auth's format: a JWK Set with bare RSA public key parameters
  /// (`n`, `e`, `kid`, `kty`, `use`; no certificates).
  rsaJwk,
}
