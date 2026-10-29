import 'package:spring_boot_starter_flutter_security/src/secret_store/linux_secret_service_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/secret_store.dart';
import 'package:spring_boot_starter_flutter_security/src/secret_store/windows_dpapi_secret_store.dart';

/// The Windows store: DPAPI-encrypted files.
SecretStore windowsSecretStore() => WindowsDpapiSecretStore();

/// The Linux store: the Secret Service through libsecret.
SecretStore linuxSecretStore() => LinuxSecretServiceStore();
