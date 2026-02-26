#!/usr/bin/env ruby

require 'yaml'

require 'optparse'

def check_deps
  raise "Please install tmux" unless `which tmux` != ""
end


def current_session
  `test -n "\${TMUX+set}" && tmux display-message -p '#S'`.strip
end

def session_exists? name
  # tmux has-session doesn't work as it returns true for substrings
  `tmux list-sessions -F "#S"`.split("\n").include? name
end


# Runs command in current shell
def run cmd, args=[]
  cmd = "#{cmd} #{args.join ' '}".strip
  puts cmd
  `#{cmd}`
end


# Sends keys to tmux pane
def send_to_pane pane, cmd
  cmd = "'#{cmd}'".gsub(/'''/, '"\'"')
  cmd = "#{cmd} 'Enter'"
  run "tmux send-keys", ["-t #{pane}", cmd]
end


# Runs a command within shell inside tmux
def run_in_pane pane, cmds
  cmds = [ cmds ] unless cmds.is_a? Array
  cmds.each do |cmd|
    send_to_pane pane, cmd
  end
end

def helper_dir
  File.expand_path('./helpers', File.dirname(__FILE__))
end

def profile_dir
  File.expand_path('~/.tmux-profiles', File.dirname(__FILE__))
end

def system_profile_dir
  File.expand_path('./profiles', File.dirname(__FILE__))
end

def load_helpers
  out = ''
  Dir.glob "#{helper_dir}/*.yaml" do |filename|
    key = File.basename(filename).gsub '.yaml', ''
    out = "helper_#{key}: &#{key}\n"
    File.readlines(filename).each do |line|
      out += '  ' + line
    end
  end
  out
end

# Loads profile by name
def load_profile profile_name, only_session: nil, attach: nil, force_attach: false, no_attach: false

  default_window = { "name" => "default" }
  yaml_data = ''

  yaml_data += load_helpers

  begin
    yaml_data +=  File.read "#{profile_dir}/#{profile_name}.yaml"
  rescue
    begin
      yaml_data +=  File.read "#{system_profile_dir}/#{profile_name}.yaml"
    rescue
      raise "Profile '#{profile_name}' doesn't exist. Is it in your '~/.tmux-profiles' directory?"
    end
  end

  begin
    profile = YAML.load yaml_data
  rescue Exception => e
    raise e
    raise "Profile '#{profile_name}' isn't valid YAML"
  end

  sessions = profile["sessions"]

  if only_session
    sessions = sessions.select { |s| s["name"] == only_session }
    raise "Session '#{only_session}' not found in profile '#{profile_name}'" if sessions.empty?
  end

  # initialize sessions
  sessions.each do |session|

    if session_exists? session["name"]
      puts "Session '#{session["name"]}' exists."
      next
    end

    window = session["windows"].first || default_window

    # get current terminal height/width
    w = `tput cols`.strip
    h = `tput lines`.strip

    current_dir = session["dir"] || window["dir"]

    # run setup command for session
    setup_cmd = session["setup_cmd"]
    puts setup_cmd
    if setup_cmd
      run "cd #{current_dir} && #{setup_cmd}"
    end

    # create session (uses session dir as default for new windows)
    args = []
    args << "-s #{session["name"]}"
    args << "-n #{window["name"]}"
    args << "-c #{current_dir}" unless current_dir.nil?
    args << "-x #{w}"
    args << "-y #{h}"
    args << "-d"
    run "tmux new-session", args

    # if first window has its own dir, respawn its pane with the correct directory
    first_window_dir = window["dir"]
    if first_window_dir && first_window_dir != current_dir
      run "tmux respawn-pane", ["-k", "-c #{first_window_dir}", "-t #{session["name"]}:#{window["name"]}"]
    end

    # create more windows
    session["windows"][1..-1].each do |new_window|
      current_dir = new_window["dir"] || session["dir"]
      args = []
      args << "-t #{session["name"]}"
      args << "-n #{new_window["name"]}"
      args << "-c #{current_dir}" unless current_dir.nil?
      args << "-d"
      run "tmux new-window", args
    end

    # initialize windows
    session["windows"].each do |new_window|
      n = "#{session["name"]}:#{new_window["name"]}"

      run_in_pane n, new_window["cmd"] unless new_window["cmd"].nil?
      send_to_pane n, new_window["send"] unless new_window["send"].nil?

      panes = new_window["panes"] || []
      panes.each do |pane|
        current_dir = pane["dir"] || new_window["dir"] || session["dir"]
        args = []
        args << "-t #{n}"
        args << "-c #{current_dir}" unless current_dir.nil?
        args << "-#{ pane["split"][0] || "h" } "
        args << "-l #{pane["size"]} " unless pane["size"].nil?
        run "tmux split-window", args
        cmds = pane["cmd"]
        run_in_pane n, cmds unless cmds.nil?
        send = pane["send"]
        send_to_pane n, send unless send.nil?
      end
    end

  end


  # Resolve which session to attach to (first match wins):
  # 1. --no-attach → skip entirely
  # 2. --attach=X → attach/switch to X (forced)
  # 3. --attach → force attach to the auto-determined session
  # 4. SESSION arg → attach to the filtered session
  # 5. Top-level attach: from YAML
  # 6. Deprecated per-session attach: true (with warning)
  # 7. First session in the loaded list
  #
  # force_attach (--attach with or without value) means always attach/switch,
  # even when already inside tmux.
  return if no_attach

  attach_to = nil

  if attach
    attach_to = attach
  elsif only_session
    attach_to = only_session
  elsif profile["attach"]
    attach_to = profile["attach"]
  else
    sessions.each do |session|
      if session["attach"]
        $stderr.puts "Warning: 'attach: true' on session '#{session["name"]}' is deprecated. Use top-level 'attach: #{session["name"]}' instead."
        attach_to = session["name"]
        break
      end
    end
    attach_to = sessions.first["name"] if attach_to.nil? && !sessions.empty?
  end

  return if attach_to.nil?

  if force_attach
    # --attach (with or without =SESSION) always attaches/switches
    if current_session.empty?
      run "tmux attach", ["-t #{attach_to}"]
    elsif current_session != attach_to
      run "tmux switch-client", ["-t #{attach_to}"]
    end
  else
    # No --attach flag: only attach if not already inside tmux
    if current_session.empty?
      run "tmux attach", ["-t #{attach_to}"]
    end
  end

end


options = {}
parser = OptionParser.new do |opts|

  opts.banner = "Usage: #{ File.basename __FILE__ } [options] PROFILE [SESSION]"

  opts.on("-l", "--list", "List available profiles") do |l|
    options[:list] = l
  end

  opts.on("-a", "--attach [SESSION]", "Force attach/switch (optionally to a specific session)") do |s|
    options[:force_attach] = true
    options[:attach] = s
  end

  opts.on("--no-attach", "Do not attach to any session after loading") do
    options[:no_attach] = true
  end

end


if __FILE__ == $0

  check_deps()
  parser.parse! ARGV

  if options[:list]
    puts Dir.new(profile_dir)
    .select { |f| f =~ /\.yaml$/ }
    .map { |f| f.sub ".yaml", "" }
    .join "\n"
  elsif ARGV.length > 0
    run "tmux start-server"
    profile_name = ARGV[0]
    only_session = ARGV[1]
    load_profile profile_name, only_session: only_session, attach: options[:attach], force_attach: !!options[:force_attach], no_attach: !!options[:no_attach]
  else
    puts parser
  end
end

