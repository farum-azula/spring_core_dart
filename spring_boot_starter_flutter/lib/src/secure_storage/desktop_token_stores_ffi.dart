import 'package:spring_boot_starter_flutter/src/secure_storage/linux_secret_service_token_store.dart';
import 'package:spring_boot_starter_flutter/src/secure_storage/windows_dpapi_token_store.dart';
import 'package:spring_boot_starter_oauth2_client/spring_boot_starter_oauth2_client.dart';

/// The Windows store: DPAPI-encrypted files.
TokenStore windowsTokenStore() => WindowsDpapiTokenStore();

/// The Linux store: the Secret Service through libsecret.
TokenStore linuxTokenStore() => LinuxSecretServiceTokenStore();
