require 'xcodeproj'
project = Xcodeproj::Project.open('Runner.xcodeproj')
target = project.targets.find { |t| t.name == 'VigoLockWatch' }

phase = target.resources_build_phase
existing = phase.files_references.find { |f| f.path != nil && f.path.include?('Assets.xcassets') }

if existing.nil?
    file_ref = project.new_file('VigoLockWatch/Assets.xcassets')
    phase.add_file_reference(file_ref, true)
    puts "Successfully linked Assets.xcassets to the resources phase!"
else
    puts "Assets.xcassets is already present."
end

target.build_configurations.each do |config|
    config.build_settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
end

project.save
puts "Project saved successfully."
