# Comtech: adds the screen sharing broadcast extension to RustDesk's iOS
# project and embeds it in the app. Run on the macOS runner (CocoaPods
# brings the xcodeproj gem) from the RustDesk source folder:
#     ruby add_broadcast.rb
require 'fileutils'
require 'xcodeproj'

here = File.dirname(File.expand_path(__FILE__))
ios = File.join('flutter', 'ios')
dir = File.join(ios, 'ComtechBroadcast')
FileUtils.mkdir_p(dir)
FileUtils.cp(File.join(here, 'SampleHandler.swift'), dir)
FileUtils.cp(File.join(here, 'Info.plist'), dir)

# the app's version, which an extension has to match
version = File.read(File.join('flutter', 'pubspec.yaml'))[/^version:\s*(\S+)/, 1] || '1.0.0+1'
name, build = version.split('+')

proj = Xcodeproj::Project.open(File.join(ios, 'Runner.xcodeproj'))
app = proj.targets.find { |t| t.name == 'Runner' } or abort('no Runner target')
abort('already added') if proj.targets.any? { |t| t.name == 'ComtechBroadcast' }

ext = proj.new_target(:app_extension, 'ComtechBroadcast', :ios, '13.0')
group = proj.main_group.new_group('ComtechBroadcast', 'ComtechBroadcast')
ext.add_file_references([group.new_file('SampleHandler.swift')])
group.new_file('Info.plist')
ext.add_system_frameworks(%w[ReplayKit CoreMedia CoreVideo VideoToolbox AVFoundation AudioToolbox
                             CoreFoundation Foundation Security SystemConfiguration Metal QuartzCore UIKit])

lib = '$(PROJECT_DIR)/../../target/aarch64-apple-ios/release/liblibrustdesk.a'
ext.build_configurations.each do |c|
  s = c.build_settings
  s['INFOPLIST_FILE'] = 'ComtechBroadcast/Info.plist'
  s['PRODUCT_NAME'] = 'ComtechBroadcast'
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.carriez.flutterHbb.broadcast'
  s['MARKETING_VERSION'] = name
  s['CURRENT_PROJECT_VERSION'] = build || '1'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['SKIP_INSTALL'] = 'YES'
  s['ENABLE_BITCODE'] = 'NO'
  s['DEAD_CODE_STRIPPING'] = 'YES'
  s['STRIP_STYLE'] = 'non-global'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'NO'
  s['CODE_SIGN_STYLE'] = 'Manual'
  s['CODE_SIGN_IDENTITY'] = ''
  s['CODE_SIGNING_REQUIRED'] = 'NO'
  s['CODE_SIGNING_ALLOWED'] = 'NO'
  s['OTHER_LDFLAGS'] = ['$(inherited)', lib, '-lc++', '-lsqlite3', '-lresolv', '-lz', '-liconv', '-lbz2']
end

app.add_dependency(ext)
embed = app.new_copy_files_build_phase('Embed App Extensions')
embed.symbol_dst_subfolder_spec = :plug_ins
embed.add_file_reference(ext.product_reference).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
# before Flutter's script phases, or Xcode finds a build cycle
app.build_phases.delete(embed)
at = app.build_phases.index { |p| p.display_name == 'Embed Frameworks' } || app.build_phases.index { |p| p.display_name == 'Resources' }
app.build_phases.insert(at + 1, embed)

proj.save
puts "added the ComtechBroadcast extension (#{name} #{build})"
