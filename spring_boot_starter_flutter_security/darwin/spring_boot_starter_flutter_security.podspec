#
# The iOS and macOS part of spring_boot_starter_flutter_security (one Swift source
# for both): the secret store on the Keychain, the DPoP key in the Secure
# Enclave or the Keychain, and the login window on ASWebAuthenticationSession. Swift Package Manager uses
# spring_boot_starter_flutter_security/Package.swift; CocoaPods uses this file.
#
Pod::Spec.new do |s|
  s.name             = 'spring_boot_starter_flutter_security'
  s.version          = '0.4.2'
  s.summary          = 'Security for Spring Boot Flutter apps: the Keychain secret store and the system login window.'
  s.description      = <<-DESC
The platform code of spring_boot_starter_flutter_security: secrets in the Keychain,
logins in ASWebAuthenticationSession.
                       DESC
  s.homepage         = 'https://github.com/farum-azula/spring_core_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'farum-azula' => 'https://github.com/farum-azula' }
  s.source           = { :path => '.' }
  s.source_files     = 'spring_boot_starter_flutter_security/Sources/spring_boot_starter_flutter_security/**/*.swift'
  s.resource_bundles = {'spring_boot_starter_flutter_security_privacy' => ['spring_boot_starter_flutter_security/Sources/spring_boot_starter_flutter_security/PrivacyInfo.xcprivacy']}
  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.frameworks = 'AuthenticationServices', 'CryptoKit', 'Security'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
