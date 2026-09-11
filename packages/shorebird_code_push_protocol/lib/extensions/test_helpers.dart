import 'package:meta/meta.dart';
import 'package:shorebird_code_push_protocol/shorebird_code_push_protocol.dart';

/// Constructs an [Organization] with arbitrary default values for testing.
///
/// Replaces the old `Organization.forTest` factory — since [Organization] is
/// now generated from the OpenAPI spec, test-only defaults live here
/// instead of on the generated class.
@visibleForTesting
Organization organizationForTest({
  int id = 42,
  String name = 'Test Organization',
  OrganizationType organizationType = OrganizationType.personal,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => Organization(
  id: id,
  name: name,
  organizationType: organizationType,
  createdAt: createdAt ?? DateTime.now(),
  updatedAt: updatedAt ?? DateTime.now(),
);

/// Constructs a [PrivateUser] with arbitrary default values for testing.
///
/// Replaces the old `PrivateUser.forTest` factory.
@visibleForTesting
PrivateUser privateUserForTest({
  int id = 42,
  String email = 'test@shorebird.dev',
  String jwtIssuer = 'https://accounts.google.com',
  bool hasActiveSubscription = false,
  String? displayName,
  String? stripeCustomerId,
  int? patchOverageLimit = 0,
}) => PrivateUser(
  id: id,
  email: email,
  jwtIssuer: jwtIssuer,
  hasActiveSubscription: hasActiveSubscription,
  displayName: displayName,
  stripeCustomerId: stripeCustomerId,
  patchOverageLimit: patchOverageLimit,
);

/// Projects a [PrivateUser] down to a [PublicUser] (drops sensitive
/// fields). Replaces the old `PublicUser.fromPrivateUser` factory.
PublicUser publicUserFromPrivateUser(PrivateUser fullUser) {
  return PublicUser(
    id: fullUser.id,
    email: fullUser.email,
    displayName: fullUser.displayName,
  );
}
