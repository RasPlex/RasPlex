#!/usr/bin/env ruby

require 'json'
require 'yaml'
require 'optparse'


config = YAML.load_file('github_auth.yml')
$auth = config['OAUTH_TOKEN']
$base_url = config['BASE_URL']
$upload_url = config['UPLOAD_URL']

def update_draft_release( version, content="stub", id=nil, prerelease=true)

  payload = {
    "tag_name"    => version,
    "name"        => version,
    "body"        => content,
    "draft"       => true, 
    "prerelease"  => prerelease,
  }

  if id.nil?
    response = `curl -s -d '#{payload.to_json}' -H "Authorization: token #{$auth}" -X POST "#{$base_url}"`
  else
    response = `curl -s -d '#{payload.to_json}' -H "Authorization: token #{$auth}" -X PATCH "#{$base_url}/#{id}"`
  end
  data = JSON.load(response)
  begin
    if data.has_key? 'id'
      puts "Updated release with id #{data['id']}"
    else
      puts "Failed to create draft release"
      exit
    end
  rescue
    puts "Error in query!"
    puts response
    exit
  end
  return data['id']

end

def add_asset(id, asset_path, shasum=false)


  name = File.basename(asset_path)

  if shasum
    checksum=`sha1sum #{asset_path} | awk '{print $1}'`.strip!
  else
    checksum=`md5sum #{asset_path} | awk '{print $1}'`.strip!
  end

  puts "Starting upload of #{name}"
  response=`curl --data-binary '@#{asset_path}' -H 'Authorization: token #{$auth}' -H 'Content-Type: application/gzip' -X POST '#{$upload_url}/#{id}/assets?name=#{name}'`
  data = JSON.load(response)
  begin
    if data.has_key? 'id'
      puts "Uploaded asset #{name} with id #{data['id']}"
    else
      puts "Failed to upload asset #{name}"
    end
  rescue
    puts "Error in query!"
    puts response
    exit
  end

  puts name, checksum
  return name, checksum


end

def create_release_notes(changes,  installname, installchecksum, updatename, updatechecksum)

  content = "changes:"

  File.open(changes).each do |change|
    content= content +"\n  - #{change.strip!}"
  end

  content = content+"\n\ninstall:"
  content = content+"\n  - file: #{installname}"
  content = content+"\n  - md5sum: #{installchecksum}"

  content = content+"\n\nupdate:"
  content = content+"\n  - file: #{updatename}"
  content = content+"\n  - shasum: #{updatechecksum}"

  return content
end


def create_and_push_tags(version)

  puts `git submodule foreach git tag RP-#{version}`
  puts `git submodule foreach git push origin --tags`
  puts `git commit -a -m 'Release #{version}'`
  puts `git tag #{version}`
  puts `git push origin --tags`
  puts `git push origin master`
  
end

def main(options)

#  create_and_push_tags(options[:version])
  id = update_draft_release(options[:version], "release notes")
  updatename, updatechecksum = add_asset(id, options[:update], true)
  installname, installchecksum = add_asset(id, options[:install])




  changes = create_release_notes(options[:changes], installname, installchecksum, updatename, updatechecksum )
  puts changes
  id = update_draft_release(options[:version], changes, id=id)
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: dorelease.rb [options]"

  opts.on('-v', '--version NAME', 'Version name') { |v| options[:version] = v }
  opts.on('-u', '--update_archive PATH', 'update archive') { |v| options[:update] = v }
  opts.on('-i', '--install_archive PATH', 'install archive') { |v| options[:install] = v }
  opts.on('-c', '--changelist PATH', 'changelist file (one change per line)') { |v| options[:changes] = v }

end.parse!
raise OptionParser::MissingArgument if options[:version].nil?
raise OptionParser::MissingArgument if options[:update].nil? or not File.exist? (options[:update])
raise OptionParser::MissingArgument if options[:install].nil? or not File.exist? (options[:install])

main(options)

#./dorelease.rb -v 0.3.9-rc1 -u OpenELEC.tv/tmp/rasplex-RPi.arm-wip.tar.gz -i OpenELEC.tv/tmp/rasplex-wip.img.gz -c changes.txt

