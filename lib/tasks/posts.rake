desc 'Update each post with latest markdown'
task 'posts:rebake' => :environment do
  ENV['RAILS_DB'] ? rebake_posts : rebake_posts_all_sites
end

desc 'Update each post with latest markdown and refresh oneboxes'
task 'posts:refresh_oneboxes' => :environment do
  ENV['RAILS_DB'] ? rebake_posts(invalidate_oneboxes: true) : rebake_posts_all_sites(invalidate_oneboxes: true)
end

desc 'Rebake all posts with a quote using a letter_avatar'
task 'posts:fix_letter_avatars' => :environment do
  return unless SiteSetting.external_system_avatars_enabled

  search = Post.where("user_id <> -1")
               .where("raw LIKE '%/letter\_avatar/%' OR cooked LIKE '%/letter\_avatar/%'")

  rebaked = 0
  total = search.count

  search.find_each do |post|
    rebake_post(post)
    print_status(rebaked += 1, total)
  end

  puts "", "#{rebaked} posts done!", ""
end

desc 'Rebake all posts matching string/regex'
task 'posts:rebake_match', [:pattern, :type] => [:environment] do |_,args|
  pattern = args[:pattern]
  type = args[:type]
  type = type.downcase if type
  if !pattern
    puts "ERROR: Expecting rake posts:rebake_match[pattern,type]"
    exit 1
  end

  if type == "regex"
    search = Post.where("raw ~ ?", pattern)
  elsif type == "string" || !type
    search = Post.where("raw ILIKE ?", "%#{pattern}%")
  else
    puts "ERROR: Expecting rake posts:rebake_match[pattern,type] where type is string or regex"
    exit 1
  end

  rebaked = 0
  total = search.count

  search.find_each do |post|
    rebake_post(post)
    print_status(rebaked += 1, total)
  end

  puts "", "#{rebaked} posts done!", ""
end

def rebake_posts_all_sites(opts = {})
  RailsMultisite::ConnectionManagement.each_connection do |db|
    rebake_posts(opts)
  end
end

def rebake_posts(opts = {})
  puts "Rebaking post markdown for '#{RailsMultisite::ConnectionManagement.current_db}'"

  disable_edit_notifications = SiteSetting.disable_edit_notifications
  SiteSetting.disable_edit_notifications = true

  total = Post.count
  rebaked = 0

  Post.find_each do |post|
    rebake_post(post, opts)
    print_status(rebaked += 1, total)
  end

  SiteSetting.disable_edit_notifications = disable_edit_notifications

  puts "", "#{rebaked} posts done!", "-" * 50
end

def rebake_post(post, opts = {})
  post.rebake!(opts)
rescue => e
  puts "", "Failed to rebake (topic_id: #{post.topic_id}, post_id: #{post.id})", e, e.backtrace.join("\n")
end

def print_status(current, max)
  print "\r%9d / %d (%5.1f%%)" % [current, max, ((current.to_f / max.to_f) * 100).round(1)]
end

desc 'normalize all markdown so <pre><code> is not used and instead backticks'
task 'posts:normalize_code' => :environment do
  lang = ENV['CODE_LANG'] || ''
  require 'import/normalize'

  puts "Normalizing"
  i = 0
  Post.where("raw like '%<pre>%<code>%'").each do |p|
    normalized = Import::Normalize.normalize_code_blocks(p.raw, lang)
    if normalized != p.raw
      p.revise(Discourse.system_user, { raw: normalized })
      putc "."
      i += 1
    end
  end

  puts
  puts "#{i} posts normalized!"
end

desc 'Remap all posts matching specific string'
task 'posts:remap', [:find, :replace] => [:environment] do |_,args|
  find = args[:find]
  replace = args[:replace]
  if !find || !replace
    puts "ERROR: Expecting rake posts:rebake_match[find,replace]"
    exit 1
  end

  puts "Remapping"
  i = 0
  Post.where("raw LIKE ?", "%#{find}%").each do |p|
    new_raw = p.raw.dup
    new_raw = new_raw.gsub!(/#{Regexp.escape(find)}/, replace) || new_raw

    if new_raw != p.raw
      p.revise(Discourse.system_user, { raw: new_raw }, { bypass_bump: true, skip_revision: true })
      putc "."
      i += 1
    end
  end
  puts "", "#{i} posts remapped!", ""
end
