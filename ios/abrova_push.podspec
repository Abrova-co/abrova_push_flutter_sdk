Pod::Spec.new do |s|
  s.name             = 'abrova_push'
  s.version          = '0.1.27'
  s.summary          = 'Abrova Push notification plugin for Flutter'
  s.description      = 'Real-time push notifications, in-app messages, inbox, A/B testing, and more for Flutter apps'
  s.homepage         = 'https://abrova.ir/cloud/abrova-push'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Abrova' => 'support@abrova.ir' }
  s.source           = { :path => '.' }

  s.source_files     = 'abrova_push/Sources/abrova_push/**/*.swift', 'abrova_push/Sources/abrova_push_objc/**/*.{h,m}'
  s.public_header_files = 'abrova_push/Sources/abrova_push_objc/include/**/*.h'

  s.dependency 'Flutter'
  # Abrova Push iOS SDK (published on CocoaPods)
  s.dependency 'AbrovaPushSDK', '~> 0.1.18'

  s.platform         = :ios, '13.0'
  s.swift_version    = '5.0'
  s.frameworks       = 'UIKit', 'UserNotifications', 'PushKit', 'CallKit'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
