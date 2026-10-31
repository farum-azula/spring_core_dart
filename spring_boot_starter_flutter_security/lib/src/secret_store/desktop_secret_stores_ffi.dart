import 'package:spring_boot_starter_flutter_security/src/secret_store/linux_secret_service_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/windows_dpapi_secret_store.dart';

/// The Windows store: DPAPI-encrypted files in the folder of
/// [applicationId] (the 0.4.x folder's files moved there once).
SecretStore windowsSecretStore(String? applicationId) =>
    WindowsDpapiSecretStore(applicationId: applicationId);

/// The Linux store: the Secret Service through libsecret, items of
/// [applicationId] (those 0.4.x wrote under the executable's name moved
/// there once).
SecretStore linuxSecretStore(String? applicationId) => LinuxSecretServiceStore(
  application: applicationId,
  legacyApplication: LinuxSecretServiceStore.executableName(),
);
