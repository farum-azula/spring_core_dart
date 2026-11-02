#
# The macOS part of spring_boot_starter_flutter: the window's title bar, size
# and drag (the desktop window properties). Swift Package Manager uses
# spring_boot_starter_flutter/Package.swift; CocoaPods uses this file.
#
Pod::Spec.new do |s|
  s.name             = 'spring_boot_starter_flutter'
  s.version          = '0.6.1'
  s.summary          = 'Spring Boot for Flutter apps: the desktop window from properties.'
  s.description      = <<-DESC
The platform code of spring_boot_starter_flutter: the window's title bar and sizes.
                       DESC
  s.homepage         = 'https://github.com/farum-azula/spring_core_dart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'farum-azula' => 'https://github.com/farum-azula' }
  s.source           = { :path => '.' }
  s.source_files     = 'spring_boot_starter_flutter/Sources/spring_boot_starter_flutter/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
