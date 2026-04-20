/// The Shorebird CodePush protocol: models and message DTOs shared
/// between the CodePush server and the `shorebird_code_push_client`.
///
/// Everything under `lib/src/` is generated from the public OpenAPI
/// spec by `space_gen`. Hand-written additions (extensions on generated
/// enums, test helpers) live under `lib/extensions/` and are
/// re-exported from here.
library;

export 'package:shorebird_code_push_protocol/extensions/auth_provider.dart';
export 'package:shorebird_code_push_protocol/extensions/release_platform_extensions.dart';
export 'package:shorebird_code_push_protocol/extensions/test_helpers.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_app/create_app_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_app_collaborator/create_app_collaborator_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_channel/create_channel_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_patch/create_patch_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_patch/create_patch_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_patch_artifact/create_patch_artifact_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_patch_artifact/create_patch_artifact_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_release/create_release_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_release/create_release_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_release_artifact/create_release_artifact_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_release_artifact/create_release_artifact_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/create_user/create_user_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/error_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_apps/get_apps_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_gcp_download_speed_test_url/get_gcp_download_speed_test_url200_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_gcp_upload_speed_test_url/get_gcp_upload_speed_test_url200_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_organization_apps/get_organization_apps_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_organization_users/get_organization_users_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_organizations_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_release/get_release_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_release_artifacts/get_release_artifacts_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_release_patches/get_release_patches_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/get_releases/get_releases_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/patch_check/patch_check_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/patch_check/patch_check_response.dart';
export 'package:shorebird_code_push_protocol/src/messages/promote_patch/promote_patch_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/update_app_collaborator/update_app_collaborator_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/update_patch/update_patch_request.dart';
export 'package:shorebird_code_push_protocol/src/messages/update_release/update_release_request.dart';
export 'package:shorebird_code_push_protocol/src/models/app.dart';
export 'package:shorebird_code_push_protocol/src/models/app_collaborator_role.dart';
export 'package:shorebird_code_push_protocol/src/models/app_metadata.dart';
export 'package:shorebird_code_push_protocol/src/models/channel.dart';
export 'package:shorebird_code_push_protocol/src/models/organization.dart';
export 'package:shorebird_code_push_protocol/src/models/organization_membership.dart';
export 'package:shorebird_code_push_protocol/src/models/organization_type.dart';
export 'package:shorebird_code_push_protocol/src/models/organization_user.dart';
export 'package:shorebird_code_push_protocol/src/models/patch.dart';
export 'package:shorebird_code_push_protocol/src/models/patch_artifact.dart';
export 'package:shorebird_code_push_protocol/src/models/patch_check_metadata.dart';
export 'package:shorebird_code_push_protocol/src/models/private_user.dart';
export 'package:shorebird_code_push_protocol/src/models/public_user.dart';
export 'package:shorebird_code_push_protocol/src/models/release.dart';
export 'package:shorebird_code_push_protocol/src/models/release_artifact.dart';
export 'package:shorebird_code_push_protocol/src/models/release_patch.dart';
export 'package:shorebird_code_push_protocol/src/models/release_platform.dart';
export 'package:shorebird_code_push_protocol/src/models/release_status.dart';
export 'package:shorebird_code_push_protocol/src/models/role.dart';

/// Parsed JSON data.
typedef Json = Map<String, dynamic>;
